from __future__ import annotations

import hashlib
import os
import posixpath
import shutil
import stat
import time
import urllib.request
import uuid
import zipfile
from pathlib import Path
from typing import Any

from .common import digest, relative_name, require


def obtain(item: dict[str, Any], cache: Path) -> Path:
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / item["name"]
    if target.exists():
        require(target.is_file() and not target.is_symlink(), f"Cache no regular: {target}")
        require(target.stat().st_size == item["bytes"] and digest(target, "sha512") == item["sha512"],
                f"Cache corrupta; se rehusa reemplazarla: {target}")
        print(f"CACHE verificada {item['name']}", flush=True)
        return target
    temporary = cache / (item["name"] + "." + uuid.uuid4().hex + ".part")
    started = time.monotonic()
    count = 0
    checksum = hashlib.sha512()
    try:
        request = urllib.request.Request(item["url"], headers={"User-Agent": "futsal-release/1"})
        with urllib.request.urlopen(request, timeout=30) as response, temporary.open("xb") as output:
            require(response.geturl().startswith("https://"), "Redireccion no HTTPS.")
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                require(count <= item["bytes"], f"Descarga excede tamano fijado: {item['name']}")
                require(time.monotonic() - started < 600, "Deadline de descarga (600s) vencido.")
                checksum.update(chunk)
                output.write(chunk)
        require(count == item["bytes"] and checksum.hexdigest() == item["sha512"],
                f"SHA512/tamano descargado incorrecto: {item['name']}")
        require(not target.exists(), f"Cache modificada durante la descarga: {target}")
        temporary.rename(target)
    finally:
        if temporary.exists():
            temporary.unlink()
    return target


def _link_target(name: str, target: str) -> str:
    require(bool(target) and "\\" not in target and ":" not in target and "\0" not in target,
            f"Symlink invalido: {name} -> {target!r}")
    require(not target.startswith("/"), f"Symlink absoluto: {name}")
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
    require(resolved != ".." and not resolved.startswith("../"), f"Symlink escapa del ZIP: {name}")
    return resolved


def _validate_links(entries: dict[str, zipfile.ZipInfo], links: dict[str, str]) -> None:
    for name in links:
        pending = name.split("/")
        resolved: list[str] = []
        followed = 0
        while pending:
            part = pending.pop(0)
            if part in ("", "."):
                continue
            if part == "..":
                require(bool(resolved), f"Cadena de symlinks escapa del ZIP: {name}")
                resolved.pop()
                continue
            resolved.append(part)
            current = "/".join(resolved)
            if current in links:
                followed += 1
                require(followed <= 40, f"Ciclo de symlinks: {name}")
                resolved.pop()
                pending = links[current].split("/") + pending
        target = "/".join(resolved)
        require(target in entries or any(item.startswith(target + "/") for item in entries),
                f"Cadena de symlink colgante: {name}")


def zip_entries(archive: zipfile.ZipFile, maximum_bytes: int = 4 * 1024**3) -> dict[str, zipfile.ZipInfo]:
    entries: dict[str, zipfile.ZipInfo] = {}
    folded: set[str] = set()
    total = 0
    for info in archive.infolist():
        name = info.filename.rstrip("/")
        relative_name(name)
        require(name not in entries and name.casefold() not in folded, f"Entrada ZIP duplicada/ambigua: {name}")
        require(not info.flag_bits & 1, "No se admite ZIP cifrado.")
        mode = info.external_attr >> 16
        kind = stat.S_IFMT(mode)
        require(kind in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), f"Tipo ZIP no soportado: {name}")
        require(not mode & 0o7000, f"ZIP con bits de privilegios: {name}")
        total += info.file_size
        require(total <= maximum_bytes and len(entries) < 100000, "ZIP supera limites de extraccion.")
        entries[name] = info
        folded.add(name.casefold())
    for name in entries:
        parts = relative_name(name).parts
        for length in range(1, len(parts)):
            parent = entries.get("/".join(parts[:length]))
            if parent is not None:
                require(parent.is_dir(), f"Entrada bajo symlink/archivo: {name}")
    return entries


