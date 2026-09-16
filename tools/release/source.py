from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any

from .common import digest, relative_name, require, same_path, text_digest
from .process import run_process

GAME_TEXT_SUFFIXES = (".gd", ".tscn", ".tres", ".cfg", ".godot", ".uid", ".gdshader", ".import", ".json")
TOOL_TEXT_SUFFIXES = (*GAME_TEXT_SUFFIXES, ".py", ".yml", ".yaml", ".md", ".txt")
CONSUMED_PATHS = ("game", "tools/release", ".github/workflows/release.yml",
                  "tools/godot/release.json", "LICENSE", "LICENSE.txt", "LICENSE.md", "THIRD_PARTY_NOTICES.md",
                  ".gitattributes")
LFS_PREFIX = b"version https://git-lfs.github.com/spec/v1"
PROJECT_NOTICES_NAME = "THIRD_PARTY_NOTICES.md"
PROJECT_NOTICES_MAX_BYTES = 1024 * 1024


def source_snapshot(project: Path) -> dict[str, str]:
    result = {}
    for directory, directories, files in os.walk(project, followlinks=False):
        directories[:] = sorted(name for name in directories if name != ".godot")
        for name in [*directories, *files]:
            path = Path(directory) / name
            require(not path.is_symlink(), f"Fuente con symlink no prevista: {path}")
        for name in sorted(files):
            path = Path(directory) / name
            relative = path.relative_to(project).as_posix()
            relative_name(relative)
            with path.open("rb") as handle:
                require(not handle.read(128).startswith(LFS_PREFIX), f"Asset LFS sin descargar: {relative}")
            result[relative] = text_digest(path) if path.suffix in GAME_TEXT_SUFFIXES else digest(path)
    return dict(sorted(result.items()))


def snapshot_digest(snapshot: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def requires_project_notices(identity: dict[str, Any]) -> bool:
    version = identity["projectVersion"]
    require(type(version) is str and re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version) is not None,
            "Version invalida para el contrato de avisos.")
    return tuple(int(part) for part in version.split("-")[0].split(".")) >= (0, 5, 0)


def source_documents(repository: Path, identity: dict[str, Any]) -> tuple[dict[str, str], dict[str, Any] | None]:
    if not requires_project_notices(identity):
        return {}, None
    path = repository / PROJECT_NOTICES_NAME
    require(path.is_file() and not path.is_symlink(), "Falta THIRD_PARTY_NOTICES.md regular en la fuente.")
    require(0 < path.stat().st_size <= PROJECT_NOTICES_MAX_BYTES, "Tamano de THIRD_PARTY_NOTICES.md invalido.")
    data = path.read_bytes()
    normalized = data.decode("utf-8").replace("\r\n", "\n")
    require(bool(normalized.strip()) and len(data) <= PROJECT_NOTICES_MAX_BYTES, "Avisos del proyecto vacios o excesivos.")
    checksum = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    return {PROJECT_NOTICES_NAME: checksum}, {
        "source": PROJECT_NOTICES_NAME, "packaged": PROJECT_NOTICES_NAME,
        "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "normalizedSha256": checksum,
    }


def require_git_root(repository: Path) -> None:
    result = run_process(["git", "rev-parse", "--show-toplevel"], repository, timeout=10)
    require(result.ok, f"No hay raiz Git verificable: {result.stderr.decode('utf-8', errors='replace')}")
    effective = Path(result.stdout.decode("utf-8").strip()).resolve()
    require(same_path(effective, repository.resolve()),
            "La raiz Git efectiva no es la raiz fuente; un snapshot anidado no acredita el commit del padre.")


def _ignored(name: str) -> bool:
    parts = relative_name(name).parts
    if parts[0] == "game":
        return ".godot" in parts[1:-1]
    if parts[:2] == ("tools", "release"):
        return ("__pycache__" in parts[2:-1] or parts[2:3] in ((".cache",), ("runtime",))
                or Path(name).suffix in (".pyc", ".pyo"))
    return False


def _text(name: str) -> bool:
    return (Path(name).suffix in GAME_TEXT_SUFFIXES if name.startswith("game/") else
            Path(name).suffix in TOOL_TEXT_SUFFIXES or name in ("LICENSE", ".gitattributes"))


def _content_digest(data: bytes, name: str) -> str:
    if _text(name):
        data = data.decode("utf-8").replace("\r\n", "\n").encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    require(not root.is_symlink(), f"Entrada fuente con symlink: {root}")
    if root.is_file():
        return [root]
    result = []
    for directory, directories, files in os.walk(root, followlinks=False):
        directories[:] = sorted(name for name in directories if name != "__pycache__"
                                and not (Path(directory) == root and name in (".cache", "runtime")))
        for name in [*directories, *files]:
            path = Path(directory) / name
            require(not path.is_symlink(), f"Entrada fuente con symlink: {path}")
        result.extend(Path(directory) / name for name in sorted(files))
    return result


