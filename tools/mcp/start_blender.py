"""Own one attached Blender process; never reuse or terminate a user's existing one."""

import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "tools" / "mcp" / "runtime"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def check_port_free():
    """Fail fast only; the addon's exclusive bind arbitrates overlapping starts."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        if os.name == "nt":
            if not hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
                raise RuntimeError("Windows exclusive socket binding is unavailable.")
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            probe.bind(("127.0.0.1", 9876))
        except OSError as error:
            raise RuntimeError("Port 9876 is already in use. Existing processes have not been touched.") from error


def wait_until_ready(process, ready_file, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Blender PID {process.pid} exited during startup ({process.returncode}).")
        if ready_file.is_file():
            try:
                ready = read_json(ready_file)
                if ready["pid"] != process.pid or (ready["host"], ready["port"]) != ("127.0.0.1", 9876):
                    raise RuntimeError("Blender readiness file does not match the owned process and loopback port.")
                with socket.create_connection(("127.0.0.1", 9876), timeout=1):
                    return ready
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(0.2)
    raise TimeoutError(f"Blender did not become responsive within {timeout} seconds.")


def stop_owned_process(process, stop_file):
    if process.poll() is None:
        stop_file.touch()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-test", action="store_true")
    parser.add_argument("--blend-file", type=Path)
    parser.add_argument("--startup-timeout", type=int, default=90)
    args = parser.parse_args()
    if args.smoke_test and args.blend_file:
        parser.error("A smoke test must use an isolated factory scene, never a user's .blend file.")
    if not 10 <= args.startup_timeout <= 300:
        parser.error("--startup-timeout must be between 10 and 300 seconds.")
    if args.blend_file and (not args.blend_file.is_file() or args.blend_file.suffix.lower() != ".blend"):
        parser.error("--blend-file must name an existing .blend file.")
    blender = read_json(ROOT / "tools" / "blender" / "local.json")
    local = read_json(ROOT / "tools" / "mcp" / "local.json")
    executable = Path(blender["blenderPath"])
    if not executable.is_file():
        raise RuntimeError("Saved Blender path is missing. Rerun Install-Blender.ps1.")
    if hashlib.sha256(executable.read_bytes()).hexdigest() != blender["binarySha256"]:
        raise RuntimeError("Blender binary changed since verification; rerun the verified installer explicitly.")
    addon = Path(local["addonPath"])
    if not addon.is_file() or hashlib.sha256(addon.read_bytes()).hexdigest() != local["addonSha256"]:
        raise RuntimeError("The installed addon changed; inspect it before rerunning Install-Mcp.ps1.")
    check_port_free()
    run_dir = RUNTIME / "sessions" / f"blender run-{uuid.uuid4().hex}"
    run_dir.mkdir(parents=True)
    ready_file, stop_file = run_dir / "ready.json", run_dir / "stop"
    log_file = run_dir / "blender.log"
    work = run_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update(
        TEMP=str(work), TMP=str(work), DISABLE_TELEMETRY="true",
        BLENDER_MCP_SAFE_MODE="1", PYTHONUNBUFFERED="1",
    )
    command = [str(executable), "--disable-autoexec", "--python-exit-code", "1"]
    if args.smoke_test:
        command += ["--factory-startup"]
    if args.blend_file:
        command += [str(args.blend_file.resolve())]
    command += [
        "--python", str(ROOT / "tools" / "blender" / "configure_blender.py"), "--", "serve",
        "--ready-file", str(ready_file), "--stop-file", str(stop_file),
    ]
    process = None
    try:
        with log_file.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(
                command, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                stdout=log, stderr=subprocess.STDOUT,
            )
            try:
                wait_until_ready(process, ready_file, args.startup_timeout)
                print(f"Blender PID {process.pid} responsive at 127.0.0.1:9876 (attached).", flush=True)
                if args.smoke_test:
                    from smoke_test import run_smoke

                    result = asyncio.run(asyncio.wait_for(run_smoke(expect_default_scene=True), timeout=120))
                    print(json.dumps(result, indent=2), flush=True)
                else:
                    print("Close this Blender window to stop. Save your work before Ctrl+C.", flush=True)
                    while process.poll() is None:
                        time.sleep(0.5)
                    if process.returncode:
                        raise RuntimeError(f"Blender exited with code {process.returncode}.")
            except KeyboardInterrupt:
                print("Stopping only this launcher's Blender instance.", flush=True)
            finally:
                stop_owned_process(process, stop_file)
                ready_file.unlink(missing_ok=True)
                stop_file.unlink(missing_ok=True)
                if args.smoke_test:
                    shutil.rmtree(work)
                state = {
                    "pid": process.pid, "running": process.poll() is None,
                    "exitCode": process.returncode, "host": "127.0.0.1", "port": 9876,
                    "closedAt": datetime.now(timezone.utc).isoformat(), "log": str(log_file),
                    "workDirectory": str(work), "workDirectoryRetained": work.exists(),
                }
                (RUNTIME / "last-session.json").write_text(json.dumps(state, indent=2), encoding="utf-8")
                print(f"Owned Blender PID {process.pid} stopped; no background socket is intentionally left running.", flush=True)
    except Exception:
        if log_file.exists():
            print("\n".join(log_file.read_text(encoding="utf-8", errors="replace").splitlines()[-35:]), file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