def extract_zip(path: Path, destination: Path) -> None:
    require(not destination.exists(), f"Destino de extraccion ya existe: {destination}")
    with zipfile.ZipFile(path) as archive:
        entries = zip_entries(archive)
        links: dict[str, str] = {}
        for name, info in entries.items():
            if stat.S_ISLNK(info.external_attr >> 16):
                require(info.file_size <= 4096, "Symlink ZIP demasiado grande.")
                target = archive.read(info).decode("utf-8")
                resolved = _link_target(name, target)
                require(resolved in entries or any(key.startswith(resolved + "/") for key in entries),
                        f"Symlink colgante: {name}")
                links[name] = target
        _validate_links(entries, links)
        destination.mkdir(parents=True)
        for name, info in entries.items():
            target = destination.joinpath(*relative_name(name).parts)
            if name in links:
                continue
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
                mode = info.external_attr >> 16
                target.chmod(0o755 if mode & 0o111 else 0o644)
        for name, link in links.items():
            target = destination.joinpath(*relative_name(name).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(link, target)


def extract_entry(archive_path: Path, entry: str, destination: Path) -> Path:
    relative_name(entry)
    require(not destination.exists(), f"Template de destino ya existe: {destination}")
    with zipfile.ZipFile(archive_path) as archive:
        matches = [info for info in archive.infolist() if info.filename == entry]
        require(len(matches) == 1, f"Template ausente/duplicado: {entry}")
        info = matches[0]
        require(not info.is_dir() and not stat.S_ISLNK(info.external_attr >> 16), "Template no regular.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info) as source, destination.open("xb") as output:
            shutil.copyfileobj(source, output, 1024 * 1024)
    return destination


def tree_index(root: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    folded: set[str] = set()
    for directory, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        for name in [*directories, *files]:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            relative_name(relative)
            require(relative.casefold() not in folded, f"Ruta de paquete ambigua: {relative}")
            folded.add(relative.casefold())
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                target = os.readlink(path)
                resolved = _link_target(relative, target)
                require(root.joinpath(*relative_name(resolved).parts).exists(), f"Symlink colgante: {relative}")
                require(path.resolve(strict=True).is_relative_to(root.resolve()), f"Symlink escapa: {relative}")
                data = target.encode("utf-8")
                result[relative] = {"kind": "symlink", "mode": 0o777, "bytes": len(data),
                                    "sha256": hashlib.sha256(data).hexdigest(), "target": target}
            elif stat.S_ISREG(mode):
                result[relative] = {"kind": "file", "mode": 0o755 if mode & 0o111 else 0o644,
                                    "bytes": path.stat().st_size, "sha256": digest(path)}
            else:
                require(stat.S_ISDIR(mode), f"Tipo de archivo no soportado: {path}")
    return dict(sorted(result.items()))


def deterministic_zip(root: Path, output: Path) -> dict[str, dict[str, Any]]:
    require(not output.exists(), f"No se sobrescribe un paquete: {output}")
    index = tree_index(root)
    require(bool(index), "Paquete vacio.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, item in index.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            kind = stat.S_IFLNK if item["kind"] == "symlink" else stat.S_IFREG
            info.external_attr = (kind | item["mode"]) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            if item["kind"] == "symlink":
                archive.writestr(info, item["target"].encode("utf-8"))
            else:
                with root.joinpath(*relative_name(name).parts).open("rb") as source, archive.open(info, "w") as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
    require(tree_index(root) == index, "El payload cambio durante el empaquetado.")
    require(verify_zip(output) == index, "El ZIP no conserva bytes/permisos/symlinks del payload.")
    return index


def verify_zip(path: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    links = {}
    with zipfile.ZipFile(path) as archive:
        entries = zip_entries(archive)
        for name, info in entries.items():
            require(not info.is_dir(), "Los ZIP finales no contienen entradas de directorio implicitas.")
            require(info.create_system == 3 and info.date_time == (1980, 1, 1, 0, 0, 0),
                    f"Metadata ZIP no reproducible: {name}")
            mode = info.external_attr >> 16
            symlink = stat.S_ISLNK(mode)
            require(stat.S_IFMT(mode) in (stat.S_IFREG, stat.S_IFLNK), f"Tipo final ZIP invalido: {name}")
            with archive.open(info) as stream:
                checksum = hashlib.file_digest(stream, "sha256").hexdigest()
            item: dict[str, Any] = {"kind": "symlink" if symlink else "file", "mode": stat.S_IMODE(mode),
                                    "bytes": info.file_size, "sha256": checksum}
            require(item["mode"] in ((0o777,) if symlink else (0o644, 0o755)), f"Permisos invalidos: {name}")
            if symlink:
                target = archive.read(info).decode("utf-8")
                _link_target(name, target)
                item["target"] = target
                links[name] = target
            result[name] = item
        _validate_links(entries, links)
    return dict(sorted(result.items()))
