from __future__ import annotations

import hashlib
import json
import os
import platform
import plistlib
import re
import shutil
import stat
import struct
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path
from typing import Any

from .archive import deterministic_zip, extract_entry, extract_zip, obtain, tree_index, verify_zip
from .audit import process_files, smoke_files
from .common import (
    ReleaseError, diagnostic_output, digest, inside, integer, json_equal, load_manifest, project_identity, read_json,
    relative_name, require, setting, strict_json, write_json,
)
from .process import WindowsAvailability, recorded_process, run_process
from .smoke import godot_output, validate_producers, validate_report
from .source import (
    CONSUMED_PATHS, committed_inputs, require_git_root, snapshot_digest, source_snapshot, verify_committed_inputs,
)

HERE = Path(__file__).resolve().parent
PLATFORMS = ("windows-x86_64", "linux-x86_64", "macos-universal")
STAGES = ("source-legacy", "source-gameplay", "packaged-legacy", "packaged-gameplay")
BUILD_PROVENANCE_FIELDS = ("templateEntry", "templateSha256", "engineWorkaround")


def preserve_inventory(repository: Path) -> dict[str, str]:
    result = {}
    for name in ("FutsalG1.exe", "FutsalG1-20260909.exe", "FutsalPreview-0.2.0.exe",
                 "FutsalPreview-0.3.0.exe", "FutsalPreview-0.4.0.exe"):
        path = repository / "build" / "windows" / name
        if path.exists():
            require(path.is_file() and not path.is_symlink(), f"Historico no regular: {path}")
            result[path.relative_to(repository).as_posix()] = digest(path)
    legacy_manifest = repository / "tools" / "godot" / "release.json"
    result[legacy_manifest.relative_to(repository).as_posix()] = digest(legacy_manifest)
    return result


def commit_identity(repository: Path, requested: str | None, allow_uncommitted: bool) -> str | None:
    repository = repository.resolve()
    if not allow_uncommitted:
        require_git_root(repository)
    result = run_process(["git", "rev-parse", "--verify", "HEAD"], repository, timeout=10)
    if result.ok:
        actual = result.stdout.decode("ascii").strip()
        require(re.fullmatch(r"[0-9a-f]{40}", actual) is not None, "Commit Git invalido.")
        require(requested in (None, actual), "El commit solicitado no es el checkout consumido.")
        if allow_uncommitted:
            print("CANDIDATO LOCAL: se registra el estado de fuente; no se acredita checkout publicable.", flush=True)
            return None
        status = run_process(
            ["git", "status", "--porcelain=v1", "--untracked-files=all", "--", *CONSUMED_PATHS],
            repository, timeout=10,
        )
        require(status.ok and status.stdout.strip() == b"",
                "Fuentes/tooling/licencia no coinciden con el commit; usar modo local explicito, no fingir un checkout limpio.")
        verify_committed_inputs(repository, actual, HERE)
        return actual
    require(allow_uncommitted and not requested and result.exit_code == 128,
            f"No hay commit verificable: {result.stderr.decode('utf-8', errors='replace')}")
    print("CANDIDATO LOCAL sin commit; no apto para publicacion automatica.", flush=True)
    return None


def _set_option(text: str, section: str, key: str, value: Any) -> str:
    header = "[" + section + "]"
    lines = text.splitlines()
    require(lines.count(header) == 1, f"Preset ausente/duplicado: {header}")
    start = lines.index(header) + 1
    end = next((index for index in range(start, len(lines)) if lines[index].startswith("[")), len(lines))
    matches = [index for index in range(start, end) if lines[index].startswith(key + "=")]
    require(len(matches) <= 1, f"Opcion de preset duplicada: {key}")
    line = key + "=" + json.dumps(value, ensure_ascii=False)
    if matches:
        lines[matches[0]] = line
    else:
        lines.insert(end, line)
    return "\n".join(lines) + "\n"


def build_variant(target: dict[str, Any], identity: dict[str, Any]) -> dict[str, Any]:
    mode = target["buildType"]
    require(mode in ("release", "debug"), "Tipo de build desconocido.")
    result = {"buildType": mode, **dict.fromkeys(BUILD_PROVENANCE_FIELDS)}
    if mode == "debug":
        require(target["host"] == "linux" and identity["projectVersion"].endswith("-preview"),
                "La plantilla debug solo esta autorizada para una version preview Linux.")
        result.update({key: target[key] for key in BUILD_PROVENANCE_FIELDS})
    return result


def _validate_build_variant(metadata: dict[str, Any], variant: dict[str, Any], label: str) -> None:
    require(type(metadata) is dict, f"{label}: se exige un objeto de metadata.")
    for key, expected in variant.items():
        require(json_equal(metadata.get(key), expected),
                f"{label}: {key} no corresponde a la variante autorizada.")


def export_arguments(editor: Path, project: Path, payload: Path, target: dict[str, Any]) -> list[str]:
    mode = target["buildType"]
    require(mode in ("release", "debug"), "Tipo de exportacion desconocido.")
    return [str(editor), "--headless", "--path", str(project), "--export-" + mode,
            target["preset"], str(payload / target["exportName"])]


