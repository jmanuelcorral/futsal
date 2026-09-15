from __future__ import annotations

import hashlib
import json
import math
import os
import re
from pathlib import Path, PurePosixPath
from typing import Any


class ReleaseError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReleaseError(message)


def strict_json(data: str | bytes) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            require(key not in result, f"Clave JSON duplicada: {key}")
            result[key] = value
        return result

    def constant(value: str) -> None:
        raise ReleaseError(f"Numero JSON no finito: {value}")

    def floating(value: str) -> float:
        parsed = float(value)
        require(math.isfinite(parsed), f"Numero JSON fuera de rango: {value}")
        return parsed

    text = data.decode("utf-8") if isinstance(data, bytes) else data
    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant, parse_float=floating)


def json_equal(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if type(left) is dict:
        return left.keys() == right.keys() and all(json_equal(value, right[key]) for key, value in left.items())
    if type(left) is list:
        return len(left) == len(right) and all(json_equal(a, b) for a, b in zip(left, right))
    return type(left) in (str, int, float, bool, type(None)) and left == right


def diagnostic_output(stdout_bytes: bytes, stderr_bytes: bytes, *,
                      allow_tool_stderr: bool = False) -> tuple[str, str]:
    stdout = stdout_bytes.decode("utf-8").replace("\r\n", "\n")
    stderr = stderr_bytes.decode("utf-8")
    pattern = r"(?im)^\s*(?:ERROR|WARNING|SCRIPT ERROR|USER ERROR|USER WARNING|Parse Error|FAIL)\b"
    require(re.search(pattern, stdout) is None and re.search(pattern, stderr) is None,
            "Diagnostico ERROR/WARNING/Parse Error/FAIL inesperado.")
    require(allow_tool_stderr or stderr == "", f"Diagnostico inesperado en stderr: {stderr[:1500]}")
    return stdout, stderr


def read_json(path: Path, limit: int = 32 * 1024 * 1024) -> Any:
    require(path.is_file() and not path.is_symlink(), f"Falta archivo regular: {path}")
    require(path.stat().st_size <= limit, f"JSON demasiado grande: {path}")
    return strict_json(path.read_bytes())


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def digest(path: Path, algorithm: str = "sha256") -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, algorithm).hexdigest()


def text_digest(path: Path) -> str:
    text = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def relative_name(value: str) -> PurePosixPath:
    require(isinstance(value, str) and bool(value), "Ruta relativa vacia.")
    require("\\" not in value and ":" not in value and "\0" not in value,
            f"Ruta no portable: {value!r}")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(part not in ("", ".", "..") for part in value.rstrip("/").split("/")),
            f"Ruta no contenida: {value!r}")
    require(all(not part.endswith((" ", ".")) for part in path.parts), f"Ruta ambigua: {value}")
    return path


def inside(root: Path, candidate: Path) -> Path:
    root = root.resolve()
    candidate = candidate.resolve()
    require(candidate != root and candidate.is_relative_to(root),
            f"Ruta fuera del directorio propietario {root}: {candidate}")
    return candidate


def same_path(left: str | Path, right: str | Path) -> bool:
    return os.path.normcase(os.path.abspath(left)) == os.path.normcase(os.path.abspath(right))


def integer(value: Any, label: str, minimum: int | None = None) -> int:
    require(type(value) is int, f"{label} debe ser entero, no boolean/string.")
    if minimum is not None:
        require(value >= minimum, f"{label} fuera de rango.")
    return value


def number(value: Any, label: str) -> float:
    require(type(value) in (int, float) and math.isfinite(value), f"{label} no es finito.")
    return float(value)


def boolean(value: Any, expected: bool, label: str) -> None:
    require(type(value) is bool and value is expected, f"{label} debe ser {expected}.")


def setting(text: str, section: str, key: str) -> Any:
    current = ""
    matches = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
        elif current == section and line.startswith(key + "="):
            matches.append(line[len(key) + 1:])
    require(len(matches) == 1, f"Se exige un unico [{section}] {key}.")
    return strict_json(matches[0])


def project_identity(project: Path, tag: str | None = None) -> dict[str, Any]:
    text = (project / "project.godot").read_text(encoding="utf-8")
    version = setting(text, "application", "config/version")
    require(isinstance(version, str) and re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version) is not None,
            "Version de proyecto invalida.")
    expected_tag = f"v{version}"
    require(tag in (None, expected_tag), f"Tag {tag!r} no coincide con {expected_tag}.")
    schema = integer(setting(text, "futsal", "preparation/input_schema_version"), "input schema", 1)
    return {
        "projectVersion": version,
        "tag": expected_tag,
        "projectName": setting(text, "application", "config/name"),
        "inputSchemaVersion": schema,
        "mainScene": setting(text, "application", "run/main_scene"),
    }


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = read_json(path)
    require(integer(manifest["schemaVersion"], "release.schemaVersion") == 1, "Schema de release desconocido.")
    engine = manifest["engine"]
    require(engine["version"] == "4.7.2" and engine["edition"] == "standard",
            "Esta entrega exige Godot 4.7.2 standard.")
    require(set(manifest["platforms"]) == {"windows-x86_64", "linux-x86_64", "macos-universal"},
            "Se requieren exactamente las tres plataformas autorizadas.")
    for platform_id, target in manifest["platforms"].items():
        mode = target["buildType"]
        require(mode in ("release", "debug"), "Tipo de template desconocido.")
        if mode == "debug":
            require(platform_id == "linux-x86_64" and
                    target["engineWorkaround"] == "https://github.com/godotengine/godot/issues/87626",
                    "Debug solo esta autorizado para la preview Linux por Godot #87626.")
            require(type(target["templateSha256"]) is str and
                    re.fullmatch(r"[0-9a-f]{64}", target["templateSha256"]) is not None,
                    "El workaround Linux exige el SHA256 de la plantilla debug oficial.")
        else:
            require("engineWorkaround" not in target, "Un template release no declara el workaround debug.")
        expected_entry = {
            "windows-x86_64": f"templates/windows_{mode}_x86_64.exe",
            "linux-x86_64": f"templates/linux_{mode}.x86_64",
            "macos-universal": "templates/macos.zip",
        }[platform_id]
        require(target["templateEntry"] == expected_entry, "El miembro del TPZ no corresponde al tipo de build.")
    downloads = [engine["templates"], *manifest["licenses"]]
    downloads.extend(value["editor"] for value in manifest["platforms"].values())
    for item in downloads:
        relative_name(item["name"])
        require("/" not in item["name"], "La cache usa nombres simples.")
        integer(item["bytes"], item["name"] + " bytes", 1)
        require(re.fullmatch(r"[0-9a-f]{128}", item["sha512"]) is not None, "Pin SHA512 invalido.")
        require(item["url"].startswith((
            "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/",
            "https://raw.githubusercontent.com/godotengine/godot/" + engine["sourceCommit"] + "/",
        )), "URL fuera del upstream fijado.")
    for item in manifest["actions"].values():
        require(re.fullmatch(r"[0-9a-f]{40}", item["commit"]) is not None, "Accion sin commit fijado.")
    return manifest
