#!/usr/bin/env python3
"""
Uninstaller for Arena.ai Local Bridge Native Messaging Host.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from install import HOST_NAME, LINUX_DIRS, MAC_DIRS, WIN_REG_KEYS


def main() -> int:
    removed = 0
    if os.name == "nt":
        import winreg  # type: ignore

        for key_path in WIN_REG_KEYS.values():
            try:
                winreg.DeleteKey(winreg.HKEY_CURRENT_USER, key_path)
                print(f"Silindi: HKCU\\{key_path}")
                removed += 1
            except FileNotFoundError:
                pass
    else:
        dir_map = MAC_DIRS if sys.platform == "darwin" else LINUX_DIRS
        for target_dir in dir_map.values():
            manifest_file = target_dir / f"{HOST_NAME}.json"
            if manifest_file.exists():
                manifest_file.unlink()
                print(f"Silindi: {manifest_file}")
                removed += 1

    print(f"Toplam {removed} Native Messaging kaydi kaldirildi.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
