"""Detect an inherited macOS sandbox without trusting environment markers.

A nested Codex cannot apply Seatbelt again (sandbox_apply exits 71). Its shell
children must use the existing OS sandbox instead. This probe never removes or
changes that sandbox; an unavailable/failed probe keeps Codex's normal policy.
"""

import ctypes
import os
import sys


def inherited_seatbelt() -> bool:
    if sys.platform != "darwin":
        return False
    try:
        lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        check = lib.sandbox_check
        check.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        check.restype = ctypes.c_int
        return check(os.getpid(), None, 0) == 1
    except (AttributeError, OSError):
        return False


if __name__ == "__main__":
    sys.exit(0 if inherited_seatbelt() else 1)
