#!/usr/bin/env python3
"""
Cross-platform installer for Arena.ai Local Bridge (Chrome Native Messaging Host).
Supports Linux, macOS, and Windows (Chrome, Chromium, Brave, Edge).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List

HOST_NAME = "com.arena.local_bridge"
EXT_ID_RE = re.compile(r"^[a-p]{32}$")

LINUX_DIRS: Dict[str, Path] = {
    "chrome": Path.home() / ".config/google-chrome/NativeMessagingHosts",
    "chromium": Path.home() / ".config/chromium/NativeMessagingHosts",
    "brave": Path.home() / ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts",
    "edge": Path.home() / ".config/microsoft-edge/NativeMessagingHosts",
}

MAC_DIRS: Dict[str, Path] = {
    "chrome": Path.home() / "Library/Application Support/Google/Chrome/NativeMessagingHosts",
    "chromium": Path.home() / "Library/Application Support/Chromium/NativeMessagingHosts",
    "brave": Path.home() / "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
    "edge": Path.home() / "Library/Application Support/Microsoft Edge/NativeMessagingHosts",
}

WIN_REG_KEYS: Dict[str, str] = {
    "chrome": rf"Software\Google\Chrome\NativeMessagingHosts\{HOST_NAME}",
    "chromium": rf"Software\Chromium\NativeMessagingHosts\{HOST_NAME}",
    "brave": rf"Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\{HOST_NAME}",
    "edge": rf"Software\Microsoft\Edge\NativeMessagingHosts\{HOST_NAME}",
}


def get_host_script_path() -> Path:
    return (Path(__file__).resolve().parent.parent / "native-host" / "host.py").resolve()


def get_data_dir() -> Path:
    return Path.home() / ".arena-local-bridge"


def write_config(workspace_root: Path, data_dir: Path) -> Path:
    data_dir.mkdir(parents=True, exist_ok=True)
    cfg_path = data_dir / "config.json"
    config = {
        "workspace_root": str(workspace_root),
        "allowed_tools": ["ping", "list_dir", "read_file", "write_file", "run_command"],
        "default_timeout_sec": 30,
        "max_output_bytes": 32768,
        "max_read_bytes": 131072,
        "lock_workspace": True,
    }
    if cfg_path.is_file():
        try:
            existing = json.loads(cfg_path.read_text(encoding="utf-8"))
            if isinstance(existing, dict):
                existing["workspace_root"] = str(workspace_root)
                config = {**config, **existing}
        except Exception:
            pass
    cfg_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return cfg_path


def build_manifest(host_exec_path: Path, extension_id: str) -> Dict[str, object]:
    return {
        "name": HOST_NAME,
        "description": "Arena.ai Local Terminal & Tool Bridge Native Messaging Host",
        "path": str(host_exec_path),
        "type": "stdio",
        "allowed_origins": [f"chrome-extension://{extension_id}/"],
    }


def install_unix(manifest: Dict[str, object], browser: str, custom_dir: Path | None) -> List[Path]:
    written: List[Path] = []
    if custom_dir is not None:
        targets = [custom_dir]
    else:
        dir_map = MAC_DIRS if sys.platform == "darwin" else LINUX_DIRS
        if browser == "all":
            targets = [p for p in dir_map.values() if p.parent.exists()]
            if not targets:
                targets = [dir_map["chrome"]]
        else:
            targets = [dir_map[browser]]

    payload = json.dumps(manifest, indent=2) + "\n"
    for target_dir in targets:
        target_dir.mkdir(parents=True, exist_ok=True)
        out_file = target_dir / f"{HOST_NAME}.json"
        out_file.write_text(payload, encoding="utf-8")
        written.append(out_file)
    return written


def install_windows(host_py: Path, extension_id: str, browser: str, data_dir: Path) -> List[str]:
    import winreg  # type: ignore

    data_dir.mkdir(parents=True, exist_ok=True)
    bat_path = data_dir / "host_wrapper.bat"
    bat_content = f'@echo off\r\n"{sys.executable}" "{host_py}" %*\r\n'
    bat_path.write_text(bat_content, encoding="utf-8")

    manifest = build_manifest(bat_path, extension_id)
    manifest_path = data_dir / f"{HOST_NAME}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    keys = list(WIN_REG_KEYS.values()) if browser == "all" else [WIN_REG_KEYS[browser]]
    registered: List[str] = []
    for key_path in keys:
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            winreg.SetValueEx(key, "", 0, winreg.REG_SZ, str(manifest_path))
        registered.append(f"HKCU\\{key_path}")
    return registered


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Arena.ai Local Bridge Native Messaging Kurulumu")
    p.add_argument("--extension-id", help="Chrome Eklenti ID (32 karakterlik a-p dizesi)")
    p.add_argument("--workspace", help="Araclarin calisabilecegi izinli proje klasoru")
    p.add_argument(
        "--browser",
        choices=["all", "chrome", "chromium", "brave", "edge"],
        default="all",
        help="Hedef tarayici (varsayilan: all)",
    )
    p.add_argument("--native-dir", help="Opsiyonel ozel NativeMessagingHosts klasoru (Linux/macOS)")
    p.add_argument("--data-dir", help="Opsiyonel config klasoru (varsayilan: ~/.arena-local-bridge)")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    ext_id = (args.extension_id or "").strip()
    if not ext_id:
        ext_id = input("Chrome Eklenti ID'sini girin (orn. abcdefghijklmnopabcdefghijklmnop): ").strip()

    if not EXT_ID_RE.match(ext_id):
        print(
            f"[HATA] Gecersiz Chrome Eklenti ID: '{ext_id}'. "
            "Chrome'da chrome://extensions sayfasindan 32 karakterlik ID'yi kopyalayin.",
            file=sys.stderr,
        )
        return 1

    ws_raw = (args.workspace or "").strip()
    if not ws_raw:
        ws_raw = input("Izin verilen calisma klasoru (workspace_root) yolu: ").strip()
    if not ws_raw:
        print("[HATA] workspace yolu bos olamaz.", file=sys.stderr)
        return 1

    workspace_root = Path(ws_raw).expanduser().resolve()
    if not workspace_root.is_dir():
        print(f"[HATA] Klasor bulunamadi: {workspace_root}", file=sys.stderr)
        return 1

    host_py = get_host_script_path()
    if not host_py.is_file():
        print(f"[HATA] host.py bulunamadi: {host_py}", file=sys.stderr)
        return 1

    data_dir = Path(args.data_dir).expanduser().resolve() if args.data_dir else get_data_dir()
    cfg_path = write_config(workspace_root, data_dir)

    if os.name == "nt":
        locs = install_windows(host_py, ext_id, args.browser, data_dir)
    else:
        os.chmod(host_py, 0o755)
        manifest = build_manifest(host_py, ext_id)
        custom_dir = Path(args.native_dir).expanduser().resolve() if args.native_dir else None
        locs = [str(p) for p in install_unix(manifest, args.browser, custom_dir)]

    print("\nKurulum tamamlandi!")
    print(f"  Config dosyasi : {cfg_path}")
    print(f"  Workspace root : {workspace_root}")
    print(f"  Native Host    : {host_py}")
    print("  Kayit noktasi  :")
    for loc in locs:
        print(f"    - {loc}")
    print("\nSimdi Chrome eklenti popup'indan 'Baglantiyi Test Et (Ping)' butonuna basabilirsiniz.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
