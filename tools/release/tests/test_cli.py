from __future__ import annotations

import contextlib
import copy
import io
import os
import re
import shlex
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

from tools.release import __main__ as cli
from tools.release.build import HERE, PLATFORMS, source_snapshot
from tools.release.common import read_json, strict_json
from tools.release.tests.git_fixture import GitFixture
from tools.release.tests.test_audit import CandidateFixture, candidate_manifest, release_variant_mutations

REPOSITORY = HERE.parents[1]
COMMIT = "a" * 40
VERSION = "v0.4.0-preview"


class CliTests(unittest.TestCase):
    def environment(self) -> dict[str, str]:
        return {
            "GITHUB_ACTIONS": "true",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": COMMIT,
            "FUTSAL_RELEASE_VERSION": VERSION,
        }

    def invoke(self, arguments: list[str], environment: dict[str, str]) -> tuple[int, str, str]:
        output, errors = io.StringIO(), io.StringIO()
        host = {key: value for key, value in os.environ.items() if key not in self.environment()}
        with mock.patch.object(os, "environ", {**host, **environment}), \
                mock.patch.object(sys, "argv", ["tools.release", *arguments]), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = cli.main()
        return result, output.getvalue(), errors.getvalue()

    def test_manual_main_build_accepts_version_without_git_tag(self) -> None:
        with mock.patch.object(cli, "build") as build:
            result, _, errors = self.invoke(
                ["build", "--platform", "windows-x86_64", "--commit", COMMIT, "--tag", VERSION],
                self.environment(),
            )
        self.assertEqual((result, errors), (0, ""))
        build.assert_called_once()
        self.assertEqual(build.call_args.kwargs, {"tag": VERSION, "commit": COMMIT, "allow_uncommitted": False})

    def test_ci_build_rejects_automatic_events_or_unbound_identity(self) -> None:
        base = ["build", "--platform", "windows-x86_64", "--commit", COMMIT, "--tag", VERSION]
        variants = [
            ("push", {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/tags/" + VERSION}, base),
            ("pull-request", {"GITHUB_EVENT_NAME": "pull_request"}, base),
            ("missing-event", {"GITHUB_EVENT_NAME": ""}, base),
            ("missing-sha", {"GITHUB_SHA": ""}, base),
            ("invalid-sha", {"GITHUB_SHA": "not-a-commit"}, base),
            ("wrong-sha", {"GITHUB_SHA": "b" * 40}, base),
            ("missing-commit", {}, ["build", "--platform", "windows-x86_64", "--tag", VERSION]),
            ("local", {}, [*base, "--allow-uncommitted"]),
            ("missing-input", {"FUTSAL_RELEASE_VERSION": ""}, base),
            ("different-input", {"FUTSAL_RELEASE_VERSION": "v0.3.0-preview"}, base),
            ("missing-version-argument", {}, ["build", "--platform", "windows-x86_64", "--commit", COMMIT]),
        ]
        for name, changes, arguments in variants:
            with self.subTest(name=name), mock.patch.object(cli, "build") as build:
                result, _, errors = self.invoke(arguments, {**self.environment(), **changes})
                self.assertEqual(result, 1)
                self.assertIn("ERROR release:", errors)
                build.assert_not_called()

    def test_ci_verifier_accepts_the_same_manual_version_and_commit(self) -> None:
        evidence = {"archives": [{"sha256": "0" * 64, "archive": "fixture.zip"}]}
        with tempfile.TemporaryDirectory() as temporary, \
                mock.patch.object(cli, "verify_collection", return_value=evidence) as verify:
            root = Path(temporary)
            index = root / "verified" / "release-index.json"
            result, _, errors = self.invoke(
                ["verify", "--directory", str(root), "--commit", COMMIT, "--tag", VERSION,
                 "--index", str(index)],
                self.environment(),
            )
            self.assertEqual((result, errors), (0, ""))
            verify.assert_called_once_with(Path.cwd().resolve(), root.resolve(), COMMIT, VERSION)
            self.assertEqual(read_json(index), evidence)
            self.assertEqual(index.with_name("SHA256SUMS").read_text(encoding="ascii"),
                             "0" * 64 + "  fixture.zip\n")

    def test_ci_verifier_rejects_unbound_requests_before_writing(self) -> None:
        for changes in ({"FUTSAL_RELEASE_VERSION": ""}, {"FUTSAL_RELEASE_VERSION": "v0.3.0-preview"},
                        {"GITHUB_SHA": "b" * 40}, {"GITHUB_EVENT_NAME": "push"}):
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as temporary, \
                    mock.patch.object(cli, "verify_collection") as verify:
                root = Path(temporary)
                index = root / "release-index.json"
                result, _, errors = self.invoke(
                    ["verify", "--directory", str(root), "--commit", COMMIT, "--tag", VERSION,
                     "--index", str(index)],
                    {**self.environment(), **changes},
                )
                self.assertEqual(result, 1)
                self.assertIn("ERROR release:", errors)
                verify.assert_not_called()
                self.assertFalse(index.exists())
                self.assertFalse(index.with_name("SHA256SUMS").exists())

    def test_dispatch_version_must_match_real_project_before_native_work(self) -> None:
        target = {"win32": "windows-x86_64", "linux": "linux-x86_64", "darwin": "macos-universal"}[sys.platform]
        with tempfile.TemporaryDirectory() as temporary, \
                mock.patch("tools.release.build.commit_identity") as commit, \
                mock.patch("tools.release.build.obtain") as obtain:
            root = Path(temporary).resolve()
            (root / "game").mkdir()
            (root / "game" / "project.godot").write_bytes((REPOSITORY / "game" / "project.godot").read_bytes())
            result, _, errors = self.invoke(
                ["build", "--platform", target, "--repository", str(root),
                 "--output", str(root / "build" / "release"), "--commit", COMMIT, "--tag", "v9.9.9"],
                {**self.environment(), "FUTSAL_RELEASE_VERSION": "v9.9.9"},
            )
            self.assertEqual(result, 1)
            self.assertIn("no coincide", errors)
            commit.assert_not_called()
            obtain.assert_not_called()
            self.assertFalse((root / "build").exists())

    def test_local_mode_does_not_require_dispatch_or_version_input(self) -> None:
        with mock.patch.object(cli, "build") as build:
            result, _, errors = self.invoke(
                ["build", "--platform", "windows-x86_64", "--allow-uncommitted"],
                {"GITHUB_EVENT_NAME": "push"},
            )
        self.assertEqual((result, errors), (0, ""))
        self.assertEqual(build.call_args.kwargs, {"tag": None, "commit": None, "allow_uncommitted": True})

    def test_ci_fixture_does_not_mutate_the_native_process_environment(self) -> None:
        with mock.patch.object(os, "putenv") as put, mock.patch.object(os, "unsetenv") as unset, \
                mock.patch.object(cli, "build"):
            result, _, errors = self.invoke(
                ["build", "--platform", "windows-x86_64", "--commit", COMMIT, "--tag", VERSION],
                self.environment(),
            )
            self.assertEqual((result, errors), (0, ""))
            put.assert_not_called()
            unset.assert_not_called()

    def test_passive_audit_does_not_require_a_dispatch(self) -> None:
        evidence = {
            "archive": "fixture.zip", "archiveSha256": "0" * 64, "commit": None,
            "platform": "windows-x86_64", "publishableCandidate": False,
            "buildType": "release",
        }
        with mock.patch.object(cli, "audit_candidate", return_value=evidence) as audit:
            result, output, errors = self.invoke(["audit", "--archive", "fixture.zip"],
                                                 {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "workflow_run"})
        self.assertEqual((result, errors), (0, ""))
        self.assertIn('"liveProcessesLaunched": false', output)
        self.assertIn('"buildType": "release"', output)
        result_json = strict_json(output)
        self.assertIsNone(result_json["templateEntry"])
        self.assertIsNone(result_json["templateSha256"])
        self.assertEqual(result_json["sha256"], evidence["archiveSha256"])
        audit.assert_called_once()

    def test_passive_audit_discloses_linux_debug_workaround(self) -> None:
        evidence = {
            "archive": "fixture.zip", "archiveSha256": "0" * 64, "commit": None,
            "platform": "linux-x86_64", "publishableCandidate": False, "buildType": "debug",
            "engineWorkaround": "https://github.com/godotengine/godot/issues/87626",
            "templateEntry": "templates/linux_debug.x86_64",
            "templateSha256": "1a291d3d15e4180b60b0af96cf6458f11fe143636d76575ddf1e23d1a3f24f2e",
        }
        with mock.patch.object(cli, "audit_candidate", return_value=evidence):
            result, output, errors = self.invoke(["audit", "--archive", "fixture.zip"], {})
        self.assertEqual((result, errors), (0, ""))
        self.assertIn('"buildType": "debug"', output)
        self.assertIn("https://github.com/godotengine/godot/issues/87626", output)
        result_json = strict_json(output)
        self.assertEqual(result_json["templateEntry"], evidence["templateEntry"])
        self.assertEqual(result_json["templateSha256"], evidence["templateSha256"])
        self.assertEqual(result_json["sha256"], evidence["archiveSha256"])
        self.assertNotEqual(result_json["templateSha256"], result_json["sha256"])

    def test_passive_audit_accepts_release_absence_and_null_without_claiming_provenance(self) -> None:
        manifest = candidate_manifest()
        for platform_id in ("windows-x86_64", "macos-universal"):
            with tempfile.TemporaryDirectory() as temporary:
                fixture = CandidateFixture(Path(temporary), platform_id, manifest)
                original = copy.deepcopy(fixture.metadata)
                with mock.patch("tools.release.build.load_manifest", return_value=manifest):
                    for explicit in (False, True):
                        with self.subTest(platform=platform_id, explicit=explicit):
                            fields = {"templateEntry": None, "templateSha256": None,
                                      "engineWorkaround": None} if explicit else {}
                            fixture.metadata = {**copy.deepcopy(original), **fields}
                            fixture.replace_embedded_build({**fixture.embedded, **fields})
                            result, output, errors = self.invoke(
                                ["audit", "--repository", str(REPOSITORY), "--archive", str(fixture.archive)], {})
                            self.assertEqual((result, errors), (0, ""))
                            report = strict_json(output)
                            self.assertIs(report["ok"], True)
                            self.assertEqual(report["buildType"], "release")
                            for field in ("templateEntry", "templateSha256", "engineWorkaround"):
                                self.assertIsNone(report[field])

    def test_passive_audit_rejects_unaccredited_release_variant_before_projecting(self) -> None:
        manifest = candidate_manifest()
        for platform_id in ("windows-x86_64", "macos-universal"):
            with tempfile.TemporaryDirectory() as temporary:
                fixture = CandidateFixture(Path(temporary), platform_id, manifest)
                original = copy.deepcopy(fixture.metadata)
                changes = release_variant_mutations(platform_id)
                with mock.patch("tools.release.build.load_manifest", return_value=manifest):
                    for label in ("typed-pair", "linux-debug-provenance", "workaround-url", "buildType-bool"):
                        for location in ("outer", "embedded", "both"):
                            with self.subTest(platform=platform_id, change=label, location=location):
                                fixture.metadata = copy.deepcopy(original)
                                embedded = dict(fixture.embedded)
                                if location != "embedded":
                                    fixture.metadata.update(changes[label])
                                if location != "outer":
                                    embedded.update(changes[label])
                                fixture.replace_embedded_build(embedded)
                                result, output, errors = self.invoke(
                                    ["audit", "--repository", str(REPOSITORY), "--archive", str(fixture.archive)], {})
                                self.assertEqual(result, 1)
                                self.assertEqual(output, "")
                                self.assertIn("ERROR release:", errors)

    def test_verifier_rejects_unaccredited_release_variant_before_writing_index(self) -> None:
        manifest = candidate_manifest()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = GitFixture(root / "repo")
            snapshot = source_snapshot(checkout.root / "game")
            fixtures = {name: CandidateFixture(root, name, manifest, checkout.commit, snapshot)
                        for name in PLATFORMS}
            with mock.patch("tools.release.build.load_manifest", return_value=manifest):
                for platform_id in ("windows-x86_64", "macos-universal"):
                    fixture = fixtures[platform_id]
                    original = copy.deepcopy(fixture.metadata)
                    changes = release_variant_mutations(platform_id)
                    for label in ("typed-pair", "linux-debug-provenance", "workaround-url", "buildType-bool"):
                        for location in ("outer", "both"):
                            with self.subTest(platform=platform_id, change=label, location=location):
                                fixture.metadata = {**copy.deepcopy(original), **changes[label]}
                                embedded = {**fixture.embedded, **changes[label]} if location == "both" else fixture.embedded
                                fixture.replace_embedded_build(embedded)
                                index = root / "indexes" / platform_id / label / location / "release-index.json"
                                result, output, errors = self.invoke(
                                    ["verify", "--repository", str(checkout.root), "--directory", str(root),
                                     "--commit", checkout.commit, "--tag", VERSION, "--index", str(index)], {})
                                self.assertEqual(result, 1)
                                self.assertEqual(output, "")
                                self.assertIn("ERROR release:", errors)
                                self.assertFalse(index.exists())
                                self.assertFalse(index.with_name("SHA256SUMS").exists())
                    fixture.metadata = original
                    fixture.replace_embedded_build(fixture.embedded)

    def test_workflow_python_forwards_version_input_on_main(self) -> None:
        workflow = (REPOSITORY / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
        blocks = re.findall(r"(?m)^        run: \|\n((?:          .*\n|[ \t]*\n)+)", workflow)
        self.assertEqual(len(blocks), 3)
        version = "v9.9.9-input-is-not-hardcoded"
        for executable in ("python", "python3"):
            environment = {
                **self.environment(), "FUTSAL_RELEASE_VERSION": version,
                "RELEASE_PLATFORM": "windows-x86_64", "RELEASE_PYTHON": executable,
            }
            with mock.patch.object(os, "environ", environment), mock.patch("subprocess.run") as run:
                commands = [
                    shlex.split(os.path.expandvars(textwrap.dedent(block).replace("\\\n", " ")))
                    for block in blocks[:2]
                ]
                exec(compile(textwrap.dedent(blocks[2]), str(REPOSITORY / ".github" / "workflows" / "release.yml"), "exec"), {})
            self.assertEqual(commands[0], [executable, "-m", "unittest", "discover", "-s", "tools/release/tests", "-v"])
            self.assertEqual(run.call_count, 1)
            commands.append(run.call_args.args[0])
            for arguments, command, interpreter in (
                (commands[1], "build", executable), (commands[2], "verify", sys.executable),
            ):
                self.assertEqual(arguments[:4], [interpreter, "-m", "tools.release", command])
                self.assertEqual(arguments[arguments.index("--commit") + 1], COMMIT)
                self.assertEqual(arguments[arguments.index("--tag") + 1], version)
                self.assertEqual(arguments.count("--tag"), 1)
            self.assertEqual(run.call_args.kwargs, {"check": True})

    def test_workflow_shells_are_literal(self) -> None:
        workflow = (REPOSITORY / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
        shells = re.findall(r"(?m)^\s+shell: (.+)$", workflow)
        self.assertEqual(shells, ["bash", "bash", "python3 {0}"])
        self.assertIn("RELEASE_PYTHON: ${{ matrix.python }}", workflow)
        self.assertIn('"$RELEASE_PYTHON" -m tools.release build', workflow)
