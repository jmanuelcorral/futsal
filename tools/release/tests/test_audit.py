from __future__ import annotations

import copy
import hashlib
import json
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from tools.release.archive import tree_index, verify_zip
from tools.release.build import (
    HERE, PLATFORMS, audit_candidate, commit_identity, snapshot_digest, source_snapshot, verify_collection,
)
from tools.release.audit import process_files
from tools.release.common import ReleaseError, diagnostic_output, digest, load_manifest, project_identity, read_json, write_json
from tools.release.process import ProcessResult
from tools.release.smoke import godot_output
from tools.release.tests.git_fixture import GitFixture
from tools.release.tests.test_smoke import SmokeFixture

REPOSITORY = HERE.parents[1]


def fake_binary(platform_id: str) -> bytes:
    data = bytearray(256)
    if platform_id.startswith("windows"):
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 60, 64)
        data[64:68] = b"PE\0\0"
        struct.pack_into("<H", data, 68, 0x8664)
        struct.pack_into("<H", data, 88, 0x20B)
    elif platform_id.startswith("linux"):
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", data, 18, 62)
    else:
        struct.pack_into(">II", data, 0, 0xCAFEBABE, 2)
        struct.pack_into(">IIIII", data, 8, 0x01000007, 0, 64, 32, 0)
        struct.pack_into(">IIIII", data, 28, 0x0100000C, 0, 128, 32, 0)
        struct.pack_into("<II", data, 64, 0xFEEDFACF, 0x01000007)
        struct.pack_into("<II", data, 128, 0xFEEDFACF, 0x0100000C)
    return bytes(data)


