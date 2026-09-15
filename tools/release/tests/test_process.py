from __future__ import annotations

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from tools.release.common import ReleaseError
from tools.release.process import WindowsAvailability, recorded_process, run_process


class ProcessTests(unittest.TestCase):
    def test_real_original_process_exit_and_both_eof(self) -> None:
        result = run_process([sys.executable, "-c", "import sys; print('out'); print('err',file=sys.stderr)"],
                             Path.cwd(), timeout=5)
        self.assertTrue(result.ok)
        self.assertGreater(result.pid, 0)
        self.assertEqual(result.exit_code, 0)
        self.assertIn(b"out", result.stdout)
        self.assertIn(b"err", result.stderr)
        self.assertTrue(result.metadata()["outputComplete"])

    def test_regular_input_file_keeps_original_exit_and_both_eof(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "input.bin"
            data = b"first\0line\nsecond\r\n" * 4096
            path.write_bytes(data)
            result = run_process([sys.executable, "-c", "import sys; sys.stdout.buffer.write(sys.stdin.buffer.read())"],
                                 Path(temporary), timeout=5, input_file=path)
            self.assertTrue(result.ok)
            self.assertEqual(result.stdout, data)
            self.assertEqual(path.read_bytes(), data)
            path.unlink()

    def test_missing_input_file_does_not_launch_a_process(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch("tools.release.process.subprocess.Popen") as spawn:
            with self.assertRaises(FileNotFoundError):
                run_process([sys.executable, "-c", "pass"], Path(temporary), timeout=5,
                            input_file=Path(temporary) / "absent")
            spawn.assert_not_called()

    def test_nonzero_never_becomes_success(self) -> None:
        result = run_process([sys.executable, "-c", "print('before'); raise SystemExit(7)"],
                             Path.cwd(), timeout=5)
        self.assertFalse(result.ok)
        self.assertEqual(result.exit_code, 7)
        self.assertIn(b"before", result.stdout)

    def test_timeout_terminates_only_owned_process(self) -> None:
        result = run_process([sys.executable, "-c", "import time; time.sleep(5)"],
                             Path.cwd(), timeout=0.15, cleanup_seconds=1)
        self.assertFalse(result.ok)
        self.assertIn("Deadline", result.error)
        self.assertIsNotNone(result.exit_code)
        self.assertLess(result.wall_seconds, 2)

    def test_inherited_pipes_do_not_make_final_drain_unbounded(self) -> None:
        child = "import time; time.sleep(1.1)"
        command = f"import subprocess,sys; subprocess.Popen([sys.executable,'-c',{child!r}]); print('parent done',flush=True)"
        result = run_process([sys.executable, "-c", command], Path.cwd(), timeout=0.15, cleanup_seconds=0.15)
        try:
            self.assertFalse(result.ok)
            self.assertEqual(result.exit_code, 0, (result.metadata(), result.stdout, result.stderr))
            self.assertFalse(result.stdout_complete)
            self.assertLess(result.wall_seconds, 0.9)
        finally:
            time.sleep(1.2)

    def test_output_size_is_bounded(self) -> None:
        result = run_process([sys.executable, "-c", "import sys; sys.stdout.buffer.write(b'x'*1048576)"],
                             Path.cwd(), timeout=5, output_limit=1024)
        self.assertFalse(result.ok)
        self.assertIn("Limite", result.error)
        self.assertLessEqual(len(result.stdout), 1024)

    def test_failure_keeps_raw_logs_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            proof = Path(temporary) / "proof"
            with self.assertRaises(ReleaseError):
                recorded_process([sys.executable, "-c", "print('evidence'); raise SystemExit(2)"],
                                 Path.cwd(), proof, timeout=5)
            self.assertIn(b"evidence", (proof / "stdout.log").read_bytes())
            self.assertTrue((proof / "process.json").is_file())
            with self.assertRaises(ReleaseError):
                recorded_process([sys.executable, "-c", "pass"], Path.cwd(), proof, timeout=5)

    def test_scoped_power_and_platform_isolation(self) -> None:
        availability = WindowsAvailability()
        with availability:
            self.assertEqual(availability.metadata["applicable"], os.name == "nt")
            self.assertEqual(availability.metadata["acquired"], os.name == "nt")
            self.assertFalse(availability.metadata["changesGlobalPowerPolicy"])
        self.assertEqual(availability.metadata["released"], os.name == "nt")
        self.assertIsNone(availability.handle)

    def test_scoped_power_released_on_error(self) -> None:
        availability = WindowsAvailability()
        with self.assertRaisesRegex(ValueError, "intentional"):
            with availability:
                raise ValueError("intentional")
        self.assertEqual(availability.metadata["released"], os.name == "nt")
        self.assertIsNone(availability.handle)


if __name__ == "__main__":
    unittest.main()
