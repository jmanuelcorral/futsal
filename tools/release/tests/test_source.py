from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.release.build import HERE, commit_identity, source_snapshot
from tools.release.common import ReleaseError
from tools.release.source import committed_inputs, require_git_root, source_documents, verify_committed_inputs
from tools.release.tests.git_fixture import GitFixture

ASSET_DIRECTORY = Path("game") / "assets" / "athletes" / "court_athlete"
METADATA_NAMES = (
    "court_athlete.glb.import",
    *(f"court_athlete_{part}_{map_type}.png.import"
      for part in ("gear", "kit", "skin") for map_type in ("albedo", "normal", "orm")),
    "provenance.json", "rig_manifest.json",
)


class SourceTests(unittest.TestCase):
    def _metadata_fixture(self, root: Path) -> tuple[GitFixture, dict[str, bytes]]:
        fixture = GitFixture(root, autocrlf=True)
        original = HERE.parents[1] / ASSET_DIRECTORY
        self.assertEqual({path.name for path in original.glob("*.import")},
                         {name for name in METADATA_NAMES if name.endswith(".import")})
        payloads = {}
        for name in METADATA_NAMES:
            relative = (ASSET_DIRECTORY / name).as_posix()
            data = (original / name).read_bytes().replace(b"\r\n", b"\n")
            self.assertIn(b"\n", data)
            path = fixture.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            payloads[relative] = data
        fixture.commit = fixture.commit_all()
        return fixture, payloads

    def test_git_checkout_keeps_all_twelve_metadata_files_lf_with_autocrlf(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture, payloads = self._metadata_fixture(Path(temporary) / "repo")
            for name in payloads:
                (fixture.root / name).unlink()
            fixture.git("checkout-index", "--force", "--", *payloads)
            for name, data in payloads.items():
                with self.subTest(path=name):
                    attributes = fixture.git("check-attr", "text", "eol", "--", name).splitlines()
                    self.assertEqual(attributes, [name + ": text: set", name + ": eol: lf"])
                    self.assertEqual((fixture.root / name).read_bytes(), data)
            self.assertEqual(verify_committed_inputs(fixture.root, fixture.commit, HERE),
                             source_snapshot(fixture.root / "game"))

    def test_lf_crlf_metadata_matches_git_without_hiding_content_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture, payloads = self._metadata_fixture(Path(temporary) / "repo")
            expected = source_snapshot(fixture.root / "game")
            self.assertEqual(verify_committed_inputs(fixture.root, fixture.commit, HERE), expected)
            for name, data in payloads.items():
                with self.subTest(path=name):
                    path = fixture.root / name
                    assumed = False
                    try:
                        git_object = fixture.git("rev-parse", fixture.commit + ":" + name)
                        self.assertEqual(fixture.git("hash-object", "--path=" + name, name), git_object)
                        path.write_bytes(data.replace(b"\n", b"\r\n"))
                        self.assertEqual(fixture.git("hash-object", "--path=" + name, name), git_object)
                        self.assertEqual(verify_committed_inputs(fixture.root, fixture.commit, HERE), expected)
                        self.assertEqual(source_snapshot(fixture.root / "game"), expected)
                        fixture.git("update-index", "--assume-unchanged", "--", name)
                        assumed = True
                        mutation = (data.replace(b"{", b'{"eol_fixture_changed":true,', 1)
                                    if name.endswith(".json") else data + b"\n[eol_fixture]\nchanged=true\n")
                        path.write_bytes(mutation.replace(b"\n", b"\r\n"))
                        self.assertEqual(fixture.git("status", "--porcelain", "--", name), "")
                        self.assertNotEqual(fixture.git("hash-object", "--path=" + name, name), git_object)
                        with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                            verify_committed_inputs(fixture.root, fixture.commit, HERE)
                        self.assertNotEqual(source_snapshot(fixture.root / "game"), expected)
                    finally:
                        path.write_bytes(data)
                        if assumed:
                            fixture.git("update-index", "--no-assume-unchanged", "--", name)

    def test_binary_assets_preserve_raw_bytes_under_autocrlf(self) -> None:
        for suffix in (".glb", ".png", ".blend"):
            with self.subTest(suffix=suffix), tempfile.TemporaryDirectory() as temporary:
                fixture = GitFixture(Path(temporary) / "repo", autocrlf=True)
                data = b"\0binary fixture\nsame length\r\npayload"
                name = "game/asset" + suffix
                path = fixture.root / name
                if suffix in (".glb", ".blend"):
                    pointer = ("version https://git-lfs.github.com/spec/v1\n"
                               "oid sha256:" + hashlib.sha256(data).hexdigest() + "\nsize " + str(len(data)) + "\n")
                    path.write_bytes(pointer.encode("ascii"))
                else:
                    path.write_bytes(data)
                commit = fixture.commit_all()
                self.assertEqual(fixture.git("check-attr", "text", "--", name), name + ": text: unset")
                fixture.git("update-index", "--assume-unchanged", "--", name)
                path.write_bytes(data)
                expected = source_snapshot(fixture.root / "game")
                self.assertEqual(expected["asset" + suffix], hashlib.sha256(data).hexdigest())
                self.assertEqual(verify_committed_inputs(fixture.root, commit, HERE), expected)
                for mutation in (data.replace(b"\r\n", b"\n\r"), data.replace(b"\n", b"\r\n")):
                    path.write_bytes(mutation)
                    self.assertNotEqual(source_snapshot(fixture.root / "game"), expected)
                    with self.assertRaisesRegex(ReleaseError, "bytes de fuente|Tamano LFS"):
                        verify_committed_inputs(fixture.root, commit, HERE)

    def test_git_attribute_policy_is_a_consumed_text_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo", autocrlf=True)
            self.assertIn(".gitattributes", committed_inputs(fixture.root, fixture.commit))
            path = fixture.root / ".gitattributes"
            data = path.read_bytes().replace(b"\r\n", b"\n")
            path.write_bytes(data.replace(b"\n", b"\r\n"))
            self.assertEqual(verify_committed_inputs(fixture.root, fixture.commit, HERE),
                             source_snapshot(fixture.root / "game"))
            fixture.git("update-index", "--assume-unchanged", "--", ".gitattributes")
            path.write_bytes(data + b"\n*.import -text\n")
            self.assertEqual(fixture.git("status", "--porcelain"), "")
            with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                verify_committed_inputs(fixture.root, fixture.commit, HERE)

    def test_project_notice_is_consumed_even_when_git_status_hides_a_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            path = fixture.root / "THIRD_PARTY_NOTICES.md"
            self.assertIn("THIRD_PARTY_NOTICES.md", committed_inputs(fixture.root, fixture.commit))
            original = path.read_bytes()
            fixture.git("update-index", "--assume-unchanged", "--", "THIRD_PARTY_NOTICES.md")
            path.write_bytes(original + b"\nUncommitted notice change.\n")
            self.assertEqual(fixture.git("status", "--porcelain"), "")
            with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                commit_identity(fixture.root, fixture.commit, False)

    def test_notice_snapshot_requires_complete_regular_utf8_source_from_05(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            identity = {"projectVersion": "0.5.0-preview"}
            self.assertEqual(source_documents(root, {"projectVersion": "0.4.0-preview"}), ({}, None))
            with self.assertRaisesRegex(ReleaseError, "THIRD_PARTY_NOTICES"):
                source_documents(root, identity)
            path = root / "THIRD_PARTY_NOTICES.md"
            for data in (b"", b" \r\n", b"\xff", b"x" * (1024 * 1024 + 1)):
                with self.subTest(data_size=len(data)):
                    path.write_bytes(data)
                    with self.assertRaises((ReleaseError, UnicodeDecodeError)):
                        source_documents(root, identity)
            data = "Dan Ulrich - CC0\nAvisos íntegros.\n".encode("utf-8")
            results = []
            for current in (data, data.replace(b"\n", b"\r\n")):
                path.write_bytes(current)
                snapshot, notice = source_documents(root, identity)
                self.assertEqual(snapshot, {"THIRD_PARTY_NOTICES.md": hashlib.sha256(data).hexdigest()})
                self.assertEqual(notice["sha256"], hashlib.sha256(current).hexdigest())
                self.assertEqual(notice["bytes"], len(current))
                results.append(snapshot)
            self.assertEqual(results[0], results[1])
            path.unlink()
            path.mkdir()
            with self.assertRaisesRegex(ReleaseError, "regular"):
                source_documents(root, identity)

    def test_real_clean_checkout_is_bound_to_git_blobs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            self.assertEqual(commit_identity(fixture.root, fixture.commit, False), fixture.commit)
            self.assertEqual(verify_committed_inputs(fixture.root, fixture.commit, HERE),
                             source_snapshot(fixture.root / "game"))
            self.assertIsNone(commit_identity(fixture.root, fixture.commit, True))

    def test_nested_ignored_snapshot_cannot_claim_parent_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            nested = fixture.root / "ignored-snapshot"
            shutil.copytree(fixture.root / "game", nested / "game")
            shutil.copytree(fixture.root / "tools", nested / "tools")
            self.assertEqual(fixture.git("status", "--porcelain", "--", "game", "tools", cwd=nested), "")
            with self.assertRaisesRegex(ReleaseError, "raiz Git efectiva"):
                commit_identity(nested, fixture.commit, False)
            self.assertIsNone(commit_identity(nested, fixture.commit, True))

    def test_assume_unchanged_and_skip_worktree_do_not_hide_changed_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            path = fixture.root / "game" / "payload.gd"
            original = path.read_bytes()
            for flag in ("assume-unchanged", "skip-worktree"):
                with self.subTest(flag=flag):
                    fixture.git("update-index", "--" + flag, "--", "game/payload.gd")
                    path.write_bytes(original + b"# hidden change\n")
                    self.assertEqual(fixture.git("status", "--porcelain"), "")
                    with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                        commit_identity(fixture.root, fixture.commit, False)
                    path.write_bytes(original)
                    fixture.git("update-index", "--no-" + flag, "--", "game/payload.gd")

    def test_ignored_game_or_tooling_files_cannot_enter_a_committed_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            for name in ("game/ignored.bin", "tools/release/ignored.py"):
                with self.subTest(name=name):
                    path = fixture.root / name
                    path.write_bytes(b"uncommitted input")
                    self.assertEqual(fixture.git("status", "--porcelain"), "")
                    with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                        commit_identity(fixture.root, fixture.commit, False)
                    path.unlink()

    def test_wrong_requested_sha_is_rejected_in_a_real_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            with self.assertRaisesRegex(ReleaseError, "commit solicitado"):
                commit_identity(fixture.root, "0" * 40, False)

    def test_external_checkout_cannot_claim_different_executing_tooling(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            path = fixture.root / "tools" / "release" / "__main__.py"
            path.write_bytes(path.read_bytes() + b"\n# a different committed tool\n")
            other = fixture.commit_all()
            self.assertEqual(fixture.git("status", "--porcelain"), "")
            with self.assertRaisesRegex(ReleaseError, "tooling ejecutado"):
                commit_identity(fixture.root, other, False)

    def test_text_eol_normalization_does_not_hide_other_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            path = fixture.root / "game" / "payload.gd"
            fixture.git("update-index", "--assume-unchanged", "--", "game/payload.gd")
            path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
            self.assertEqual(commit_identity(fixture.root, fixture.commit, False), fixture.commit)
            path.write_bytes(path.read_bytes() + b"# not just EOL\r\n")
            with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                commit_identity(fixture.root, fixture.commit, False)

    def test_expanded_lfs_bytes_and_size_match_the_committed_pointer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            data = b"binary fixture payload"
            pointer = ("version https://git-lfs.github.com/spec/v1\n"
                       "oid sha256:" + hashlib.sha256(data).hexdigest() + "\nsize " + str(len(data)) + "\n")
            path = fixture.root / "game" / "asset.glb"
            path.write_text(pointer, encoding="ascii", newline="\n")
            commit = fixture.commit_all()
            fixture.git("update-index", "--assume-unchanged", "--", "game/asset.glb")
            path.write_bytes(data)
            self.assertEqual(committed_inputs(fixture.root, commit)["game/asset.glb"], hashlib.sha256(data).hexdigest())
            self.assertEqual(commit_identity(fixture.root, commit, False), commit)
            path.write_bytes(b"x" * len(data))
            with self.assertRaisesRegex(ReleaseError, "bytes de fuente"):
                commit_identity(fixture.root, commit, False)
            path.write_bytes(data + b"x")
            with self.assertRaisesRegex(ReleaseError, "Tamano LFS"):
                commit_identity(fixture.root, commit, False)

    def test_effective_git_root_uses_resolved_platform_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = GitFixture(Path(temporary) / "repo")
            alias = fixture.root / "game" / ".."
            require_git_root(alias)
            if os.name == "nt":
                require_git_root(Path(str(fixture.root).upper()))
