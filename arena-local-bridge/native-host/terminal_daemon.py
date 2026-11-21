#!/usr/bin/env python3
"""
Arena.ai Local Bridge - Persistent Interactive Terminal Daemon
Maintains live PTY (Linux/macOS) or pipe (Windows) shell sessions across
stateless Chrome Native Messaging invocations.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

if os.name != "nt":
    import fcntl
    import pty
    import termios

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][AB012]|\r")
MAX_BUFFER_CHARS = 256 * 1024


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def default_shell() -> str:
    if os.name == "nt":
        return shutil.which("powershell.exe") or os.environ.get("COMSPEC", "cmd.exe")
    env_shell = os.environ.get("SHELL")
    if env_shell and os.path.exists(env_shell):
        return env_shell
    for cand in ("/bin/bash", "/bin/zsh", "/bin/sh"):
        if os.path.exists(cand):
            return cand
    return "/bin/sh"


class TerminalSession:
    def __init__(
        self,
        session_id: str,
        cwd: str,
        shell: Optional[str] = None,
        command: Optional[str] = None,
        rows: int = 24,
        cols: int = 120,
    ) -> None:
        self.session_id = session_id
        self.cwd = cwd
        self.shell = shell or default_shell()
        self.command = command
        self.created_at = time.time()
        self.lock = threading.Lock()
        self.buffer = ""
        self.total_chars = 0  # monotonic cursor across lifetime
        self.master_fd: Optional[int] = None
        self.proc: Optional[subprocess.Popen[bytes]] = None
        self._closed = False

        self._spawn(rows, cols)
        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()

    def _spawn(self, rows: int, cols: int) -> None:
        env = os.environ.copy()
        env.setdefault("TERM", "xterm-256color")

        if os.name != "nt":
            master_fd, slave_fd = pty.openpty()
            try:
                winsize = struct.pack("HHHH", max(10, rows), max(40, cols), 0, 0)
                fcntl.ioctl(master_fd, termios.TIOCSWINSZ, winsize)
            except Exception:
                pass

            argv = [self.shell]
            self.proc = subprocess.Popen(
                argv,
                cwd=self.cwd,
                env=env,
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                start_new_session=True,
                close_fds=True,
            )
            os.close(slave_fd)
            self.master_fd = master_fd
        else:
            self.proc = subprocess.Popen(
                [self.shell],
                cwd=self.cwd,
                env=env,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,  # type: ignore[attr-defined]
            )

        if self.command:
            self.write_raw((self.command.rstrip("\r\n") + "\n").encode("utf-8"))

    def _append_output(self, chunk_bytes: bytes) -> None:
        text = chunk_bytes.decode("utf-8", errors="replace")
        with self.lock:
            self.buffer += text
            self.total_chars += len(text)
            if len(self.buffer) > MAX_BUFFER_CHARS:
                self.buffer = self.buffer[-MAX_BUFFER_CHARS:]

    def _read_loop(self) -> None:
        if os.name != "nt" and self.master_fd is not None:
            while not self._closed:
                try:
                    data = os.read(self.master_fd, 4096)
                    if not data:
                        break
                    self._append_output(data)
                except OSError:
                    break
        elif self.proc and self.proc.stdout is not None:
            while not self._closed:
                try:
                    data = self.proc.stdout.read1(4096) if hasattr(self.proc.stdout, "read1") else self.proc.stdout.read(1)
                    if not data:
                        break
                    self._append_output(data)
                except Exception:
                    break

    def is_alive(self) -> bool:
        if not self.proc:
            return False
        return self.proc.poll() is None

    def exit_code(self) -> Optional[int]:
        if not self.proc:
            return None
        return self.proc.poll()

    def write_raw(self, data: bytes) -> None:
        if not self.is_alive():
            raise RuntimeError(f"Terminal oturumu sonlanmis (exit_code={self.exit_code()}).")
        if os.name != "nt" and self.master_fd is not None:
            os.write(self.master_fd, data)
        elif self.proc and self.proc.stdin is not None:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()

    def read_output(self, since_cursor: Optional[int] = None, raw: bool = False) -> Dict[str, Any]:
        with self.lock:
            end_cursor = self.total_chars
            start_cursor = max(0, end_cursor - len(self.buffer))
            if since_cursor is None:
                chunk = self.buffer
            else:
                req_cur = int(since_cursor)
                if req_cur <= start_cursor:
                    chunk = self.buffer
                elif req_cur >= end_cursor:
                    chunk = ""
                else:
                    offset = req_cur - start_cursor
                    chunk = self.buffer[offset:]

        output = chunk if raw else strip_ansi(chunk)
        return {
            "session_id": self.session_id,
            "pid": self.proc.pid if self.proc else None,
            "cwd": self.cwd,
            "shell": self.shell,
            "alive": self.is_alive(),
            "exit_code": self.exit_code(),
            "output": output,
            "cursor": end_cursor,
        }

    def close(self) -> None:
        self._closed = True
        if self.proc and self.is_alive():
            try:
                if os.name == "nt":
                    subprocess.run(
                        ["taskkill", "/F", "/T", "/PID", str(self.proc.pid)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                else:
                    os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except Exception:
                try:
                    self.proc.kill()
                except Exception:
                    pass
            try:
                self.proc.wait(timeout=2)
            except Exception:
                pass
        if self.master_fd is not None:
            try:
                os.close(self.master_fd)
            except Exception:
                pass
            self.master_fd = None


class SessionManager:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.sessions: Dict[str, TerminalSession] = {}

    def start(self, args: Dict[str, Any]) -> Dict[str, Any]:
        cwd = str(args.get("cwd") or Path.home())
        if not os.path.isdir(cwd):
            raise NotADirectoryError(f"Klasor bulunamadi: {cwd}")
        shell = args.get("shell")
        command = args.get("command")
        rows = int(args.get("rows", 24))
        cols = int(args.get("cols", 120))
        wait_ms = max(0, min(int(args.get("wait_ms", 450)), 5000))
        raw = bool(args.get("raw", False))

        sid = f"term_{uuid.uuid4().hex[:8]}"
        session = TerminalSession(sid, cwd=cwd, shell=shell, command=command, rows=rows, cols=cols)
        with self.lock:
            self.sessions[sid] = session

        if wait_ms > 0:
            time.sleep(wait_ms / 1000.0)
        return session.read_output(since_cursor=0, raw=raw)

    def write(self, args: Dict[str, Any]) -> Dict[str, Any]:
        sid = args.get("session_id")
        if not sid or not isinstance(sid, str):
            raise ValueError("terminal_write icin 'session_id' gerekli.")
        session = self._get(sid)

        with session.lock:
            cursor_before = session.total_chars

        ctrl = args.get("ctrl")
        text = args.get("input")
        enter = bool(args.get("enter", True))
        wait_ms = max(0, min(int(args.get("wait_ms", 500)), 10000))
        raw = bool(args.get("raw", False))

        if ctrl:
            c = str(ctrl).lower().strip()
            ctrl_map = {"c": b"\x03", "d": b"\x04", "z": b"\x1a"}
            if c not in ctrl_map:
                raise ValueError(f"Desteklenmeyen ctrl tusu: {ctrl}")
            session.write_raw(ctrl_map[c])
        elif text is not None:
            if not isinstance(text, str):
                raise ValueError("'input' string olmalidir.")
            payload = text
            if enter and not payload.endswith(("\n", "\r")):
                payload += "\r\n" if os.name == "nt" else "\n"
            session.write_raw(payload.encode("utf-8"))
        else:
            raise ValueError("terminal_write icin 'input' veya 'ctrl' gerekli.")

        if wait_ms > 0:
            time.sleep(wait_ms / 1000.0)
        return session.read_output(since_cursor=cursor_before, raw=raw)

    def read(self, args: Dict[str, Any]) -> Dict[str, Any]:
        sid = args.get("session_id")
        if not sid or not isinstance(sid, str):
            raise ValueError("terminal_read icin 'session_id' gerekli.")
        session = self._get(sid)
        wait_ms = max(0, min(int(args.get("wait_ms", 0)), 10000))
        if wait_ms > 0:
            time.sleep(wait_ms / 1000.0)
        cursor = args.get("cursor")
        raw = bool(args.get("raw", False))
        return session.read_output(since_cursor=cursor, raw=raw)

    def list_sessions(self) -> Dict[str, Any]:
        with self.lock:
            items: List[Dict[str, Any]] = []
            for sid, s in self.sessions.items():
                items.append(
                    {
                        "session_id": sid,
                        "pid": s.proc.pid if s.proc else None,
                        "cwd": s.cwd,
                        "shell": s.shell,
                        "alive": s.is_alive(),
                        "exit_code": s.exit_code(),
                        "created_at": s.created_at,
                    }
                )
        return {"sessions": items}

    def kill(self, args: Dict[str, Any]) -> Dict[str, Any]:
        sid = args.get("session_id")
        if not sid or not isinstance(sid, str):
            raise ValueError("terminal_kill icin 'session_id' gerekli.")
        with self.lock:
            session = self.sessions.pop(sid, None)
        if not session:
            raise KeyError(f"Terminal oturumu bulunamadi: {sid}")
        session.close()
        return {"session_id": sid, "killed": True}

    def close_all(self) -> None:
        with self.lock:
            all_sessions = list(self.sessions.values())
            self.sessions.clear()
        for s in all_sessions:
            s.close()

    def _get(self, sid: str) -> TerminalSession:
        with self.lock:
            s = self.sessions.get(sid)
        if not s:
            raise KeyError(f"Terminal oturumu bulunamadi: {sid}")
        return s


class DaemonTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address, RequestHandlerClass, token: str, manager: SessionManager):
        self.token = token
        self.manager = manager
        self.shutdown_event = threading.Event()
        super().__init__(server_address, RequestHandlerClass)


class DaemonHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        try:
            line = self.rfile.readline(1024 * 1024)
            if not line:
                return
            req = json.loads(line.decode("utf-8"))
            if not isinstance(req, dict):
                return
            req_token = str(req.get("token") or "")
            srv: DaemonTCPServer = self.server  # type: ignore[assignment]
            if not secrets.compare_digest(req_token, srv.token):
                self._send({"ok": False, "error": "Yetkisiz daemon erisimi."})
                return

            action = req.get("action")
            args = req.get("args") or {}

            if action == "ping":
                self._send({"ok": True, "result": {"pid": os.getpid()}})
            elif action == "start":
                self._send({"ok": True, "result": srv.manager.start(args)})
            elif action == "write":
                self._send({"ok": True, "result": srv.manager.write(args)})
            elif action == "read":
                self._send({"ok": True, "result": srv.manager.read(args)})
            elif action == "list":
                self._send({"ok": True, "result": srv.manager.list_sessions()})
            elif action == "kill":
                self._send({"ok": True, "result": srv.manager.kill(args)})
            elif action == "shutdown":
                self._send({"ok": True, "result": {"shutting_down": True}})
                srv.shutdown_event.set()
                threading.Thread(target=srv.shutdown, daemon=True).start()
            else:
                self._send({"ok": False, "error": f"Bilinmeyen daemon aksiyonu: {action}"})
        except Exception as exc:
            try:
                self._send({"ok": False, "error": str(exc)})
            except Exception:
                pass

    def _send(self, obj: Dict[str, Any]) -> None:
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
        self.wfile.write(data)
        self.wfile.flush()


def write_daemon_info(data_dir: Path, port: int, token: str) -> Path:
    data_dir.mkdir(parents=True, exist_ok=True)
    info_path = data_dir / "daemon.json"
    tmp_path = data_dir / f"daemon.{os.getpid()}.tmp"
    payload = {
        "pid": os.getpid(),
        "port": port,
        "token": token,
        "started_at": time.time(),
    }
    tmp_path.write_text(json.dumps(payload), encoding="utf-8")
    if os.name != "nt":
        try:
            os.chmod(tmp_path, 0o600)
        except Exception:
            pass
    os.replace(tmp_path, info_path)
    return info_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Arena Local Bridge Terminal Daemon")
    parser.add_argument("--data-dir", required=True)
    args = parser.parse_args()

    data_dir = Path(args.data_dir).expanduser().resolve()
    token = secrets.token_hex(32)
    manager = SessionManager()
    server = DaemonTCPServer(("127.0.0.1", 0), DaemonHandler, token=token, manager=manager)
    port = server.server_address[1]
    info_path = write_daemon_info(data_dir, port, token)

    def handle_sig(_signum, _frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(sig, handle_sig)
        except Exception:
            pass

    try:
        server.serve_forever()
    finally:
        manager.close_all()
        server.server_close()
        try:
            if info_path.exists():
                cur = json.loads(info_path.read_text(encoding="utf-8"))
                if cur.get("pid") == os.getpid():
                    info_path.unlink()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
