#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SERVER_PY = ROOT_DIR / "server" / "local_server.py"


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class LocalServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)
        self.workspace = self.tmp_path / "workspace"
        self.workspace.mkdir()
        self.data_dir = self.tmp_path / "data"
        self.data_dir.mkdir()
        self.config_path = self.data_dir / "config.json"
        self.port = find_free_port()
        self.token = "test_secret_token_123456"
        self.proc = None

    def tearDown(self) -> None:
        if self.proc is not None:
            if self.proc.poll() is None:
                self.proc.terminate()
                try:
                    self.proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
            if self.proc.stdout:
                self.proc.stdout.close()
            if self.proc.stderr:
                self.proc.stderr.close()
        self.tmp.cleanup()

    def start_server(self, extra_args=None) -> None:
        env = os.environ.copy()
        env["ARENA_BRIDGE_CONFIG"] = str(self.config_path)
        env["ARENA_BRIDGE_DATA_DIR"] = str(self.data_dir)
        cmd = [
            sys.executable,
            str(SERVER_PY),
            "--port",
            str(self.port),
            "--workspace",
            str(self.workspace),
            "--token",
            self.token,
        ]
        if extra_args:
            cmd.extend(extra_args)

        self.proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )

        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/api/health", timeout=0.5) as resp:
                    if resp.status == 200:
                        return
            except Exception:
                time.sleep(0.1)
        raise RuntimeError("local_server.py zamaninda baslamadi")

    def http_call(self, path: str, method: str = "GET", body=None, token: str | None = None, origin: str | None = None):
        headers = {}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        if origin is not None:
            headers["Origin"] = origin
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode("utf-8")

        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read().decode("utf-8"))

    def test_auth_origin_and_full_access_tools(self) -> None:
        self.start_server(["--full-access"])

        # 1. Missing token -> 401
        code, res = self.http_call("/api/ping", "GET")
        self.assertEqual(code, 401)
        self.assertFalse(res["ok"])

        # 2. Bad web origin -> 403 even with valid token
        code, res = self.http_call("/api/ping", "GET", token=self.token, origin="https://evil.example")
        self.assertEqual(code, 403)
        self.assertFalse(res["ok"])

        # 3. Valid chrome-extension origin + valid token -> 200
        ext_origin = "chrome-extension://" + ("a" * 32)
        code, res = self.http_call("/api/ping", "GET", token=self.token, origin=ext_origin)
        self.assertEqual(code, 200)
        self.assertTrue(res["ok"])
        self.assertTrue(res["result"]["full_system_access"])
        self.assertEqual(res["result"]["transport"], "localhost_http")

        # 4. Write & read outside workspace (full system access)
        outside_file = self.tmp_path / "outside.txt"
        code, res = self.http_call(
            "/api/tool",
            "POST",
            body={"id": "w1", "tool": "write_file", "args": {"path": str(outside_file), "content": "http-ok"}},
            token=self.token,
            origin=ext_origin,
        )
        self.assertEqual(code, 200)
        self.assertTrue(res["ok"])
        self.assertEqual(outside_file.read_text(encoding="utf-8"), "http-ok")

        # 5. In-process persistent terminal session over HTTP
        code, s_res = self.http_call(
            "/api/tool",
            "POST",
            body={"id": "ts", "tool": "terminal_start", "args": {"cwd": ".", "wait_ms": 250}},
            token=self.token,
            origin=ext_origin,
        )
        self.assertEqual(code, 200)
        self.assertTrue(s_res["ok"])
        sid = s_res["result"]["session_id"]

        _, w1 = self.http_call(
            "/api/tool",
            "POST",
            body={"id": "tw1", "tool": "terminal_write", "args": {"session_id": sid, "input": "export HTTP_VAR=9090", "wait_ms": 250}},
            token=self.token,
            origin=ext_origin,
        )
        self.assertTrue(w1["ok"])

        _, w2 = self.http_call(
            "/api/tool",
            "POST",
            body={"id": "tw2", "tool": "terminal_write", "args": {"session_id": sid, "input": "echo OUT=$HTTP_VAR", "wait_ms": 300}},
            token=self.token,
            origin=ext_origin,
        )
        self.assertTrue(w2["ok"])
        self.assertIn("OUT=9090", w2["result"]["output"])

        _, k_res = self.http_call(
            "/api/tool",
            "POST",
            body={"id": "tk", "tool": "terminal_kill", "args": {"session_id": sid}},
            token=self.token,
            origin=ext_origin,
        )
        self.assertTrue(k_res["ok"])
        self.assertTrue(k_res["result"]["killed"])

    def test_restricted_mode_blocks_escape(self) -> None:
        self.start_server(["--restricted"])
        outside = self.tmp_path / "secret.txt"
        outside.write_text("nope", encoding="utf-8")
        code, res = self.http_call(
            "/api/tool",
            "POST",
            body={"id": "r1", "tool": "read_file", "args": {"path": str(outside)}},
            token=self.token,
        )
        self.assertEqual(code, 200)
        self.assertFalse(res["ok"])
        self.assertIn("Guvenlik engeli", res["error"])


if __name__ == "__main__":
    unittest.main()
