from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

from .build import PLATFORMS, audit_candidate, build, verify_collection
from .common import ReleaseError, require, write_json


def validate_ci_request(commit: str | None, tag: str | None, *, local: bool = False) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true":
        require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
                "Release CI solo admite workflow_dispatch; no push/tag automatico.")
        expected_commit = os.environ.get("GITHUB_SHA", "")
        require(re.fullmatch(r"[0-9a-f]{40}", expected_commit) is not None
                and commit == expected_commit and not local,
                "CI exige el commit del checkout, nunca modo local.")
        version = os.environ.get("FUTSAL_RELEASE_VERSION", "")
        require(bool(version) and tag == version,
                "CI exige --tag igual al input version del dispatch.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build/validacion de release nativa; no publica en GitHub.")
    commands = parser.add_subparsers(dest="command", required=True)
    builder = commands.add_parser("build")
    builder.add_argument("--platform", required=True, choices=PLATFORMS)
    builder.add_argument("--repository", type=Path, default=Path.cwd())
    builder.add_argument("--output", type=Path, default=Path("build") / "release")
    builder.add_argument("--cache", type=Path, default=Path("build") / "release" / "cache")
    builder.add_argument("--tag")
    builder.add_argument("--commit")
    builder.add_argument("--allow-uncommitted", action="store_true")
    verifier = commands.add_parser("verify")
    verifier.add_argument("--repository", type=Path, default=Path.cwd())
    verifier.add_argument("--directory", required=True, type=Path)
    verifier.add_argument("--commit", required=True)
    verifier.add_argument("--tag")
    verifier.add_argument("--index", required=True, type=Path)
    auditor = commands.add_parser("audit")
    auditor.add_argument("--repository", type=Path, default=Path.cwd())
    auditor.add_argument("--archive", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == "build":
            validate_ci_request(args.commit, args.tag, local=args.allow_uncommitted)
            build(args.repository, args.platform, args.output, args.cache, tag=args.tag,
                  commit=args.commit, allow_uncommitted=args.allow_uncommitted)
        elif args.command == "verify":
            validate_ci_request(args.commit, args.tag)
            result = verify_collection(args.repository.resolve(), args.directory.resolve(), args.commit, args.tag)
            write_json(args.index, result)
            checksums = args.index.with_name("SHA256SUMS")
            with checksums.open("x", encoding="ascii", newline="\n") as handle:
                for archive in result["archives"]:
                    handle.write(archive["sha256"] + "  " + archive["archive"] + "\n")
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            metadata = audit_candidate(args.repository.resolve(), args.archive.resolve())
            print(json.dumps({
                "ok": True, "archive": metadata["archive"], "sha256": metadata["archiveSha256"],
                "commit": metadata["commit"], "platform": metadata["platform"],
                "publishableCandidate": metadata["publishableCandidate"],
                "published": False, "liveProcessesLaunched": False, "technicalReviewPending": True,
                "scope": "Auditoria pasiva de bytes y evidencia archivada; no acepta procesos rehidratados.",
            }, indent=2))
        return 0
    except (ReleaseError, OSError, ValueError, KeyError) as exc:
        print(f"ERROR release: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    raise SystemExit(main())