def configure_private_preset(project: Path, target: dict[str, Any], template: Path,
                             identity: dict[str, Any]) -> None:
    path = project / "export_presets.cfg"
    text = path.read_text(encoding="utf-8")
    index = target["presetIndex"]
    require(setting(text, f"preset.{index}", "name") == target["preset"], "Nombre de preset incorrecto.")
    require(setting(text, f"preset.{index}.options", "binary_format/architecture") ==
            ("universal" if target["host"] == "darwin" else "x86_64"), "Arquitectura de preset incorrecta.")
    mode = build_variant(target, identity)["buildType"]
    text = _set_option(text, f"preset.{index}.options", "custom_template/" + mode, str(template))
    if target["host"] == "darwin":
        require(setting(text, f"preset.{index}.options", "codesign/codesign") == 1 and
                setting(text, f"preset.{index}.options", "notarization/notarization") == 0,
                "macOS exige ad-hoc local, sin notarizacion ni credenciales.")
        project_settings = (project / "project.godot").read_text(encoding="utf-8")
        require(setting(project_settings, "rendering", "textures/vram_compression/import_etc2_astc") is True,
                "macOS Universal exige textures/vram_compression/import_etc2_astc=true antes de importar.")
        numeric_version = identity["projectVersion"].split("-")[0]
        for key in ("application/short_version", "application/version"):
            text = _set_option(text, f"preset.{index}.options", key, numeric_version)
    path.write_text(text, encoding="utf-8", newline="\n")


def isolated_environment(profile: Path) -> dict[str, str]:
    environment = os.environ.copy()
    folders = {
        "HOME": profile / "home", "USERPROFILE": profile / "home",
        "APPDATA": profile / "roaming", "LOCALAPPDATA": profile / "local",
        "XDG_DATA_HOME": profile / "data", "XDG_CONFIG_HOME": profile / "config",
        "XDG_CACHE_HOME": profile / "cache", "TMPDIR": profile / "tmp",
        "TMP": profile / "tmp", "TEMP": profile / "tmp",
    }
    for key, path in folders.items():
        path.mkdir(parents=True, exist_ok=True)
        environment[key] = str(path)
    environment["PYTHONIOENCODING"] = "utf-8"
    environment["NO_COLOR"] = "1"
    return environment


def extract_private_template(archive: Path, target: dict[str, Any], engine: dict[str, Any],
                             work: Path, environment: dict[str, str]) -> Path:
    directory = work / "templates"
    name = relative_name(target["templateEntry"]).name
    if target["host"] == "darwin":
        home = Path(environment["HOME"])
        require(home.is_absolute(), "macOS exige un HOME privado absoluto.")
        home = inside(work, home)
        require(name == "macos.zip", "macOS exige el template oficial macos.zip.")
        # Godot busca primero el ZIP estandar incluso con custom_template/release.
        directory = (home / "Library" / "Application Support" / "Godot" / "export_templates"
                     / (engine["version"] + ".stable"))
    template = extract_entry(archive, target["templateEntry"], directory / name)
    if target["buildType"] == "debug":
        require(digest(template) == target["templateSha256"], "La plantilla debug no coincide con el pin oficial.")
    return template


def native_executable(payload: Path, target: dict[str, Any]) -> Path:
    path = payload / target["exportName"]
    if target["host"] == "darwin":
        info = plistlib.loads((path / "Contents" / "Info.plist").read_bytes())
        name = info["CFBundleExecutable"]
        relative_name(name)
        require("/" not in name, "CFBundleExecutable debe ser un nombre simple.")
        path = path / "Contents" / "MacOS" / name
    require(path.is_file() and not path.is_symlink(), f"Ejecutable nativo no regular: {path}")
    return path


