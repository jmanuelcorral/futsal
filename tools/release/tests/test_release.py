from __future__ import annotations

import hashlib
import json
import os
import stat
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from tools.release.archive import deterministic_zip, extract_zip, obtain, tree_index, verify_zip, zip_entries
from tools.release.build import (
    HERE, PLATFORMS, binary_architectures, configure_private_preset, project_identity,
    source_snapshot, verify_collection,
)
from tools.release.common import (
    ReleaseError, boolean, digest, inside, integer, json_equal, load_manifest, read_json,
    relative_name, setting, strict_json, write_json,
)

REPOSITORY = HERE.parents[1]


class CommonTests(unittest.TestCase):
    def test_json_equality_preserves_types_recursively(self) -> None:
        self.assertTrue(json_equal({"a": [0, True, None, {"b": 1.0}]}, {"a": [0, True, None, {"b": 1.0}]}))
        self.assertTrue(json_equal({"a": 1, "b": 2}, {"b": 2, "a": 1}))
        for left, right in ((True, 1), (False, 0), (1, 1.0), ([1], [True]),
                            ({"nested": [{"mode": 0}]}, {"nested": [{"mode": False}]}),
                            ({"a": 1}, {"a": 1, "b": 2}), ([1, 2], [2, 1]), ((1,), [1])):
            with self.subTest(left=left, right=right):
                self.assertFalse(json_equal(left, right))
                self.assertFalse(json_equal(right, left))

    def test_strict_json_rejects_duplicates_and_nonfinite(self) -> None:
        for text in ('{"a":1,"a":2}', '{"x":{"a":1,"a":1}}', '{"n":NaN}',
                     '{"n":Infinity}', '{"n":-Infinity}', '{"n":1e999}', '{"n":-1e999}'):
            with self.subTest(text=text), self.assertRaises(ReleaseError):
                strict_json(text)

    def test_strict_json_rejects_invalid_utf8(self) -> None:
        with self.assertRaises(UnicodeDecodeError):
            strict_json(b'{"x":"\xff"}')

    def test_types_are_not_coerced(self) -> None:
        for value in (True, False, "1", 1.0, None):
            with self.subTest(value=value), self.assertRaises(ReleaseError):
                integer(value, "value")
        for value in (1, "true", None):
            with self.subTest(value=value), self.assertRaises(ReleaseError):
                boolean(value, True, "flag")

    def test_path_escape_and_ambiguous_names(self) -> None:
        for value in ("", "/abs", "../x", "a/../b", "a//b", "a/./b", "C:/x", "a\\b", "name.", "name "):
            with self.subTest(value=value), self.assertRaises(ReleaseError):
                relative_name(value)
        self.assertEqual(relative_name("Futsal.app/Contents/MacOS/Futsal").name, "Futsal")

    def test_owned_output_cannot_be_root_or_sibling(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            self.assertEqual(inside(root, root / "child"), root / "child")
            for path in (root, root.parent / "outside"):
                with self.assertRaises(ReleaseError):
                    inside(root, path)

    def test_owned_output_resolves_aliases_without_allowing_root_or_escape(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / "nested").mkdir()
            alias = root / "nested" / ".."
            self.assertEqual(inside(alias, alias / "child"), root / "child")
            self.assertEqual(inside(root, alias / "child"), root / "child")
            for candidate in (alias, alias / ".." / "outside"):
                with self.subTest(candidate=candidate), self.assertRaises(ReleaseError):
                    inside(root, candidate)

    def test_json_write_refuses_overwrite_and_size(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "proof.json"
            write_json(path, {"ok": True})
            self.assertEqual(read_json(path), {"ok": True})
            with self.assertRaises(FileExistsError):
                write_json(path, {})
            with self.assertRaises(ReleaseError):
                read_json(path, 1)

    def test_manifest_has_exact_platforms_and_official_pins(self) -> None:
        manifest = load_manifest(HERE / "manifest.json")
        self.assertEqual(set(manifest["platforms"]), set(PLATFORMS))
        old = read_json(REPOSITORY / "tools" / "godot" / "release.json")
        self.assertEqual(manifest["engine"]["templates"]["sha512"], old["templates"]["sha512"])
        self.assertEqual(manifest["platforms"]["windows-x86_64"]["editor"]["sha512"], old["editor"]["sha512"])
        self.assertEqual(len(manifest["licenses"]), 2)

    def test_version_and_tag_are_inferred_not_overridden(self) -> None:
        identity = project_identity(REPOSITORY / "game")
        self.assertEqual(identity["tag"], "v0.4.0-preview")
        self.assertEqual(identity["inputSchemaVersion"], 3)
        for tag in ("0.4.0-preview", "v0.3.0-preview", "v9.0.0", "refs/tags/v0.4.0-preview"):
            with self.subTest(tag=tag), self.assertRaises(ReleaseError):
                project_identity(REPOSITORY / "game", tag)

    def test_preset_zero_semantics_are_preserved(self) -> None:
        text = (REPOSITORY / "game" / "export_presets.cfg").read_text(encoding="utf-8")
        expected = {
            "name": "Windows Desktop", "platform": "Windows Desktop", "runnable": True,
            "advanced_options": False, "dedicated_server": False, "custom_features": "",
            "export_filter": "all_resources", "include_filter": "",
            "exclude_filter": "tests/*,tests/**/*,assets/_pipeline_probe_*,match/validation.png",
            "export_path": "../build/windows/FutsalG1.exe", "encrypt_pck": False, "encrypt_directory": False,
        }
        options = {
            "custom_template/debug": "", "custom_template/release": "", "debug/export_console_wrapper": 0,
            "binary_format/embed_pck": True, "binary_format/architecture": "x86_64",
            "texture_format/s3tc_bptc": True, "texture_format/etc2_astc": False,
            "codesign/enable": False, "application/modify_resources": False,
        }
        for section, values in (("preset.0", expected), ("preset.0.options", options)):
            for key, value in values.items():
                self.assertEqual(setting(text, section, key), value, key)
        self.assertEqual(text.count('[preset.0]'), 1)
        self.assertEqual(setting(text, "preset.2.options", "codesign/codesign"), 1)
        self.assertEqual(setting(text, "preset.2.options", "notarization/notarization"), 0)

    def test_only_private_preset_receives_absolute_template(self) -> None:
        original = (REPOSITORY / "game" / "export_presets.cfg").read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / "export_presets.cfg").write_bytes(original)
            manifest = load_manifest(HERE / "manifest.json")
            template = project / "owned-template.exe"
            configure_private_preset(project, manifest["platforms"]["windows-x86_64"], template,
                                     project_identity(REPOSITORY / "game"))
            text = (project / "export_presets.cfg").read_text(encoding="utf-8")
            self.assertEqual(setting(text, "preset.0.options", "custom_template/release"), str(template))
            self.assertEqual((REPOSITORY / "game" / "export_presets.cfg").read_bytes(), original)

    def test_snapshot_rejects_unresolved_lfs_and_ignores_import_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            (project / "source.gd").write_text("extends Node\n", encoding="utf-8")
            (project / ".godot").mkdir()
            (project / ".godot" / "cache").write_bytes(b"transient")
            self.assertEqual(set(source_snapshot(project)), {"source.gd"})
            (project / "asset.glb").write_text("version https://git-lfs.github.com/spec/v1\noid sha256:x\n")
            with self.assertRaises(ReleaseError):
                source_snapshot(project)

    def test_workflow_has_only_pinned_actions_and_no_publish_permission(self) -> None:
        import re
        text = (REPOSITORY / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
        pins = load_manifest(HERE / "manifest.json")["actions"]
        used = re.findall(r"uses:\s+([^@\s]+)@([0-9a-f]+)", text)
        self.assertEqual({name for name, _ in used}, set(pins))
        for name, revision in used:
            self.assertEqual(revision, pins[name]["commit"])
        self.assertIn("max-parallel: 3", text)
        self.assertIn("contents: read", text)
        self.assertNotIn("contents: write", text)
        self.assertNotIn("gh release", text)
        self.assertIn("github.event.repository.private == false", text)
        self.assertEqual(text.count("persist-credentials: false"), 2)
        triggers = text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(re.findall(r"(?m)^  ([a-z_]+):", triggers), ["workflow_dispatch"])
        self.assertIn("      version:\n", triggers)
        self.assertIn("        required: true\n", triggers)
        self.assertIn("        type: string\n", triggers)
        self.assertIn("        default: v0.4.0-preview\n", triggers)
        self.assertIn("FUTSAL_RELEASE_VERSION: ${{ inputs.version }}", text)
        self.assertIn("github.event_name == 'workflow_dispatch'", text)
        self.assertNotIn("refs/tags/", text)
        for name in PLATFORMS:
            self.assertIn("- platform: " + name, text)
        for runner in ("windows-2025", "ubuntu-24.04", "macos-15"):
            self.assertIn("runner: " + runner, text)


class ArchiveTests(unittest.TestCase):
    def test_deterministic_zip_and_unpacked_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / "payload"
            (payload / "folder").mkdir(parents=True)
            (payload / "folder" / "data.pck").write_bytes(b"payload" * 200)
            (payload / "Futsal.exe").write_bytes(b"binary")
            first = root / "one.zip"
            second = root / "two.zip"
            index = deterministic_zip(payload, first)
            os.utime(payload / "Futsal.exe", (1800000000, 1800000000))
            self.assertEqual(deterministic_zip(payload, second), index)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            extract_zip(first, root / "installed")
            self.assertEqual(tree_index(root / "installed"), index)
            with self.assertRaises(ReleaseError):
                deterministic_zip(payload, first)

    def _zip(self, path: Path, entries: list[tuple[str, bytes, int]]) -> None:
        with zipfile.ZipFile(path, "w") as archive:
            for name, data, mode in entries:
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = mode << 16
                archive.writestr(info, data)

    def test_unix_exec_and_symlink_metadata_survive_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "mac.zip"
            self._zip(archive, [
                ("Futsal.app/Contents/MacOS/Futsal", b"exec", stat.S_IFREG | 0o755),
                ("Futsal.app/Contents/Frameworks/Versions/A/lib", b"lib", stat.S_IFREG | 0o755),
                ("Futsal.app/Contents/Frameworks/Versions/Current", b"A", stat.S_IFLNK | 0o777),
            ])
            index = verify_zip(archive)
            self.assertEqual(index["Futsal.app/Contents/MacOS/Futsal"]["mode"], 0o755)
            link = "Futsal.app/Contents/Frameworks/Versions/Current"
            self.assertEqual(index[link]["target"], "A")
            with mock.patch("tools.release.archive.os.symlink") as symlink:
                extract_zip(archive, root / "installed")
                symlink.assert_called_once_with("A", root / "installed" / link)

    def test_archive_rejects_traversal_duplicates_devices_and_privileges(self) -> None:
        cases = [
            [("../escape", b"x", stat.S_IFREG | 0o644)],
            [("C:/escape", b"x", stat.S_IFREG | 0o644)],
            [("A", b"x", stat.S_IFREG | 0o644), ("a", b"x", stat.S_IFREG | 0o644)],
            [("fifo", b"", stat.S_IFIFO | 0o644)],
            [("setuid", b"x", stat.S_IFREG | 0o4755)],
            [("parent", b"x", stat.S_IFREG | 0o644), ("parent/file", b"x", stat.S_IFREG | 0o644)],
        ]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, entries in enumerate(cases):
                with self.subTest(index=index):
                    archive = root / f"{index}.zip"
                    self._zip(archive, entries)
                    with self.assertRaises(ReleaseError):
                        extract_zip(archive, root / f"out-{index}")
                    self.assertFalse((root / f"out-{index}").exists())

    def test_archive_rejects_absolute_dangling_and_cyclic_symlinks(self) -> None:
        cases = [
            [("link", b"/etc", stat.S_IFLNK | 0o777)],
            [("link", b"../outside", stat.S_IFLNK | 0o777)],
            [("link", b"missing", stat.S_IFLNK | 0o777)],
            [("a", b"b", stat.S_IFLNK | 0o777), ("b", b"a", stat.S_IFLNK | 0o777)],
        ]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for index, entries in enumerate(cases):
                self._zip(root / f"{index}.zip", entries)
                with self.subTest(index=index), self.assertRaises(ReleaseError):
                    verify_zip(root / f"{index}.zip")

    def test_archive_enforces_decompressed_byte_limit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "x.zip"
            self._zip(path, [("data", b"12345", stat.S_IFREG | 0o644)])
            with zipfile.ZipFile(path) as archive, self.assertRaises(ReleaseError):
                zip_entries(archive, maximum_bytes=4)

    def test_verified_cache_reused_and_corruption_not_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = b"verified"
            path = root / "archive.zip"
            path.write_bytes(data)
            item = {"name": path.name, "bytes": len(data), "sha512": hashlib.sha512(data).hexdigest(),
                    "url": "https://invalid.example/never"}
            with mock.patch("urllib.request.urlopen", side_effect=AssertionError("network not allowed")):
                self.assertEqual(obtain(item, root), path)
                path.write_bytes(b"corrupt!")
                with self.assertRaises(ReleaseError):
                    obtain(item, root)
                self.assertEqual(path.read_bytes(), b"corrupt!")

    def test_partial_download_is_not_promoted(self) -> None:
        import io
        class Response(io.BytesIO):
            def geturl(self) -> str:
                return "https://github.com/official"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            item = {"name": "archive.zip", "bytes": 3, "sha512": hashlib.sha512(b"abc").hexdigest(),
                    "url": "https://github.com/official"}
            with mock.patch("urllib.request.urlopen", return_value=Response(b"ab")), self.assertRaises(ReleaseError):
                obtain(item, root)
            self.assertEqual(list(root.iterdir()), [])


class BinaryTests(unittest.TestCase):
    def test_pe_elf_and_universal_architectures(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pe = bytearray(256)
            pe[:2] = b"MZ"
            struct.pack_into("<I", pe, 60, 64)
            pe[64:68] = b"PE\0\0"
            struct.pack_into("<H", pe, 68, 0x8664)
            struct.pack_into("<H", pe, 88, 0x20B)
            (root / "win").write_bytes(pe)
            self.assertEqual(binary_architectures(root / "win"), ["x86_64"])
            elf = bytearray(64)
            elf[:6] = b"\x7fELF\x02\x01"
            struct.pack_into("<H", elf, 18, 62)
            (root / "linux").write_bytes(elf)
            self.assertEqual(binary_architectures(root / "linux"), ["x86_64"])
            fat = bytearray(192)
            struct.pack_into(">II", fat, 0, 0xCAFEBABE, 2)
            struct.pack_into(">IIIII", fat, 8, 0x01000007, 0, 64, 32, 0)
            struct.pack_into(">IIIII", fat, 28, 0x0100000C, 0, 128, 32, 0)
            struct.pack_into("<II", fat, 64, 0xFEEDFACF, 0x01000007)
            struct.pack_into("<II", fat, 128, 0xFEEDFACF, 0x0100000C)
            (root / "mac").write_bytes(fat)
            self.assertEqual(binary_architectures(root / "mac"), ["arm64", "x86_64"])
            struct.pack_into(">I", fat, 28, 0x01000007)
            (root / "mac").write_bytes(fat)
            with self.assertRaises(ReleaseError):
                binary_architectures(root / "mac")

    def test_empty_and_invalid_binary_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fake"
            for value in (b"", b"MZ", b"\x7fELF", b"not an executable"):
                path.write_bytes(value)
                with self.subTest(value=value), self.assertRaises(ReleaseError):
                    binary_architectures(path)

    def test_collection_requires_exactly_three_archives(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, self.assertRaises(ReleaseError):
            verify_collection(REPOSITORY, Path(temporary), "a" * 40, "v0.4.0-preview")


if __name__ == "__main__":
    unittest.main()