class CandidateFixture:
    """Paquetes sinteticos para probar el auditor, no pruebas de OS/ejecucion."""

    def __init__(self, root: Path, platform_id: str, manifest: dict, commit: str | None = None,
                 snapshot: dict[str, str] | None = None) -> None:
        self.directory = root / platform_id
        self.directory.mkdir()
        self.platform_id = platform_id
        self.identity = project_identity(REPOSITORY / "game")
        self.stem = f"futsal-{self.identity['tag']}-{platform_id}"
        self.archive = self.directory / (self.stem + ".zip")
        target = manifest["platforms"][platform_id]
        binary = fake_binary(platform_id)
        binary_name = target["exportName"]
        self.files = {}
        if platform_id == "macos-universal":
            self.files["Futsal.app/Contents/Info.plist"] = plistlib.dumps({"CFBundleExecutable": "Futsal"})
            binary_name = "Futsal.app/Contents/MacOS/Futsal"
            self.files["Futsal.app/Contents/Resources/Futsal.pck"] = b"fixture pck"
        elif platform_id == "linux-x86_64":
            self.files["Futsal.pck"] = b"fixture pck"
        self.files[binary_name] = binary
        for item in manifest["licenses"]:
            self.files[item["name"]] = b"synthetic notice"
        signing = {
            "kind": "ad-hoc" if platform_id.startswith("macos") else
                    ("unsigned" if platform_id.startswith("windows") else "not-applicable"),
            "verified": platform_id.startswith("macos"), "notarized": False, "developerId": False,
            "architectures": sorted(target["architectures"]),
        }
        if platform_id.startswith("macos"):
            signing["libraries"] = {}
        snapshot = {"project.godot": "f" * 64} if snapshot is None else snapshot
        self.embedded = {
            "schemaVersion": 1, **self.identity, "platform": platform_id, "buildType": "release",
            "commit": commit, "sourceSnapshotSha256": snapshot_digest(snapshot),
            "engine": manifest["engine"]["versionOutput"], "engineEdition": "standard",
            "signing": signing, "projectLicense": None, "licensePolicy": "not-defined",
            "validationEvidenceFile": self.stem + ".build.json", "limitations": ["Synthetic unit fixture."],
        }
        self.files["BUILD.json"] = (json.dumps(self.embedded) + "\n").encode()
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name, data in sorted(self.files.items()):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | (0o755 if name == binary_name else 0o644)) << 16
                archive.writestr(info, data)
        self.proof = self.directory / "proof" / platform_id
        self.proof.mkdir(parents=True)
        write_json(self.proof / "source-snapshot.json", snapshot)
        self._process("engine-version", ["editor", "--version"], manifest["engine"]["versionOutput"] + "\n")
        self._process("import", ["editor", "--headless", "--editor", "--import"], "")
        self._process("export-release", ["editor", "--export-release", target["preset"], "output"], "")
        if platform_id.startswith("macos"):
            for label in ("export", "packaged"):
                self._process(label + "-codesign-verify", ["codesign", "--verify"], "", "valid on disk\n")
                self._process(label + "-codesign-display", ["codesign", "--display"], "", "Signature=adhoc\nTeamIdentifier=not set\n")
                self._process(label + "-lipo", ["lipo", "-archs"], "x86_64 arm64\n")
        validation = []
        for stage in ("source-legacy", "source-gameplay", "packaged-legacy", "packaged-gameplay"):
            directory = self.proof / stage
            directory.mkdir()
            editor = stage.startswith("source")
            protocol = "gameplay" if stage.endswith("gameplay") else "legacy"
            fixture = SmokeFixture(directory, protocol, editor)
            summary = fixture.validate()
            result = fixture.write()
            arguments = [str(fixture.executable), "--headless", "--audio-driver", "Dummy", "--fixed-fps", "60"]
            if editor:
                arguments += ["--path", str(directory)]
            arguments += ["--", "--gameplay-smoke" if protocol == "gameplay" else "--smoke-test",
                          "--report-path=" + str(fixture.report_path)]
            process_directory = directory / "process"
            process_directory.mkdir()
            (process_directory / "stdout.log").write_bytes(result.stdout)
            (process_directory / "stderr.log").write_bytes(result.stderr)
            write_json(process_directory / "process.json", {**result.metadata(), "arguments": arguments,
                                                            "workingDirectory": str(directory)})
            validation.append({
                "stage": stage, **summary, "process": result.metadata(),
                "executableSha256": hashlib.sha256(binary).hexdigest(),
                "reportSha256": digest(fixture.report_path),
            })
        self.metadata = {
            **self.embedded, "archive": self.archive.name, "archiveSha256": digest(self.archive),
            "archiveBytes": self.archive.stat().st_size, "contents": verify_zip(self.archive),
            "validation": {"complete": True, "stages": validation, "headlessOnly": True,
                           "renderedValidated": False, "artApproved": False, "humanFeelAccepted": False},
            "host": {"system": target["host"], "machine": "arm64" if platform_id.startswith("macos") else "x86_64"},
            "sourceCommitVerified": commit is not None, "publishableCandidate": commit is not None,
            "publicationRequiresReview": True,
            "powerAvailability": {"applicable": platform_id.startswith("windows"), "acquired": True,
                                  "released": True, "changesGlobalPowerPolicy": False},
            "evidenceFiles": tree_index(self.directory / "proof"),
            "templateArchiveSha512": manifest["engine"]["templates"]["sha512"],
            "editorArchiveSha512": target["editor"]["sha512"],
        }
        self.metadata_path = self.directory / (self.stem + ".build.json")
        self.save()
        self.archive.with_suffix(".sha256").write_text(
            digest(self.archive) + "  " + self.archive.name + "\n", encoding="ascii")

    def _process(self, name: str, arguments: list[str], stdout: str, stderr: str = "") -> None:
        directory = self.proof / name
        directory.mkdir()
        result = ProcessResult(123, 0, "2026-01-01T00:00:00Z", 1, 1.0,
                               stdout.encode(), stderr.encode(), True, True, "")
        (directory / "stdout.log").write_bytes(result.stdout)
        (directory / "stderr.log").write_bytes(result.stderr)
        write_json(directory / "process.json", {**result.metadata(), "arguments": arguments,
                                               "workingDirectory": str(directory)})

    def save(self) -> None:
        self.metadata_path.write_text(json.dumps(self.metadata), encoding="utf-8")

    def replace_process_log(self, stage: str, stream: str, data: bytes) -> None:
        directory = self.proof / stage
        if (directory / "process").is_dir():
            directory /= "process"
        (directory / (stream + ".log")).write_bytes(data)
        process = read_json(directory / "process.json")
        process[stream + "Bytes"] = len(data)
        (directory / "process.json").write_text(json.dumps(process), encoding="utf-8")
        for summary in self.metadata["validation"]["stages"]:
            if summary["stage"] == stage:
                summary["process"][stream + "Bytes"] = len(data)
                summary["reportSha256"] = digest(self.proof / stage / "report.json")
        self.metadata["evidenceFiles"] = tree_index(self.directory / "proof")
        self.save()


class AuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_manifest(HERE / "manifest.json")
        for item in self.manifest["licenses"]:
            item["bytes"] = len(b"synthetic notice")
            item["sha512"] = hashlib.sha512(b"synthetic notice").hexdigest()

    def test_exact_three_candidates_with_raw_native_proofs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = GitFixture(root / "repo")
            snapshot = source_snapshot(checkout.root / "game")
            for name in PLATFORMS:
                CandidateFixture(root, name, self.manifest, checkout.commit, snapshot)
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest):
                result = verify_collection(checkout.root, root, checkout.commit, "v0.4.0-preview")
                self.assertTrue(result["ok"])
                self.assertEqual(len(result["archives"]), 3)
                self.assertFalse(result["published"])
                self.assertTrue(result["technicalReviewPending"])

    def test_candidate_rejects_fabricated_summary_or_missing_proof(self) -> None:
        mutations = {
            "debug": lambda value: value.update(buildType="debug"),
            "schema-bool": lambda value: value.update(schemaVersion=True),
            "wrong-commit": lambda value: value.update(commit="b" * 40),
            "zero-proof": lambda value: value.update(evidenceFiles={}),
            "render-claim": lambda value: value["validation"].update(renderedValidated=True),
            "subset": lambda value: value["validation"]["stages"].pop(),
            "notarized": lambda value: value["signing"].update(notarized=True),
            "wrong-zip-exe": lambda value: value["validation"]["stages"][2].update(executableSha256="0" * 64),
            "source-mismatch": lambda value: value.update(sourceSnapshotSha256="0" * 64),
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = GitFixture(root / "repo")
            fixture = CandidateFixture(root, "windows-x86_64", self.manifest, checkout.commit,
                                       source_snapshot(checkout.root / "game"))
            original = copy.deepcopy(fixture.metadata)
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest):
                audit_candidate(checkout.root, fixture.archive, commit=checkout.commit)
                for label, mutation in mutations.items():
                    with self.subTest(label=label):
                        fixture.metadata = copy.deepcopy(original)
                        mutation(fixture.metadata)
                        fixture.save()
                        with self.assertRaises(ReleaseError):
                            audit_candidate(checkout.root, fixture.archive, commit=checkout.commit)

    def test_raw_proof_cannot_be_replaced_even_if_its_hash_is_updated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = CandidateFixture(Path(temporary), "windows-x86_64", self.manifest)
            path = fixture.proof / "packaged-gameplay" / "process" / "stdout.log"
            path.write_text("PASS fabricated\nFUTSAL_GAMEPLAY_SMOKE {}\n", encoding="utf-8")
            fixture.metadata["evidenceFiles"] = tree_index(fixture.directory / "proof")
            fixture.save()
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest), self.assertRaises(ReleaseError):
                audit_candidate(REPOSITORY, fixture.archive)

    def test_collection_rejects_extra_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in PLATFORMS:
                CandidateFixture(root, name, self.manifest)
            (root / "extra.zip").write_bytes(b"extra")
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest), self.assertRaises(ReleaseError):
                verify_collection(REPOSITORY, root, "a" * 40, None)

    def test_dirty_source_cannot_claim_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            checkout = GitFixture(Path(temporary) / "repo")
            self.assertEqual(commit_identity(checkout.root, checkout.commit, False), checkout.commit)
            (checkout.root / "game" / "payload.gd").write_text("extends Node\n# changed\n", encoding="utf-8")
            with self.assertRaises(ReleaseError):
                commit_identity(checkout.root, checkout.commit, False)

    def test_three_equal_foreign_snapshots_do_not_match_the_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = GitFixture(root / "repo")
            snapshot = source_snapshot(checkout.root / "game")
            snapshot["payload.gd"] = "0" * 64
            for name in PLATFORMS:
                CandidateFixture(root, name, self.manifest, checkout.commit, snapshot)
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest), \
                    self.assertRaisesRegex(ReleaseError, "fuente archivada no corresponde"):
                verify_collection(checkout.root, root, checkout.commit, "v0.4.0-preview")

    def test_full_candidate_rejects_parse_error_with_updated_proof_and_unchanged_zip(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = CandidateFixture(Path(temporary), "windows-x86_64", self.manifest)
            checksum = digest(fixture.archive)
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest):
                audit_candidate(REPOSITORY, fixture.archive)
                for stream in ("stdout", "stderr"):
                    with self.subTest(stream=stream):
                        fixture.replace_process_log("export-release", stream, b"Parse Error: independent counterexample\n")
                        with self.assertRaisesRegex(ReleaseError, "Parse Error"):
                            audit_candidate(REPOSITORY, fixture.archive)
                        self.assertEqual(digest(fixture.archive), checksum)
                        fixture.replace_process_log("export-release", stream, b"")

    def test_full_candidate_rejects_stdout_only_types_after_updating_all_proof_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = CandidateFixture(Path(temporary), "windows-x86_64", self.manifest)
            checksum = digest(fixture.archive)
            covered = 0
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest):
                audit_candidate(REPOSITORY, fixture.archive)
                for stage in fixture.metadata["validation"]["stages"]:
                    name = stage["stage"]
                    path = fixture.proof / name / "process" / "stdout.log"
                    original = path.read_bytes()
                    marker = "FUTSAL_GAMEPLAY_SMOKE" if name.endswith("gameplay") else "FUTSAL_MATCH_SMOKE"
                    report = read_json(fixture.proof / name / "report.json")
                    for field, value in (("mode", True), ("ok", 1), ("frames_drawn", False), ("headless", 1)):
                        if field not in report:
                            continue
                        with self.subTest(stage=name, field=field):
                            changed = copy.deepcopy(report)
                            changed[field] = value
                            text = original.decode("utf-8").split(marker + " ", 1)[0]
                            text += marker + " " + json.dumps(changed, ensure_ascii=False) + "\n"
                            fixture.replace_process_log(name, "stdout", text.encode("utf-8"))
                            with self.assertRaisesRegex(ReleaseError, "stdout y archivo difieren"):
                                audit_candidate(REPOSITORY, fixture.archive)
                            self.assertEqual(digest(fixture.archive), checksum)
                            covered += 1
                            fixture.replace_process_log(name, "stdout", original)
            self.assertEqual(covered, 14)

    def test_full_candidate_rejects_boolean_modes_when_stdout_and_report_agree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = CandidateFixture(Path(temporary), "windows-x86_64", self.manifest)
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest):
                for stage in fixture.metadata["validation"]["stages"]:
                    name = stage["stage"]
                    report_path = fixture.proof / name / "report.json"
                    original_report = report_path.read_bytes()
                    original_log = (fixture.proof / name / "process" / "stdout.log").read_bytes()
                    report = read_json(report_path)
                    report["mode_changes"][0]["requested_mode"] = bool(report["mode_changes"][0]["requested_mode"])
                    report_path.write_text(json.dumps(report), encoding="utf-8")
                    marker = "FUTSAL_GAMEPLAY_SMOKE" if name.endswith("gameplay") else "FUTSAL_MATCH_SMOKE"
                    text = original_log.decode("utf-8").split(marker + " ", 1)[0] + marker + " " + json.dumps(report) + "\n"
                    fixture.replace_process_log(name, "stdout", text.encode("utf-8"))
                    with self.subTest(stage=name), self.assertRaisesRegex(ReleaseError, "requested_mode"):
                        audit_candidate(REPOSITORY, fixture.archive)
                    report_path.write_bytes(original_report)
                    fixture.replace_process_log(name, "stdout", original_log)

    def test_full_candidate_rejects_matching_scalar_type_mutations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = CandidateFixture(Path(temporary), "windows-x86_64", self.manifest)
            covered = 0
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest):
                for stage in fixture.metadata["validation"]["stages"]:
                    name = stage["stage"]
                    report_path = fixture.proof / name / "report.json"
                    original_report = report_path.read_bytes()
                    original_log = (fixture.proof / name / "process" / "stdout.log").read_bytes()
                    original = read_json(report_path)
                    for field, value in (("mode", True), ("ok", 1), ("frames_drawn", False), ("headless", 1)):
                        if field not in original:
                            continue
                        with self.subTest(stage=name, field=field):
                            changed = copy.deepcopy(original)
                            changed[field] = value
                            report_path.write_text(json.dumps(changed), encoding="utf-8")
                            marker = "FUTSAL_GAMEPLAY_SMOKE" if name.endswith("gameplay") else "FUTSAL_MATCH_SMOKE"
                            text = original_log.decode("utf-8").split(marker + " ", 1)[0]
                            text += marker + " " + json.dumps(changed) + "\n"
                            fixture.replace_process_log(name, "stdout", text.encode("utf-8"))
                            with self.assertRaises(ReleaseError):
                                audit_candidate(REPOSITORY, fixture.archive)
                            covered += 1
                            report_path.write_bytes(original_report)
                            fixture.replace_process_log(name, "stdout", original_log)
            self.assertEqual(covered, 14)

    def test_live_and_archived_diagnostics_share_stdout_and_stderr_policy(self) -> None:
        messages = ("ERROR: x\n", "WARNING: x\n", "SCRIPT ERROR: x\n", "USER ERROR: x\n",
                    "USER WARNING: x\n", "Parse Error: x\n", "FAIL x\n")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scenarios = [(b"normal output\n", b"", True), (b"", b"normal tool detail\n", False)]
            scenarios.extend((message.encode(), b"", False) for message in messages)
            scenarios.extend((b"", message.encode(), False) for message in messages)
            for index, (stdout, stderr, engine_allowed) in enumerate(scenarios):
                directory = root / str(index)
                directory.mkdir()
                result = ProcessResult(123, 0, "", 0, 1.0, stdout, stderr, True, True, "")
                (directory / "stdout.log").write_bytes(stdout)
                (directory / "stderr.log").write_bytes(stderr)
                write_json(directory / "process.json", {**result.metadata(), "arguments": ["fixture"]})
                for tool in (False, True):
                    accepted = engine_allowed or (tool and index == 1)
                    with self.subTest(index=index, tool=tool):
                        if accepted:
                            self.assertEqual(process_files(directory, allow_tool_stderr=tool)[1:],
                                             diagnostic_output(stdout, stderr, allow_tool_stderr=tool))
                        else:
                            with self.assertRaises(ReleaseError):
                                process_files(directory, allow_tool_stderr=tool)
                            with self.assertRaises(ReleaseError):
                                diagnostic_output(stdout, stderr, allow_tool_stderr=tool)
                    if not tool:
                        if accepted:
                            self.assertEqual(godot_output(result), stdout.decode("utf-8"))
                        else:
                            with self.assertRaises(ReleaseError):
                                godot_output(result)

    def test_archived_byte_counts_cannot_be_booleans(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = CandidateFixture(Path(temporary), "windows-x86_64", self.manifest)
            process_path = fixture.proof / "export-release" / "process.json"
            process = read_json(process_path)
            process["stdoutBytes"] = False
            process_path.write_text(json.dumps(process), encoding="utf-8")
            fixture.metadata["evidenceFiles"] = tree_index(fixture.directory / "proof")
            fixture.save()
            with mock.patch("tools.release.build.load_manifest", return_value=self.manifest), \
                    self.assertRaisesRegex(ReleaseError, "stdoutBytes"):
                audit_candidate(REPOSITORY, fixture.archive)


if __name__ == "__main__":
    unittest.main()