def binary_architectures(path: Path) -> list[str]:
    size = path.stat().st_size
    with path.open("rb") as handle:
        header = handle.read(64)
        if header.startswith(b"MZ"):
            require(len(header) == 64, "Cabecera PE truncada.")
            offset = struct.unpack_from("<I", header, 60)[0]
            require(64 <= offset <= size - 26, "Offset PE invalido.")
            handle.seek(offset)
            pe = handle.read(26)
            require(pe[:4] == b"PE\0\0" and struct.unpack_from("<H", pe, 4)[0] == 0x8664
                    and struct.unpack_from("<H", pe, 24)[0] == 0x20B, "No es Windows PE x86_64.")
            return ["x86_64"]
        if header.startswith(b"\x7fELF"):
            require(len(header) >= 20 and header[4:6] == b"\x02\x01" and
                    struct.unpack_from("<H", header, 18)[0] == 62, "No es ELF64 little-endian x86_64.")
            return ["x86_64"]
        fat = {b"\xca\xfe\xba\xbe": (">", False), b"\xca\xfe\xba\xbf": (">", True),
               b"\xbe\xba\xfe\xca": ("<", False), b"\xbf\xba\xfe\xca": ("<", True)}
        require(header[:4] in fat, "No es Mach-O Universal2.")
        endian, wide = fat[header[:4]]
        count = struct.unpack_from(endian + "I", header, 4)[0]
        require(count == 2, "Universal2 debe tener exactamente dos arquitecturas.")
        handle.seek(8)
        architectures = []
        slices = []
        for _ in range(count):
            entry = handle.read(32 if wide else 20)
            require(len(entry) == (32 if wide else 20), "Fat header truncado.")
            cpu = struct.unpack_from(endian + "I", entry)[0]
            offset, length = struct.unpack_from(endian + ("QQ" if wide else "II"), entry, 8)
            require(offset >= 8 + count * len(entry) and length > 0 and offset + length <= size,
                    "Slice Mach-O fuera del archivo.")
            require(cpu in (0x01000007, 0x0100000C), "Slice Mach-O no autorizada.")
            architectures.append("x86_64" if cpu == 0x01000007 else "arm64")
            slices.append((offset, length, cpu))
        require(len(set(architectures)) == 2, "Universal2 repite arquitectura.")
        require(slices[0][0] + slices[0][1] <= slices[1][0] or slices[1][0] + slices[1][1] <= slices[0][0],
                "Slices Mach-O solapadas.")
        for offset, _length, cpu in slices:
            handle.seek(offset)
            slice_header = handle.read(8)
            require(len(slice_header) == 8 and slice_header[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"),
                    "Slice sin cabecera Mach-O64.")
            slice_endian = "<" if slice_header[:4] == b"\xcf\xfa\xed\xfe" else ">"
            require(struct.unpack_from(slice_endian + "I", slice_header, 4)[0] == cpu,
                    "CPU de la slice no coincide con el directorio Universal2.")
        return sorted(architectures)


def payload_structure(payload: Path, target: dict[str, Any]) -> tuple[Path, dict[str, list[str]]]:
    executable = native_executable(payload, target)
    with executable.open("rb") as stream:
        magic = stream.read(4)
    expected_format = {
        "win32": magic.startswith(b"MZ"),
        "linux": magic == b"\x7fELF",
        "darwin": magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf", b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca"),
    }
    require(expected_format[target["host"]], "Formato de binario de otro sistema operativo.")
    architectures = binary_architectures(executable)
    require(architectures == sorted(target["architectures"]), "Arquitecturas del binario no coinciden.")
    if target["host"] != "win32":
        require(executable.stat().st_mode & 0o111 != 0, "El ejecutable perdio permisos de ejecucion.")
    libraries = {}
    if target["host"] == "linux":
        require((payload / "Futsal.pck").is_file(), "No se empaqueto el PCK Linux.")
    if target["host"] == "darwin":
        app = payload / target["exportName"]
        require(any(app.rglob("*.pck")), "El bundle macOS no contiene PCK.")
        macho_magic = {
            b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf", b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca",
            b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
        }
        for path in app.rglob("*"):
            if not path.is_file() or path.is_symlink() or path == executable:
                continue
            with path.open("rb") as stream:
                library_magic = stream.read(4)
            if library_magic in macho_magic:
                found = binary_architectures(path)
                require(found == ["arm64", "x86_64"], "Dependencia Mach-O no universal.")
                libraries[path.relative_to(payload).as_posix()] = found
    return executable, libraries


def validate_native_payload(payload: Path, target: dict[str, Any], proof: Path,
                            environment: dict[str, str], label: str) -> dict[str, Any]:
    executable, libraries = payload_structure(payload, target)
    architectures = binary_architectures(executable)
    if target["host"] == "darwin":
        app = payload / target["exportName"]
        verification = recorded_process(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)],
                                        payload, proof / (label + "-codesign-verify"), timeout=30, environment=environment)
        diagnostic_output(verification.stdout, verification.stderr, allow_tool_stderr=True)
        signature = recorded_process(["codesign", "--display", "--verbose=4", str(app)],
                                     payload, proof / (label + "-codesign-display"), timeout=30, environment=environment)
        text = "".join(diagnostic_output(signature.stdout, signature.stderr, allow_tool_stderr=True))
        require("Signature=adhoc" in text and "TeamIdentifier=not set" in text,
                "La firma no es ad-hoc sin identidad Apple.")
        lipo = recorded_process(["lipo", "-archs", str(executable)], payload, proof / (label + "-lipo"),
                                timeout=30, environment=environment)
        require(set(godot_output(lipo).split()) == {"x86_64", "arm64"}, "lipo no confirma Universal2.")
        return {"kind": "ad-hoc", "verified": True, "notarized": False, "developerId": False,
                "architectures": architectures, "libraries": libraries}
    return {"kind": "unsigned" if target["host"] == "win32" else "not-applicable",
            "verified": False, "notarized": False, "developerId": False, "architectures": architectures}


