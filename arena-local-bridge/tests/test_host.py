#!/usr/bin/env python3
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
HOST_PY = ROOT_DIR / "native-host" / "host.py"
INSTALL_PY = ROOT_DIR / "install" / "install.py"


def encode_native_msg(obj: dict) -> bytes:
    payload = json.dumps(obj).encode("utf-8")
    return struct.pack("<I", len(payload)) + payload


def decode_native_stream(raw: bytes) -> list[dict]:
    msgs = []
    idx = 0
    while idx < len(raw):
        (length,) = struct.unpack("<I", raw[idx : idx + 4])
        idx += 4
        payload = raw[idx : idx + length]
        idx += length
        msgs.append(json.loads(payload.decode("utf-8")))
    return msgs


class NativeHostTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)
        self.workspace = self.tmp_path / "workspace"
        self.workspace.mkdir()
        self.data_dir = self.tmp_path / "data"
        self.data_dir.mkdir()
        self.config_path = self.data_dir / "config.json"
        self.write_config(
            {
                "workspace_root": str(self.workspace),
                "allowed_tools": ["ping", "list_dir", "read_file", "write_file", "run_command"],
                "default_timeout_sec": 5,
                "max_output_bytes": 1024,
                "max_read_bytes": 4096,
                "lock_workspace": True,
            }
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_config(self, cfg: dict) -> None:
        self.config_path.write_text(json.dumps(cfg), encoding="utf-8")

    def call_host(self, *requests: dict) -> list[dict]:
        stdin_bytes = b"".join(encode_native_msg(r) for r in requests)
        env = os.environ.copy()
        env["ARENA_BRIDGE_CONFIG"] = str(self.config_path)
        env["ARENA_BRIDGE_DATA_DIR"] = str(self.data_dir)
        proc = subprocess.run(
            [sys.executable, str(HOST_PY)],
            input=stdin_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=20,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, msg=f"Host stderr: {proc.stderr.decode('utf-8', 'replace')}")
        return decode_native_stream(proc.stdout)

    def test_ping_and_file_roundtrip(self) -> None:
        res = self.call_host(
            {"id": "1", "tool": "ping", "args": {}},
            {
                "id": "2",
                "tool": "write_file",
                "args": {"path": "sub/hello.txt", "content": "line1\nline2\nline3\n"},
            },
            {"id": "3", "tool": "read_file", "args": {"path": "sub/hello.txt", "offset": 2, "limit": 1}},
            {"id": "4", "tool": "list_dir", "args": {"path": "."}},
        )
        self.assertEqual(len(res), 4)
        self.assertTrue(res[0]["ok"])
        self.assertTrue(res[0]["result"]["workspace_exists"])

        self.assertTrue(res[1]["ok"])
        self.assertEqual(res[1]["result"]["path"], "sub/hello.txt")

        self.assertTrue(res[2]["ok"])
        self.assertEqual(res[2]["result"]["content"], "line2\n")
        self.assertEqual(res[2]["result"]["total_lines"], 3)

        self.assertTrue(res[3]["ok"])
        names = [e["name"] for e in res[3]["result"]["entries"]]
        self.assertIn("sub", names)

    def test_run_command_and_truncation(self) -> None:
        res = self.call_host(
            {
                "id": "cmd1",
                "tool": "run_command",
                "args": {"command": f'"{sys.executable}" -c "print(\'A\' * 4000)"'},
            }
        )
        self.assertTrue(res[0]["ok"])
        r = res[0]["result"]
        self.assertEqual(r["exit_code"], 0)
        self.assertTrue(r["truncated"])
        self.assertIn("truncated", r["stdout"])

    def test_timeout_kills_process(self) -> None:
        res = self.call_host(
            {
                "id": "cmd_to",
                "tool": "run_command",
                "args": {"command": f'"{sys.executable}" -c "import time; time.sleep(10)"', "timeout": 1},
            }
        )
        self.assertTrue(res[0]["ok"])
        r = res[0]["result"]
        self.assertTrue(r["timed_out"])
        self.assertEqual(r["exit_code"], -1)

    def test_workspace_jail_blocks_traversal_and_symlink(self) -> None:
        outside_file = self.tmp_path / "secret.txt"
        outside_file.write_text("top-secret", encoding="utf-8")

        symlink_path = self.workspace / "escape_link.txt"
        try:
            symlink_path.symlink_to(outside_file)
            has_symlink = True
        except OSError:
            has_symlink = False

        reqs = [
            {"id": "t1", "tool": "read_file", "args": {"path": "../secret.txt"}},
            {"id": "t2", "tool": "read_file", "args": {"path": str(outside_file)}},
            {"id": "t3", "tool": "write_file", "args": {"path": "../evil.txt", "content": "x"}},
            {"id": "t4", "tool": "run_command", "args": {"command": "pwd", "cwd": ".."}},
        ]
        if has_symlink:
            reqs.append({"id": "t5", "tool": "read_file", "args": {"path": "escape_link.txt"}})

        res = self.call_host(*reqs)
        for item in res:
            self.assertFalse(item["ok"], msg=f"Expected failure for {item}")
            self.assertIn("Guvenlik engeli", item["error"])

    def test_disabled_tool_rejected(self) -> None:
        self.write_config(
            {
                "workspace_root": str(self.workspace),
                "allowed_tools": ["ping", "list_dir"],
            }
        )
        res = self.call_host({"id": "d1", "tool": "run_command", "args": {"command": "echo hi"}})
        self.assertFalse(res[0]["ok"])
        self.assertIn("devre disi", res[0]["error"])

    def test_installer_writes_manifest_and_config(self) -> None:
        if os.name == "nt":
            self.skipTest("Unix manifest dir test")
        native_dir = self.tmp_path / "native_hosts"
        data_dir = self.tmp_path / "inst_data"
        ext_id = "a" * 32
        proc = subprocess.run(
            [
                sys.executable,
                str(INSTALL_PY),
                "--extension-id",
                ext_id,
                "--workspace",
                str(self.workspace),
                "--native-dir",
                str(native_dir),
                "--data-dir",
                str(data_dir),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        manifest_file = native_dir / "com.arena.local_bridge.json"
        self.assertTrue(manifest_file.is_file())
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        self.assertEqual(manifest["allowed_origins"], [f"chrome-extension://{ext_id}/"])
        self.assertTrue((data_dir / "config.json").is_file())


if __name__ == "__main__":
    unittest.main()
