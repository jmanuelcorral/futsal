from __future__ import annotations

import os
import shutil
from pathlib import Path

from tools.release.build import HERE
from tools.release.common import require
from tools.release.process import run_process


class GitFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        root.mkdir()
        settings = root.parent / (root.name + "-settings")
        settings.mkdir()
        (settings / "empty").write_bytes(b"")
        (settings / "hooks").mkdir()
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.environment.update({
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": str(settings / "empty"),
            "GIT_TERMINAL_PROMPT": "0",
        })
        self.prefix = [
            "git", "-c", "user.name=Release Fixture", "-c", "user.email=release-fixture@example.invalid",
            "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false", "-c", "gc.auto=0",
            "-c", "maintenance.auto=false", "-c", "core.hooksPath=" + str(settings / "hooks"),
            "-c", "core.attributesFile=" + str(settings / "empty"),
        ]
        self.git("-c", "init.defaultBranch=main", "init", "--quiet", "--template=" + str(settings / "hooks"))
        (root / "game").mkdir()
        repository = HERE.parents[1]
        shutil.copyfile(repository / "game" / "project.godot", root / "game" / "project.godot")
        (root / "game" / "payload.gd").write_text("extends Node\n", encoding="utf-8", newline="\n")
        shutil.copytree(HERE, root / "tools" / "release",
                        ignore=shutil.ignore_patterns("__pycache__", ".cache", "runtime", "*.pyc", "*.pyo"))
        (root / ".github" / "workflows").mkdir(parents=True)
        shutil.copyfile(repository / ".github" / "workflows" / "release.yml",
                        root / ".github" / "workflows" / "release.yml")
        (root / ".gitignore").write_text(
            "build/\nignored-snapshot/\ngame/ignored.bin\ntools/release/ignored.py\n"
            "tools/release/.cache/\ntools/release/runtime/\n__pycache__/\n",
            encoding="utf-8", newline="\n",
        )
        self.commit = self.commit_all()

    def git(self, *arguments: str, cwd: Path | None = None) -> str:
        result = run_process([*self.prefix, *arguments], cwd or self.root,
                             timeout=10, environment=self.environment)
        require(result.ok, "Fallo en Git fixture: " + result.stderr.decode("utf-8", errors="replace"))
        return result.stdout.decode("utf-8").strip()

    def commit_all(self) -> str:
        self.git("add", "--all")
        self.git("commit", "--quiet", "--no-gpg-sign", "-m", "Isolated release test fixture")
        return self.git("rev-parse", "HEAD")
