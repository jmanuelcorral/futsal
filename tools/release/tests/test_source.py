from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.release.build import HERE, commit_identity, source_snapshot
from tools.release.common import ReleaseError
from tools.release.source import committed_inputs, require_git_root, verify_committed_inputs
from tools.release.tests.git_fixture import GitFixture


class SourceTests(unittest.TestCase):
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