def working_inputs(repository: Path) -> dict[str, str]:
    result = {"game/" + name: value for name, value in source_snapshot(repository / "game").items()}
    for relative in CONSUMED_PATHS[1:]:
        for path in _files(repository / relative):
            name = path.relative_to(repository).as_posix()
            relative_name(name)
            if not _ignored(name):
                data = path.read_bytes()
                require(not data.startswith(LFS_PREFIX), f"Entrada LFS sin descargar: {name}")
                result[name] = _content_digest(data, name)
    return dict(sorted(result.items()))


def _committed_blobs(repository: Path, commit: str) -> dict[str, bytes]:
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "Commit de fuente invalido.")
    tree = run_process(["git", "ls-tree", "-rz", "--full-tree", commit, "--", *CONSUMED_PATHS],
                       repository, timeout=10)
    require(tree.ok, f"No se pudo leer el arbol Git: {tree.error}")
    entries = {}
    for record in tree.stdout.split(b"\0"):
        if not record:
            continue
        header, name_bytes = record.split(b"\t", 1)
        mode, kind, object_id = header.split(b" ")
        name = name_bytes.decode("utf-8")
        relative_name(name)
        if _ignored(name):
            continue
        require(mode in (b"100644", b"100755") and kind == b"blob",
                f"El commit contiene symlink/submodulo no admitido en fuente: {name}")
        require(name not in entries, "Ruta Git duplicada.")
        require(re.fullmatch(rb"[0-9a-f]{40}", object_id) is not None, "Blob Git invalido.")
        entries[name] = object_id
    require("game/project.godot" in entries, "El commit no contiene la fuente de juego.")
    identifiers = list(dict.fromkeys(entries.values()))
    with tempfile.TemporaryDirectory(prefix="futsal-git-") as temporary:
        request = Path(temporary) / "objects.txt"
        request.write_bytes(b"\n".join(identifiers) + b"\n")
        response = run_process(["git", "cat-file", "--batch"], repository, timeout=10, input_file=request)
    require(response.ok, f"No se pudieron leer los blobs Git: {response.error}")
    blobs = {}
    offset = 0
    for expected in identifiers:
        end = response.stdout.find(b"\n", offset)
        require(end >= offset, "Respuesta Git sin cabecera completa.")
        header = response.stdout[offset:end].split(b" ")
        require(len(header) == 3 and header[0] == expected and header[1] == b"blob" and header[2].isdigit(),
                "Respuesta Git no corresponde al blob solicitado.")
        size = int(header[2])
        start, stop = end + 1, end + 1 + size
        require(stop < len(response.stdout) and response.stdout[stop:stop + 1] == b"\n", "Blob Git truncado.")
        data = response.stdout[start:stop]
        require(hashlib.sha1(b"blob " + str(size).encode("ascii") + b"\0" + data).hexdigest().encode("ascii") == expected,
                "Los bytes no corresponden al objeto Git solicitado.")
        blobs[expected] = data
        offset = stop + 1
    require(offset == len(response.stdout), "Respuesta Git con datos extra.")
    return {name: blobs[object_id] for name, object_id in entries.items()}


def committed_inputs(repository: Path, commit: str) -> dict[str, str]:
    result = {}
    for name, data in _committed_blobs(repository, commit).items():
        if data.startswith(LFS_PREFIX):
            pointer = re.fullmatch(
                rb"version https://git-lfs.github.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n",
                data.replace(b"\r\n", b"\n"),
            )
            require(pointer is not None, f"Pointer LFS no admitido: {name}")
            require((repository / name).stat().st_size == int(pointer[2]), f"Tamano LFS no corresponde al commit: {name}")
            result[name] = pointer[1].decode("ascii")
        else:
            result[name] = _content_digest(data, name)
    return dict(sorted(result.items()))


def verify_committed_inputs(repository: Path, commit: str, tooling: Path) -> dict[str, str]:
    actual = working_inputs(repository)
    expected = committed_inputs(repository, commit)
    require(actual == expected,
            "Los bytes de fuente/tooling/licencia no corresponden a HEAD; status limpio no acredita dirt ignorada/oculta.")
    executing = {}
    for path in _files(tooling):
        name = "tools/release/" + path.relative_to(tooling).as_posix()
        if not _ignored(name):
            executing[name] = _content_digest(path.read_bytes(), name)
    committed_tooling = {name: value for name, value in expected.items() if name.startswith("tools/release/")}
    require(bool(committed_tooling) and executing == committed_tooling,
            "El tooling ejecutado no corresponde al commit de la fuente consumida.")
    return {name.removeprefix("game/"): value for name, value in expected.items() if name.startswith("game/")}
