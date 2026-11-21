#!/usr/bin/env python3
import json
import os
import socket
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
                "full_system_access": False,
                "allowed_tools": [
                    "ping",
                    "list_dir",
                    "read_file",
                    "write_file",
                    "edit_file",
                    "delete_path",
                    "run_command",
                    "terminal_start",
                    "terminal_write",
                    "terminal_read",
                    "terminal_list",
                    "terminal_kill",
                    "open_terminal_window",
                ],
                "default_timeout_sec": 5,
                "max_output_bytes": 4096,
                "max_read_bytes": 4096,
                "lock_workspace": True,
            }
        )

    def tearDown(self) -> None:
        daemon_json = self.data_dir / "daemon.json"
        if daemon_json.is_file():
            try:
                info = json.loads(daemon_json.read_text(encoding="utf-8"))
                payload = (json.dumps({"token": info["token"], "action": "shutdown", "args": {}}) + "\n").encode("utf-8")
                with socket.create_connection(("127.0.0.1", int(info["port"])), timeout=2) as sock:
                    sock.sendall(payload)
                    sock.recv(1024)
            except Exception:
                pass
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
            timeout=25,
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
            {
                "id": "3",
                "tool": "edit_file",
                "args": {"path": "sub/hello.txt", "old_text": "line2", "new_text": "line2_edited"},
            },
            {"id": "4", "tool": "read_file", "args": {"path": "sub/hello.txt", "offset": 2, "limit": 1}},
            {"id": "5", "tool": "list_dir", "args": {"path": "."}},
            {"id": "6", "tool": "delete_path", "args": {"path": "sub/hello.txt"}},
        )
        self.assertEqual(len(res), 6)
        self.assertTrue(res[0]["ok"])
        self.assertTrue(res[0]["result"]["workspace_exists"])
        self.assertFalse(res[0]["result"]["full_system_access"])

        self.assertTrue(res[1]["ok"])
        self.assertEqual(res[1]["result"]["path"], "sub/hello.txt")

        self.assertTrue(res[2]["ok"])
        self.assertEqual(res[2]["result"]["replacements"], 1)

        self.assertTrue(res[3]["ok"])
        self.assertEqual(res[3]["result"]["content"], "line2_edited\n")
        self.assertEqual(res[3]["result"]["total_lines"], 3)

        self.assertTrue(res[4]["ok"])
        names = [e["name"] for e in res[4]["result"]["entries"]]
        self.assertIn("sub", names)

        self.assertTrue(res[5]["ok"])
        self.assertTrue(res[5]["result"]["deleted"])

    def test_run_command_stdin_and_truncation(self) -> None:
        res = self.call_host(
            {
                "id": "cmd_stdin",
                "tool": "run_command",
                "args": {
                    "command": f'"{sys.executable}" -c "import sys; print(sys.stdin.read().upper())"',
                    "stdin": "merhaba arena",
                },
            },
            {
                "id": "cmd_trunc",
                "tool": "run_command",
                "args": {"command": f'"{sys.executable}" -c "print(\'A\' * 8000)"'},
            },
        )
        self.assertTrue(res[0]["ok"])
        self.assertIn("MERHABA ARENA", res[0]["result"]["stdout"])

        self.assertTrue(res[1]["ok"])
        r = res[1]["result"]
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

    def test_full_system_access_allows_paths_outside_workspace(self) -> None:
        outside_dir = self.tmp_path / "outside_pc"
        outside_dir.mkdir()
        outside_file = outside_dir / "note.txt"

        cfg = json.loads(self.config_path.read_text(encoding="utf-8"))
        cfg["full_system_access"] = True
        self.write_config(cfg)

        res = self.call_host(
            {"id": "p1", "tool": "ping", "args": {}},
            {"id": "w1", "tool": "write_file", "args": {"path": str(outside_file), "content": "global-ok"}},
            {"id": "r1", "tool": "read_file", "args": {"path": str(outside_file)}},
            {"id": "c1", "tool": "run_command", "args": {"command": "pwd", "cwd": str(outside_dir)}},
        )
        self.assertTrue(res[0]["result"]["full_system_access"])
        self.assertTrue(res[1]["ok"])
        self.assertEqual(res[2]["result"]["content"], "global-ok")
        self.assertTrue(res[3]["ok"])
        self.assertIn("outside_pc", res[3]["result"]["stdout"])

    def test_persistent_interactive_terminal_session(self) -> None:
        start_res = self.call_host(
            {"id": "ts1", "tool": "terminal_start", "args": {"cwd": ".", "wait_ms": 250}}
        )[0]
        self.assertTrue(start_res["ok"], msg=start_res)
        sid = start_res["result"]["session_id"]
        self.assertTrue(start_res["result"]["alive"])

        # State persists across separate host invocations!
        write1 = self.call_host(
            {
                "id": "tw1",
                "tool": "terminal_write",
                "args": {"session_id": sid, "input": "export ARENA_TEST_VAR=4242", "wait_ms": 250},
            }
        )[0]
        self.assertTrue(write1["ok"], msg=write1)

        write2 = self.call_host(
            {
                "id": "tw2",
                "tool": "terminal_write",
                "args": {"session_id": sid, "input": "echo VAL=$ARENA_TEST_VAR", "wait_ms": 300},
            }
        )[0]
        self.assertTrue(write2["ok"], msg=write2)
        self.assertIn("VAL=4242", write2["result"]["output"])

        listed = self.call_host({"id": "tl1", "tool": "terminal_list", "args": {}})[0]
        self.assertTrue(listed["ok"])
        self.assertTrue(any(s["session_id"] == sid and s["alive"] for s in listed["result"]["sessions"]))

        killed = self.call_host({"id": "tk1", "tool": "terminal_kill", "args": {"session_id": sid}})[0]
        self.assertTrue(killed["ok"])
        self.assertTrue(killed["result"]["killed"])

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

    def test_installer_writes_manifest_and_full_access_config(self) -> None:
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
                "--full-access",
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
        cfg = json.loads((data_dir / "config.json").read_text(encoding="utf-8"))
        self.assertTrue(cfg["full_system_access"])
        self.assertIn("terminal_write", cfg["allowed_tools"])


if __name__ == "__main__":
    unittest.main()