def inspect_packaged_payload(archive_path: Path, target: dict[str, Any], metadata: dict[str, Any],
                             manifest: dict[str, Any]) -> None:
    contents = metadata["contents"]
    with zipfile.ZipFile(archive_path) as archive, tempfile.TemporaryDirectory(prefix="futsal-audit-") as temporary:
        scratch = Path(temporary) / "binary"
        executable_name = target["exportName"]
        if target["host"] == "darwin":
            require(contents[executable_name + "/Contents/Info.plist"]["bytes"] <= 1024 * 1024, "Info.plist demasiado grande.")
            info = plistlib.loads(archive.read(executable_name + "/Contents/Info.plist"))
            binary_name = info["CFBundleExecutable"]
            relative_name(binary_name)
            require("/" not in binary_name, "CFBundleExecutable ambiguo.")
            executable_name += "/Contents/MacOS/" + binary_name
            require(any(name.startswith(target["exportName"] + "/") and name.endswith(".pck") for name in contents),
                    "Falta PCK en bundle.")
        if target["host"] == "linux":
            require("Futsal.pck" in contents and contents["Futsal.pck"]["kind"] == "file", "Falta PCK Linux.")
        require(executable_name in contents and contents[executable_name]["kind"] == "file",
                "Falta el ejecutable regular en el ZIP.")
        if target["host"] != "win32":
            require(contents[executable_name]["mode"] == 0o755, "El ZIP perdio exec bit.")
        with archive.open(executable_name) as source, scratch.open("wb") as output:
            shutil.copyfileobj(source, output, 1024 * 1024)
        with scratch.open("rb") as source:
            magic = source.read(4)
        require((target["host"] == "win32" and magic.startswith(b"MZ")) or
                (target["host"] == "linux" and magic == b"\x7fELF") or
                (target["host"] == "darwin" and magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",
                                                         b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca")),
                "El paquete contiene un binario de otro OS.")
        require(binary_architectures(scratch) == sorted(target["architectures"]), "Arquitecturas empaquetadas incorrectas.")
        executable_hash = digest(scratch)
        require(all(stage["executableSha256"] == executable_hash for stage in metadata["validation"]["stages"]
                    if stage["stage"].startswith("packaged-")), "El binario del ZIP no es el ejecutado.")
        if target["host"] == "darwin":
            libraries = {}
            for name, entry in contents.items():
                if name == executable_name or entry["kind"] != "file" or not name.startswith(target["exportName"] + "/"):
                    continue
                with archive.open(name) as source:
                    magic = source.read(4)
                if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf", b"\xbe\xba\xfe\xca",
                             b"\xbf\xba\xfe\xca", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
                    with archive.open(name) as source, scratch.open("wb") as output:
                        shutil.copyfileobj(source, output, 1024 * 1024)
                    libraries[name] = binary_architectures(scratch)
                    require(libraries[name] == ["arm64", "x86_64"], "Dependencia empaquetada no universal.")
            require(libraries == metadata["signing"]["libraries"], "Dependencias Universal2 distintas.")
        require(contents["BUILD.json"]["bytes"] <= 1024 * 1024, "BUILD.json demasiado grande.")
        embedded = strict_json(archive.read("BUILD.json"))
        required = {
            "schemaVersion", "projectVersion", "tag", "projectName", "inputSchemaVersion", "mainScene",
            "platform", "buildType", "commit", "sourceSnapshotSha256", "engine", "engineEdition",
            "signing", "projectLicense", "licensePolicy", "validationEvidenceFile", "limitations",
        }
        _validate_build_variant(embedded, build_variant(target, metadata), "BUILD.json")
        require(required <= set(embedded) <= required | set(BUILD_PROVENANCE_FIELDS) and
                all(json_equal(metadata[key], embedded[key]) for key in required),
                "BUILD.json y evidencia discrepan.")
        for item in manifest["licenses"]:
            require(contents[item["name"]]["bytes"] == item["bytes"] and
                    hashlib.sha512(archive.read(item["name"])).hexdigest() == item["sha512"],
                    "Licencia/avisos oficiales alterados o ausentes.")
        if metadata["licensePolicy"] == "project-file":
            license_info = metadata["projectLicense"]
            require(license_info["packaged"] == "GAME_LICENSE.txt" and
                    hashlib.sha256(archive.read("GAME_LICENSE.txt")).hexdigest() == license_info["sha256"],
                    "La licencia propia no corresponde a su metadata.")
        else:
            require("GAME_LICENSE.txt" not in contents, "Se atribuyo una licencia no declarada.")


def _smoke(executable: Path, project: Path | None, proof: Path, name: str,
           identity: dict[str, Any], manifest: dict[str, Any], contract: dict[str, Any],
           environment: dict[str, str]) -> dict[str, Any]:
    protocol = "gameplay" if name.endswith("gameplay") else "legacy"
    directory = proof / name
    directory.mkdir()
    report = directory / "report.json"
    require(not report.exists(), "Informe preexistente.")
    arguments = [str(executable), "--headless", "--audio-driver", "Dummy", "--fixed-fps", "60"]
    if project is not None:
        arguments += ["--path", str(project)]
    arguments += ["--", "--gameplay-smoke" if protocol == "gameplay" else "--smoke-test",
                  "--report-path=" + str(report)]
    result = recorded_process(arguments, project or executable.parent, directory / "process",
                              timeout=180, environment=environment)
    validation = validate_report(result, report, executable, protocol=protocol, editor=project is not None,
                                 identity=identity, engine=manifest["engine"], contract=contract)
    return {"stage": name, **validation, "process": result.metadata(),
            "executableSha256": digest(executable), "reportSha256": digest(report)}


def _notices(repository: Path, payload: Path, manifest: dict[str, Any], cache: Path,
             platform_id: str) -> dict[str, Any] | None:
    for item in manifest["licenses"]:
        shutil.copyfile(obtain(item, cache), payload / item["name"])
    licenses = [repository / name for name in ("LICENSE", "LICENSE.txt", "LICENSE.md")]
    found = [path for path in licenses if path.is_file()]
    require(len(found) <= 1, "Varias licencias raiz ambiguas; coordinacion debe decidir.")
    project_license = None
    if found:
        require(not found[0].is_symlink(), "Licencia del juego no regular.")
        shutil.copyfile(found[0], payload / "GAME_LICENSE.txt")
        project_license = {"source": found[0].name, "packaged": "GAME_LICENSE.txt", "sha256": digest(found[0])}
    message = (
        "Futsal - preview experimental de entrenamiento, no el MVP completo.\n\n"
        "Godot Engine usa MIT; GODOT_LICENSE.txt y GODOT_COPYRIGHT.txt contienen\n"
        "sus avisos y los de terceros. Esos permisos NO asignan licencia al juego.\n"
        + ("La licencia del proyecto esta en GAME_LICENSE.txt.\n" if found else
           "El proyecto no declara licencia propia. El tooling no asigna una ni concede derechos sobre el juego.\n")
        + "\nEl laboratorio no tiene audio. Teclado/mando: controles en pantalla y F1.\n"
        "La prueba automatica es headless; no acredita GPU, 60 FPS, mando fisico o arte.\n"
        "No iniciar normalmente con --fixed-fps, --smoke-test ni --gameplay-smoke.\n"
    )
    if platform_id == "windows-x86_64":
        message += "\nExtraer todo el ZIP y abrir Futsal.exe. Sin firma Authenticode.\n"
    elif platform_id == "linux-x86_64":
        message += "\nExtraer conservando permisos y mantener Futsal.pck junto a Futsal.x86_64.\nEjecutar ./Futsal.x86_64; requiere entorno grafico/GPU compatible para jugar.\n"
        if manifest["platforms"][platform_id]["buildType"] == "debug":
            message += (
                "\nEsta preview Linux usa la plantilla DEBUG oficial de Godot 4.7.2 como workaround\n"
                "de https://github.com/godotengine/godot/issues/87626. No es un template release\n"
                "optimizado ni acredita FPS. Conserva Popup nativo, UX y los smokes completos.\n"
            )
    else:
        message += (
            "\nExtraer con una herramienta que preserve permisos y enlaces del bundle Futsal.app.\n"
            "Universal2; firma ad-hoc, NO Developer ID ni notarizacion. Gatekeeper puede bloquearlo.\n"
            "Consultar la ayuda oficial de Apple para abrir una app de un desarrollador no identificado;\n"
            "hacerlo solo tras verificar procedencia y checksum. No desactivar Gatekeeper globalmente.\n"
        )
    (payload / "README_ES.txt").write_text(message, encoding="utf-8", newline="\n")
    return project_license


def build(repository: Path, platform_id: str, output: Path, cache: Path, *,
          tag: str | None, commit: str | None, allow_uncommitted: bool) -> Path:
    require(sys.version_info >= (3, 11), "Se requiere Python 3.11 o posterior.")
    repository = repository.resolve()
    output = inside(repository / "build", output)
    require(output.is_relative_to(repository / "build" / "release"), "Solo se escribe bajo build/release.")
    require(platform_id in PLATFORMS, "Plataforma no autorizada.")
    manifest = load_manifest(HERE / "manifest.json")
    target = manifest["platforms"][platform_id]
    require(sys.platform == target["host"], "Se exige build y validacion nativos; no se simula otro OS.")
    require(platform.machine().lower() in (("amd64", "x86_64") if sys.platform != "darwin" else ("arm64", "x86_64")),
            "Arquitectura del runner no autorizada.")
    identity = project_identity(repository / "game", tag)
    variant = build_variant(target, identity)
    actual_commit = commit_identity(repository, commit, allow_uncommitted)
    contract = read_json(HERE / "smoke-contract.json")
    validate_producers(repository / "game", contract, identity)
    destination = output / "dist" / platform_id
    require(not destination.exists(), f"No se sobrescribe una release: {destination}")
    original = source_snapshot(repository / "game")
    if actual_commit is not None:
        expected_inputs = committed_inputs(repository, actual_commit)
        require(original == {name.removeprefix("game/"): value for name, value in expected_inputs.items()
                             if name.startswith("game/")}, "La fuente cambio despues de verificar el commit.")
    protected = preserve_inventory(repository)
    run_id = uuid.uuid4().hex
    proof = output / "proof" / platform_id / run_id
    proof.mkdir(parents=True)
    work_root = output / "work"
    work_root.mkdir(parents=True, exist_ok=True)
    write_json(proof / "source-snapshot.json", original)
    availability = WindowsAvailability()
    try:
        with tempfile.TemporaryDirectory(prefix=platform_id + "-", dir=work_root) as temporary:
            work = Path(temporary).resolve()
            with availability:
                editor_zip = obtain(target["editor"], cache)
                templates = obtain(manifest["engine"]["templates"], cache)
                editor_root = work / "editor"
                extract_zip(editor_zip, editor_root)
                editor = editor_root.joinpath(*relative_name(target["editorExecutable"]).parts)
                require(editor.is_file(), f"Editor oficial ausente: {editor}")
                if sys.platform != "win32":
                    require(editor.stat().st_mode & 0o111 != 0, "ZIP del editor perdio exec bit.")
                environment = isolated_environment(work / "profile")
                template = extract_private_template(templates, target, manifest["engine"], work, environment)
                project = work / "project"
                shutil.copytree(repository / "game", project, ignore=shutil.ignore_patterns(".godot"))
                require(source_snapshot(project) == original, "La copia de fuente no coincide con el checkout.")
                configure_private_preset(project, target, template, identity)
                version = recorded_process([str(editor), "--version"], work, proof / "engine-version",
                                           timeout=30, environment=environment)
                require(godot_output(version).strip() == manifest["engine"]["versionOutput"], "Motor distinto al fijado.")
                imported = recorded_process([str(editor), "--headless", "--path", str(project), "--editor", "--import"],
                                            project, proof / "import", timeout=240, environment=environment)
                godot_output(imported)
                validation = [
                    _smoke(editor, project, proof, name, identity, manifest, contract, environment)
                    for name in ("source-legacy", "source-gameplay")
                ]
                payload = work / "payload"
                payload.mkdir()
                exported = recorded_process(
                    export_arguments(editor, project, payload, target),
                    project, proof / ("export-" + variant["buildType"]), timeout=300, environment=environment,
                )
                godot_output(exported)
                signing = validate_native_payload(payload, target, proof, environment, "export")
                project_license = _notices(repository, payload, manifest, cache, platform_id)
                package_name = f"futsal-{identity['tag']}-{platform_id}"
                build_info = {
                    "schemaVersion": 1, **identity, "platform": platform_id, **variant,
                    "commit": actual_commit, "sourceSnapshotSha256": snapshot_digest(original),
                    "engine": manifest["engine"]["versionOutput"], "engineEdition": "standard",
                    "signing": signing, "projectLicense": project_license,
                    "licensePolicy": "project-file" if project_license is not None else "not-defined",
                    "validationEvidenceFile": package_name + ".build.json",
                    "limitations": ["Sin aceptacion humana, artistica ni de FPS.",
                                    "CI prueba headless en la arquitectura nativa del runner; no todos los CPUs de Universal2."],
                }
                if variant["buildType"] == "debug":
                    build_info["limitations"].append(
                        "Preview Linux con template debug oficial por Godot #87626; no afirma optimizacion ni FPS.")
                write_json(payload / "BUILD.json", build_info)
                ready = work / "ready"
                ready.mkdir()
                archive = ready / (package_name + ".zip")
                contents = deterministic_zip(payload, archive)
                installation = work / "test-install"
                extract_zip(archive, installation)
                require(tree_index(installation) == contents, "Extraccion del paquete altero su contenido/permisos.")
                installed_signing = validate_native_payload(installation, target, proof, environment, "packaged")
                require(installed_signing == signing, "La firma/cabecera cambio al empaquetar.")
                executable = native_executable(installation, target)
                validation.extend(
                    _smoke(executable, None, proof, name, identity, manifest, contract, environment)
                    for name in ("packaged-legacy", "packaged-gameplay")
                )
                require(tree_index(installation) == contents, "El recorrido modifico el paquete instalado.")
            require(source_snapshot(repository / "game") == original, "La fuente original cambio durante el build.")
            require(preserve_inventory(repository) == protected, "Se modifico un debug/historico o release.json previo.")
            if actual_commit is not None:
                require(commit_identity(repository, actual_commit, False) == actual_commit,
                        "El checkout cambio antes de entregar el candidato.")
            require(not availability.metadata["applicable"] or availability.metadata["released"],
                    "No se libero la solicitud de disponibilidad.")
            checksum = digest(archive)
            (ready / (package_name + ".sha256")).write_text(
                checksum + "  " + archive.name + "\n", encoding="ascii", newline="\n")
            shutil.copytree(proof, ready / "proof" / platform_id)
            proof_files = tree_index(ready / "proof")
            metadata = {
                **build_info, "archive": archive.name, "archiveSha256": checksum,
                "archiveBytes": archive.stat().st_size, "contents": contents,
                "validation": {"complete": True, "stages": validation, "headlessOnly": True,
                               "renderedValidated": False, "artApproved": False, "humanFeelAccepted": False},
                "host": {"system": sys.platform, "machine": platform.machine(), "python": platform.python_version()},
                "sourceCommitVerified": actual_commit is not None,
                "publishableCandidate": actual_commit is not None,
                "publicationRequiresReview": True,
                "powerAvailability": availability.metadata,
                "preservedLocalArtifacts": protected, "evidenceFiles": proof_files,
                "templateArchiveSha512": manifest["engine"]["templates"]["sha512"],
                "editorArchiveSha512": target["editor"]["sha512"],
            }
            write_json(ready / (package_name + ".build.json"), metadata)
            destination.parent.mkdir(parents=True, exist_ok=True)
            require(not destination.exists(), "Otro build publico el mismo destino; no se sobrescribe.")
            ready.rename(destination)
        print(f"RELEASE CANDIDATA {destination}", flush=True)
        return destination
    except (ReleaseError, OSError, ValueError, KeyError) as exc:
        write_json(proof / "failure.json", {"ok": False, "error": str(exc), "platform": platform_id,
                                          "powerAvailability": availability.metadata})
        raise


def audit_candidate(repository: Path, archive: Path, *, commit: str | None = None,
                    tag: str | None = None) -> dict[str, Any]:
    metadata = read_json(archive.with_name(archive.stem + ".build.json"))
    required_commit = commit if commit is not None else metadata["commit"]
    expected = None
    if required_commit is not None:
        commit_identity(repository, required_commit, False)
        expected = _committed_game_snapshot(repository, required_commit)
    return _audit_candidate(repository, archive, commit=commit, tag=tag, expected_source=expected)


def _committed_game_snapshot(repository: Path, commit: str) -> dict[str, str]:
    return {name.removeprefix("game/"): value for name, value in committed_inputs(repository, commit).items()
            if name.startswith("game/")}


def _audit_candidate(repository: Path, archive: Path, *, commit: str | None,
                     tag: str | None, expected_source: dict[str, str] | None) -> dict[str, Any]:
    identity = project_identity(repository / "game", tag)
    manifest = load_manifest(HERE / "manifest.json")
    contract = read_json(HERE / "smoke-contract.json")
    metadata_path = archive.with_name(archive.stem + ".build.json")
    metadata = read_json(metadata_path)
    require(type(metadata["schemaVersion"]) is int and metadata["schemaVersion"] == 1, "Schema de candidato invalido.")
    integer(metadata["archiveBytes"], "archiveBytes", 1)
    platform_id = metadata["platform"]
    require(platform_id in PLATFORMS, "Plataforma de candidato desconocida.")
    target = manifest["platforms"][platform_id]
    variant = build_variant(target, identity)
    _validate_build_variant(metadata, variant, "Metadata de candidato")
    require(archive.name == f"futsal-{identity['tag']}-{platform_id}.zip", "Nombre de paquete incorrecto.")
    checksum = digest(archive)
    require(archive.with_suffix(".sha256").read_text(encoding="ascii") == checksum + "  " + archive.name + "\n",
            "Checksum adjunto incorrecto.")
    require(metadata["tag"] == identity["tag"] and metadata["projectVersion"] == identity["projectVersion"]
            and metadata["engine"] == manifest["engine"]["versionOutput"]
            and metadata["engineEdition"] == "standard", "Version/motor/clase de candidato incorrectos.")
    require(metadata["archive"] == archive.name and metadata["archiveSha256"] == checksum and
            metadata["archiveBytes"] == archive.stat().st_size and json_equal(verify_zip(archive), metadata["contents"]),
            "El paquete no coincide con la metadata validada.")
    require(metadata["templateArchiveSha512"] == manifest["engine"]["templates"]["sha512"] and
            metadata["editorArchiveSha512"] == target["editor"]["sha512"], "Pins de motor/templates distintos.")
    if commit is not None:
        require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None and metadata["commit"] == commit and
                metadata["sourceCommitVerified"] is True and metadata["publishableCandidate"] is True,
                "Commit/candidato no verificable para el conjunto CI.")
    else:
        require(metadata["commit"] is None or re.fullmatch(r"[0-9a-f]{40}", metadata["commit"]) is not None,
                "Commit de candidato invalido.")
    require(metadata["sourceCommitVerified"] is (metadata["commit"] is not None) and
            metadata["publishableCandidate"] is (metadata["commit"] is not None), "Estado de commit incoherente.")
    require(metadata["publicationRequiresReview"] is True, "El build no puede aprobar su publicacion.")
    policy = metadata["licensePolicy"]
    require(policy in ("project-file", "not-defined") and
            (metadata["projectLicense"] is None) == (policy == "not-defined"), "Politica de licencia incoherente.")
    validation = metadata["validation"]
    require(validation["complete"] is True and validation["headlessOnly"] is True and
            validation["renderedValidated"] is False and validation["artApproved"] is False and
            validation["humanFeelAccepted"] is False, "Aceptacion/validacion fabricada.")
    require([stage["stage"] for stage in validation["stages"]] == list(STAGES), "Falta etapa nativa obligatoria.")
    proof_root = archive.parent / "proof" / platform_id
    actual_proof = {platform_id + "/" + name: item for name, item in tree_index(proof_root).items()}
    require(bool(actual_proof) and json_equal(actual_proof, metadata["evidenceFiles"]), "Evidencia ausente/extra/alterada.")
    snapshot = read_json(proof_root / "source-snapshot.json")
    require(snapshot_digest(snapshot) == metadata["sourceSnapshotSha256"], "Snapshot de fuente incorrecto.")
    if expected_source is not None:
        require(json_equal(snapshot, expected_source), "La fuente archivada no corresponde al commit del checkout.")
    _version_process, version_text, _ = process_files(proof_root / "engine-version")
    require(version_text.strip() == manifest["engine"]["versionOutput"], "Version nativa archivada incorrecta.")
    import_process, _, _ = process_files(proof_root / "import")
    require(all(flag in import_process["arguments"] for flag in ("--headless", "--editor", "--import")),
            "Falta importacion nativa de fuentes.")
    export_stage = "export-" + variant["buildType"]
    export_flag = "--" + export_stage
    export_process, _, _ = process_files(proof_root / export_stage)
    export_arguments = export_process["arguments"]
    other_flags = {"--export-debug", "--export-release"} - {export_flag}
    require(export_arguments.count(export_flag) == 1 and not other_flags.intersection(export_arguments) and
            export_arguments.index(export_flag) + 2 < len(export_arguments) and
            export_arguments[export_arguments.index(export_flag) + 1] == target["preset"],
            "La exportacion archivada no coincide con el modo y preset declarados.")
    for stage in validation["stages"]:
        require(stage["modes"] == [0, 1] and all(type(mode) is int for mode in stage["modes"]) and
                stage["headless"] is True and stage["renderedValidated"] is False and stage["savedPngs"] == 0,
                "Resumen de recorrido no nativo/headless/ambos modos.")
        smoke_files(proof_root / stage["stage"], stage, identity, manifest["engine"], contract)
    power = metadata["powerAvailability"]
    require(power["applicable"] is (target["host"] == "win32") and power["changesGlobalPowerPolicy"] is False,
            "Politica de disponibilidad incorrecta.")
    if power["applicable"]:
        require(power["acquired"] is True and power["released"] is True, "Solicitud Windows no liberada.")
    require(metadata["host"]["system"] == target["host"], "Prueba no ejecutada en el OS nativo.")
    signing = metadata["signing"]
    require(signing["notarized"] is False and signing["developerId"] is False and
            signing["architectures"] == sorted(target["architectures"]), "Firma/arquitecturas mal declaradas.")
    if target["host"] == "darwin":
        require(signing["kind"] == "ad-hoc" and signing["verified"] is True, "macOS carece de firma ad-hoc verificada.")
        for label in ("export", "packaged"):
            process_files(proof_root / (label + "-codesign-verify"), allow_tool_stderr=True)
            _, out, err = process_files(proof_root / (label + "-codesign-display"), allow_tool_stderr=True)
            require("Signature=adhoc" in out + err and "TeamIdentifier=not set" in out + err, "Firma Apple inventada.")
            _, out, _ = process_files(proof_root / (label + "-lipo"))
            require(set(out.split()) == {"x86_64", "arm64"}, "Falta lipo Universal2.")
    else:
        require(signing["kind"] == ("unsigned" if target["host"] == "win32" else "not-applicable") and
                signing["verified"] is False, "Firma no existente declarada.")
    inspect_packaged_payload(archive, target, metadata, manifest)
    return metadata


