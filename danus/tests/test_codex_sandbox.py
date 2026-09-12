"""The macOS nested-launch exception must depend on the kernel, not env flags."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

_path = Path(__file__).resolve().parents[2] / "scripts" / "codex-sandbox.py"
_spec = importlib.util.spec_from_file_location("codex_sandbox_probe", _path)
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)


class SandboxProbeTests(unittest.TestCase):
    def test_environment_marker_cannot_enable_exception(self):
        lib = MagicMock()
        lib.sandbox_check.return_value = 0
        with patch.object(probe.sys, "platform", "darwin"), \
             patch.object(probe.ctypes, "CDLL", return_value=lib), \
             patch.dict(probe.os.environ, {"CODEX_SANDBOX": "seatbelt"}):
            self.assertFalse(probe.inherited_seatbelt())

    def test_confirmed_inherited_sandbox_needs_no_environment_marker(self):
        lib = MagicMock()
        lib.sandbox_check.return_value = 1
        with patch.object(probe.sys, "platform", "darwin"), \
             patch.object(probe.ctypes, "CDLL", return_value=lib), \
             patch.dict(probe.os.environ, {}, clear=True):
            self.assertTrue(probe.inherited_seatbelt())
        lib.sandbox_check.assert_called_once_with(probe.os.getpid(), None, 0)

    def test_kernel_error_keeps_normal_sandbox(self):
        lib = MagicMock()
        lib.sandbox_check.return_value = -1
        with patch.object(probe.sys, "platform", "darwin"), \
             patch.object(probe.ctypes, "CDLL", return_value=lib):
            self.assertFalse(probe.inherited_seatbelt())

    def test_unavailable_probe_keeps_normal_sandbox(self):
        for failure in (OSError("unavailable"), AttributeError("missing symbol")):
            with self.subTest(failure=failure), \
                 patch.object(probe.sys, "platform", "darwin"), \
                 patch.object(probe.ctypes, "CDLL", side_effect=failure):
                self.assertFalse(probe.inherited_seatbelt())

    def test_other_platform_never_uses_macos_exception(self):
        with patch.object(probe.sys, "platform", "linux"), \
             patch.object(probe.ctypes, "CDLL") as load:
            self.assertFalse(probe.inherited_seatbelt())
            load.assert_not_called()


if __name__ == "__main__":
    unittest.main()
