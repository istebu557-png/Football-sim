#!/usr/bin/env python3
"""
Arena.ai Local Bridge - Localhost HTTP Server (Option 2B)
Easy-setup local bridge listening strictly on 127.0.0.1 with Bearer Token
and browser Origin verification, including in-process PTY terminal sessions.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Optional

SERVER_DIR = Path(__file__).resolve().parent
NATIVE_HOST_DIR = SERVER_DIR.parent / "native-host"
if str(NATIVE_HOST_DIR) not in sys.path:
    sys.path.insert(0, str(NATIVE_HOST_DIR))

import host  # type: ignore  # noqa: E402
import terminal_daemon  # type: ignore  # noqa: E402

DEFAULT_PORT = 38450
SERVER_VERSION = "1.2.0"


def ensure_server_config(
    *,
    port: Optional[int] = None,
    workspace: Optional[str] = None,
    full_access: Optional[bool] = None,
    custom_token: Optional[str] = None,
    regenerate_token: bool = False,
) -> Dict[str, Any]:
    cfg_path = host.get_config_path()
    cfg_path.parent.mkdir(parents=True, exist_ok=True)

    existing: Dict[str, Any] = {}
    if cfg_path.is_file():
        try:
            loaded = json.loads(cfg_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                existing = loaded
        except Exception:
            existing = {}

    if "full_system_access" not in existing and full_access is None:
        full_access = True  # Default to full access for Option 2B easy setup

    if full_access is not None:
        existing["full_system_access"] = bool(full_access)
        existing["lock_workspace"] = not bool(full_access)

    if workspace:
        ws_resolved = str(Path(workspace).expanduser().resolve())
        if not os.path.isdir(ws_resolved):
            raise FileNotFoundError(f"Workspace klasoru bulunamadi: {ws_resolved}")
        existing["workspace_root"] = ws_resolved
    elif not existing.get("workspace_root"):
        existing["workspace_root"] = str(Path.home().resolve())

    if port is not None:
        existing["server_port"] = int(port)
    elif not existing.get("server_port"):
        existing["server_port"] = DEFAULT_PORT

    if custom_token:
        existing["server_token"] = custom_token.strip()
    elif regenerate_token or not existing.get("server_token"):
        existing["server_token"] = secrets.token_hex(24)

    existing_tools = list(existing.get("allowed_tools") or [])
    existing["allowed_tools"] = list(dict.fromkeys(existing_tools + list(host.DEFAULT_ALLOWED_TOOLS)))
    existing.setdefault("default_timeout_sec", host.DEFAULT_TIMEOUT_SEC)
    existing.setdefault("max_output_bytes", host.DEFAULT_MAX_OUTPUT_BYTES)
    existing.setdefault("max_read_bytes", host.DEFAULT_MAX_READ_BYTES)

    cfg_path.write_text(json.dumps(existing, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if os.name != "nt":
        try:
            os.chmod(cfg_path, 0o600)
        except Exception:
            pass
    return existing


class LocalBridgeHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address, RequestHandlerClass, session_manager: terminal_daemon.SessionManager):
        self.session_manager = session_manager
        super().__init__(server_address, RequestHandlerClass)


class LocalBridgeHandler(BaseHTTPRequestHandler):
    server: LocalBridgeHTTPServer

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        # Keep terminal output clean; write tool execution logs via host.audit_log
        return

    def _set_cors_headers(self) -> None:
        origin = self.headers.get("Origin", "")
        if origin.startswith(("chrome-extension://", "moz-extension://")):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Cache-Control", "no-store")

    def _send_json(self, status_code: int, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._set_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _check_origin_and_auth(self, config: Dict[str, Any]) -> Optional[str]:
        origin = self.headers.get("Origin", "").strip()
        if origin and not origin.startswith(("chrome-extension://", "moz-extension://")):
            return "403: Tarayici web sayfalarindan dogrudan erisim engellendi."

        expected_token = str(config.get("server_token") or "")
        auth_header = self.headers.get("Authorization", "")
        if not expected_token:
            return "401: Sunucu token'i yapilandirilmamis."
        if not auth_header.startswith("Bearer "):
            return "401: Eksik Authorization Bearer token."
        provided = auth_header[7:].strip()
        if not secrets.compare_digest(provided, expected_token):
            return "401: Gecersiz API Token."
        return None

    def do_OPTIONS(self) -> None:  # noqa: N802
        origin = self.headers.get("Origin", "").strip()
        if origin and not origin.startswith(("chrome-extension://", "moz-extension://")):
            self._send_json(403, {"ok": False, "error": "Forbidden origin"})
            return
        self.send_response(204)
        self._set_cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/api/health":
            self._send_json(200, {"ok": True, "service": "arena-local-bridge", "version": SERVER_VERSION})
            return

        if self.path == "/api/ping":
            config = host.load_config()
            err = self._check_origin_and_auth(config)
            if err:
                code = 403 if err.startswith("403:") else 401
                self._send_json(code, {"ok": False, "error": err})
                return
            result = host.handle_ping(config)
            result["transport"] = "localhost_http"
            result["server_version"] = SERVER_VERSION
            self._send_json(200, {"id": "ping", "ok": True, "result": result})
            return

        self._send_json(404, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/api/tool":
            self._send_json(404, {"ok": False, "error": "Not found"})
            return

        config = host.load_config()
        err = self._check_origin_and_auth(config)
        if err:
            code = 403 if err.startswith("403:") else 401
            self._send_json(code, {"ok": False, "error": err})
            return

        try:
            content_len = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"ok": False, "error": "Gecersiz Content-Length"})
            return

        if content_len <= 0 or content_len > 16 * 1024 * 1024:
            self._send_json(400, {"ok": False, "error": "Gecersiz istek boyutu"})
            return

        raw_body = self.rfile.read(content_len)
        try:
            request = json.loads(raw_body.decode("utf-8"))
        except Exception as exc:
            self._send_json(400, {"ok": False, "error": f"Gecersiz JSON: {exc}"})
            return

        if not isinstance(request, dict):
            self._send_json(400, {"ok": False, "error": "Istek JSON nesnesi olmalidir"})
            return

        req_id = request.get("id")
        tool = request.get("tool")
        args = request.get("args") or {}
        if not isinstance(args, dict):
            self._send_json(400, {"id": req_id, "ok": False, "error": "'args' bir JSON nesnesi olmalidir."})
            return

        allowed = config.get("allowed_tools", host.DEFAULT_ALLOWED_TOOLS)
        if tool not in allowed:
            host.audit_log({"tool": tool, "ok": False, "reason": "tool_not_allowed"})
            self._send_json(
                200,
                {
                    "id": req_id,
                    "ok": False,
                    "error": f"'{tool}' araci config.json tarafindan devre disi birakilmis.",
                },
            )
            return

        # Handle persistent interactive terminals directly in-process via SessionManager
        if tool in ("terminal_start", "terminal_write", "terminal_read", "terminal_list", "terminal_kill"):
            try:
                result = self._handle_terminal(tool, args, config)
                host.audit_log(
                    {
                        "id": req_id,
                        "tool": tool,
                        "ok": True,
                        "target": args.get("session_id") or args.get("cwd") or ".",
                    }
                )
                self._send_json(200, {"id": req_id, "ok": True, "result": result})
            except Exception as exc:
                host.audit_log({"id": req_id, "tool": tool, "ok": False, "error": str(exc)})
                self._send_json(200, {"id": req_id, "ok": False, "error": str(exc)})
            return

        response = host.dispatch(request)
        if response.get("ok") and isinstance(response.get("result"), dict) and tool == "ping":
            response["result"]["transport"] = "localhost_http"
            response["result"]["server_version"] = SERVER_VERSION
        self._send_json(200, response)

    def _handle_terminal(self, tool: str, args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        mgr = self.server.session_manager
        if tool == "terminal_start":
            ws = host.get_workspace_root(config)
            full = host.is_full_access(config)
            cwd_real, _ = host.resolve_safe_path(ws, args.get("cwd", "."), full_access=full)
            start_args = dict(args)
            start_args["cwd"] = cwd_real
            res = mgr.start(start_args)
        elif tool == "terminal_write":
            res = mgr.write(args)
        elif tool == "terminal_read":
            res = mgr.read(args)
        elif tool == "terminal_list":
            res = mgr.list_sessions()
        elif tool == "terminal_kill":
            res = mgr.kill(args)
        else:
            raise ValueError(f"Bilinmeyen terminal araci: {tool}")

        res["tool"] = tool
        if isinstance(res.get("output"), str):
            max_out = int(config.get("max_output_bytes", host.DEFAULT_MAX_OUTPUT_BYTES))
            trimmed, trunc = host.truncate_text(res["output"], max_out)
            res["output"] = trimmed
            if trunc:
                res["truncated"] = True
        return res


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Arena.ai Local Bridge - Localhost Sunucusu (2B)")
    p.add_argument("--port", type=int, help=f"Dinlenecek 127.0.0.1 portu (varsayilan: {DEFAULT_PORT})")
    p.add_argument("--workspace", help="Varsayilan calisma klasoru")
    p.add_argument("--full-access", action="store_true", help="Tum bilgisayara erisim modunu ac")
    p.add_argument("--restricted", action="store_true", help="Yalnizca workspace klasorune kilitle")
    p.add_argument("--token", help="Ozel API Token belirle")
    p.add_argument("--regenerate-token", action="store_true", help="Yeni rastgele API Token uret")
    p.add_argument("--print-token", action="store_true", help="Mevcut API Token'i yazdir ve cik")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if args.full_access and args.restricted:
        print("[HATA] --full-access ve --restricted ayni anda kullanilamaz.", file=sys.stderr)
        return 1

    full_flag: Optional[bool] = True if args.full_access else (False if args.restricted else None)
    cfg = ensure_server_config(
        port=args.port,
        workspace=args.workspace,
        full_access=full_flag,
        custom_token=args.token,
        regenerate_token=args.regenerate_token,
    )

    if args.print_token:
        print(cfg["server_token"])
        return 0

    port = int(cfg.get("server_port", DEFAULT_PORT))
    token = str(cfg["server_token"])
    full_access = bool(cfg.get("full_system_access", False))

    session_manager = terminal_daemon.SessionManager()
    server = LocalBridgeHTTPServer(("127.0.0.1", port), LocalBridgeHandler, session_manager=session_manager)

    def handle_sig(_signum, _frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(sig, handle_sig)
        except Exception:
            pass

    print("=" * 64)
    print("  Arena.ai Local Bridge (Secenek 2B - Localhost HTTP)")
    print("=" * 64)
    print(f"  Sunucu Adresi : http://127.0.0.1:{port}")
    print(f"  Erisim Modu   : {'TUM BILGISAYAR (Tam Erisim)' if full_access else 'Klasor Kilidi (Workspace Jail)'}")
    print(f"  Varsayilan CWD: {cfg.get('workspace_root')}")
    print(f"  Config        : {host.get_config_path()}")
    print(f"  API Token     : {token}")
    print("-" * 64)
    print("  Chrome eklenti simgesine tiklayip yukaridaki API Token'i girin.")
    print("  Durdurmak icin Ctrl+C basin.")
    print("=" * 64, flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        session_manager.close_all()
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
