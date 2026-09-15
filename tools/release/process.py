from __future__ import annotations

import os
import subprocess
import threading
import time
from contextlib import nullcontext
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, BinaryIO

from .common import ReleaseError, require, write_json


@dataclass(frozen=True)
class ProcessResult:
    pid: int
    exit_code: int | None
    started_at: str
    started_ns: int
    wall_seconds: float
    stdout: bytes
    stderr: bytes
    stdout_complete: bool
    stderr_complete: bool
    error: str

    @property
    def ok(self) -> bool:
        return not self.error and self.exit_code == 0 and self.stdout_complete and self.stderr_complete

    def metadata(self) -> dict[str, Any]:
        return {
            "processId": self.pid,
            "exitCode": self.exit_code,
            "startedAt": self.started_at,
            "wallSeconds": round(self.wall_seconds, 6),
            "stdoutComplete": self.stdout_complete,
            "stderrComplete": self.stderr_complete,
            "outputComplete": self.stdout_complete and self.stderr_complete,
            "stdoutBytes": len(self.stdout),
            "stderrBytes": len(self.stderr),
            "error": self.error,
            "ownership": "Original subprocess.Popen object/handle; no late PID lookup.",
        }


class _Pipe:
    def __init__(self, stream: BinaryIO, limit: int) -> None:
        self.stream = stream
        self.limit = limit
        self.data = bytearray()
        self.lock = threading.Lock()
        self.done = threading.Event()
        self.error = ""
        self.thread = threading.Thread(target=self._read, daemon=True, name="futsal-pipe-reader")
        self.thread.start()

    def _read(self) -> None:
        try:
            while chunk := self.stream.read(65536):
                with self.lock:
                    if len(self.data) + len(chunk) > self.limit:
                        self.error = "Limite de salida excedido."
                        break
                    self.data.extend(chunk)
        except OSError as exc:
            with self.lock:
                self.error = f"Error de lectura del pipe: {exc}"
        finally:
            self.stream.close()
            self.done.set()

    def snapshot(self) -> tuple[bytes, bool, str]:
        with self.lock:
            return bytes(self.data), self.done.is_set() and not self.error, self.error

    def failure(self) -> str:
        with self.lock:
            return self.error