def verify_collection(repository: Path, directory: Path, commit: str, tag: str | None) -> dict[str, Any]:
    identity = project_identity(repository / "game", tag)
    require(re.fullmatch(r"[0-9a-f]{40}", commit) is not None, "Se exige commit real para revisar entregas.")
    archives = {path.name: path for path in directory.rglob("*.zip")}
    expected = {f"futsal-{identity['tag']}-{platform_id}.zip" for platform_id in PLATFORMS}
    require(len(list(directory.rglob("*.zip"))) == 3 and set(archives) == expected,
            "Se requieren exactamente los tres ZIP de release, sin extras/duplicados.")
    commit_identity(repository, commit, False)
    expected_source = _committed_game_snapshot(repository, commit)
    entries = []
    source_hashes = set()
    for platform_id in PLATFORMS:
        stem = f"futsal-{identity['tag']}-{platform_id}"
        archive = archives[stem + ".zip"]
        metadata = _audit_candidate(repository, archive, commit=commit, tag=tag, expected_source=expected_source)
        checksum = metadata["archiveSha256"]
        source_hashes.add(metadata["sourceSnapshotSha256"])
        entries.append({"platform": platform_id, "archive": archive.name, "sha256": checksum,
                        "bytes": archive.stat().st_size, "buildType": metadata["buildType"],
                        "templateEntry": metadata.get("templateEntry"),
                        "templateSha256": metadata.get("templateSha256"),
                        "engineWorkaround": metadata.get("engineWorkaround")})
    require(len(source_hashes) == 1, "Las tres plataformas no consumieron la misma fuente.")
    return {"schemaVersion": 1, "ok": True, **identity, "commit": commit,
            "sourceSnapshotSha256": next(iter(source_hashes)), "archives": entries,
            "published": False, "technicalReviewPending": True,
            "scope": "Comprobacion de artefactos/protocolos archivados; no ejecucion nueva ni aceptacion humana/arte/FPS."}
