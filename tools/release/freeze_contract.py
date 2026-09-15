"""Mantenimiento explicito del oraculo, nunca invocado por build ni por CI."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .common import read_json, require, text_digest


def freeze(reviewed_all: Path, repository: Path, output: Path, replace_reviewed: bool = False) -> None:
    run = read_json(reviewed_all)
    require(run["ok"] is True and run["gameplayValidated"] is True and
            run["runnerPassed"] == run["runnerTotal"], "Se requiere un All completo revisado.")
    protocols = {}
    for protocol, prefix in (("legacy", ""), ("gameplay", "gameplay-")):
        variants = {}
        for variant, stage in (("source", "source-headless"), ("export", "artifact-headless")):
            report = read_json(Path(run["reports"][prefix + stage]["path"]))
            require(report["ok"] is True and report["complete"] is True, "Informe incompleto.")
            names = [check["name"] for check in report["checks"]]
            require(len(set(names)) == len(names) == report["passed"] == report["total"],
                    "Checks del oraculo duplicados o incompletos.")
            require(all(check["passed"] is True for check in report["checks"]), "Oraculo con fallos.")
            variants[variant] = {
                "checks": names,
                "rootKeys": sorted(report),
                "modeSequence": [change["requested_mode"] for change in report["mode_changes"]],
                "focusCases": [change["case"] for change in report["focus_changes"]],
            }
            if protocol == "gameplay":
                variants[variant]["caseKeys"] = {
                    case["case"]: sorted(case) for case in report["gameplay"]["cases"]
                }
        protocols[protocol] = variants
    producers = (
        "diagnostics/match_smoke.gd", "diagnostics/gameplay_smoke.gd",
        "match/match.gd",
    )
    result = {
        "schemaVersion": 1,
        "projectVersion": run["projectVersion"],
        "inputSchemaVersion": run["inputSchemaVersion"],
        "provenance": "Identidades literales del All revisado " + reviewed_all.parent.name,
        "hashFormat": "UTF-8 con CRLF normalizado a LF; sin regeneracion durante build.",
        "producers": {name: text_digest(repository / "game" / name) for name in producers},
        "protocols": protocols,
    }
    require(not output.exists() or replace_reviewed, "El oraculo existente no se sobrescribe implicitamente.")
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reviewed-all", required=True, type=Path)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--replace-reviewed", action="store_true")
    args = parser.parse_args()
    freeze(args.reviewed_all, args.repository, args.output, args.replace_reviewed)