def run_process(arguments: list[str], cwd: Path, *, timeout: float,
                environment: dict[str, str] | None = None,
                output_limit: int = 32 * 1024 * 1024, cleanup_seconds: float = 1.0,
                input_file: Path | None = None) -> ProcessResult:
    require(timeout > 0 and output_limit > 0 and cleanup_seconds > 0, "Limites de proceso invalidos.")
    started_ns = time.time_ns()
    started_at = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    with input_file.open("rb") if input_file is not None else nullcontext(subprocess.DEVNULL) as stdin:
        process = subprocess.Popen(
            arguments, cwd=cwd, env=environment, stdin=stdin,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0, shell=False,
        )
    assert process.stdout is not None and process.stderr is not None
    stdout = _Pipe(process.stdout, output_limit)
    stderr = _Pipe(process.stderr, output_limit)
    error = ""
    deadline = started + timeout
    try:
        while True:
            exit_code = process.poll()
            pipe_error = stdout.failure() or stderr.failure()
            if pipe_error:
                error = pipe_error
                break
            if exit_code is not None and stdout.done.is_set() and stderr.done.is_set():
                if exit_code != 0:
                    error = f"Proceso termino con exit {exit_code}."
                break
            if exit_code is not None and exit_code != 0:
                error = f"Proceso termino con exit {exit_code} sin EOF completo."
                break
            if time.monotonic() >= deadline:
                error = f"Deadline {timeout:g}s vencido (proceso y EOF)."
                break
            time.sleep(min(0.01, max(0, deadline - time.monotonic())))
    finally:
        cleanup_deadline = time.monotonic() + cleanup_seconds
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=max(0.001, cleanup_deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                error = (error + " No termino el proceso propietario durante la limpieza.").strip()
        for pipe in (stdout, stderr):
            pipe.thread.join(timeout=max(0, cleanup_deadline - time.monotonic()))
    out, out_complete, out_error = stdout.snapshot()
    err, err_complete, err_error = stderr.snapshot()
    if not out_complete or not err_complete:
        error = (error + " EOF incompleto; drenaje final acotado, no GetResult/communicate ilimitado.").strip()
    error = error or out_error or err_error
    return ProcessResult(
        process.pid, process.poll(), started_at, started_ns, time.monotonic() - started,
        out, err, out_complete, err_complete, error,
    )


def recorded_process(arguments: list[str], cwd: Path, evidence: Path, *, timeout: float,
                     environment: dict[str, str] | None = None) -> ProcessResult:
    require(not evidence.exists(), f"Evidencia ya existente: {evidence}")
    evidence.mkdir(parents=True)
    print(f"INICIO {evidence.name}: plazo {timeout:g}s", flush=True)
    result = run_process(arguments, cwd, timeout=timeout, environment=environment)
    (evidence / "stdout.log").write_bytes(result.stdout)
    (evidence / "stderr.log").write_bytes(result.stderr)
    write_json(evidence / "process.json", {
        **result.metadata(), "arguments": arguments, "workingDirectory": str(cwd),
    })
    require(result.ok, f"{evidence.name}: {result.error}; logs en {evidence}")
    print(f"FIN {evidence.name}: exit 0, EOF completo, {result.wall_seconds:.3f}s", flush=True)
    return result


class WindowsAvailability:
    """Solicitud temporal; en otros hosts no carga APIs de Windows."""

    def __init__(self) -> None:
        self.metadata: dict[str, Any] = {
            "applicable": os.name == "nt", "acquired": False, "released": False,
            "changesGlobalPowerPolicy": False, "displayRequested": False,
        }
        self.handle: int | None = None
        self.requests: list[int] = []
        self.kernel: Any = None

    def __enter__(self) -> WindowsAvailability:
        if os.name != "nt":
            return self
        import ctypes
        from ctypes import wintypes

        class Detailed(ctypes.Structure):
            _fields_ = [("LocalizedReasonModule", wintypes.HMODULE),
                        ("LocalizedReasonId", wintypes.ULONG), ("ReasonStringCount", wintypes.ULONG),
                        ("ReasonStrings", ctypes.POINTER(wintypes.LPWSTR))]

        class ReasonValue(ctypes.Union):
            _fields_ = [("SimpleReasonString", wintypes.LPWSTR), ("Detailed", Detailed)]

        class Reason(ctypes.Structure):
            _fields_ = [("Version", wintypes.ULONG), ("Flags", wintypes.DWORD),
                        ("Value", ReasonValue)]

        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.PowerCreateRequest.argtypes = [ctypes.POINTER(Reason)]
        kernel.PowerCreateRequest.restype = wintypes.HANDLE
        for name in ("PowerSetRequest", "PowerClearRequest"):
            function = getattr(kernel, name)
            function.argtypes = [wintypes.HANDLE, ctypes.c_int]
            function.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel.CloseHandle.restype = wintypes.BOOL
        self.kernel = kernel
        reason = Reason(0, 1, ReasonValue(SimpleReasonString="Futsal: validacion acotada de release"))
        self.handle = kernel.PowerCreateRequest(ctypes.byref(reason))
        require(self.handle not in (None, ctypes.c_void_p(-1).value),
                f"PowerCreateRequest fallo: {ctypes.get_last_error()}")
        try:
            for request in (1, 3):
                require(bool(kernel.PowerSetRequest(self.handle, request)),
                        f"PowerSetRequest {request} fallo: {ctypes.get_last_error()}")
                self.requests.append(request)
            self.metadata["acquired"] = True
        except ReleaseError:
            self.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, *_args: Any) -> None:
        if self.handle is None:
            return
        errors = []
        for request in reversed(self.requests):
            if not self.kernel.PowerClearRequest(self.handle, request):
                errors.append(f"PowerClearRequest {request}")
        if not self.kernel.CloseHandle(self.handle):
            errors.append("CloseHandle")
        self.handle = None
        self.metadata["released"] = not errors
        require(not errors, "Fallo al liberar disponibilidad: " + ", ".join(errors))
