#!/usr/bin/env python3
"""
Arena.ai Local Bridge - Chrome Native Messaging Host
Pure Python 3 stdlib implementation supporting both workspace-jailed mode
and full-system access mode, plus persistent interactive terminals.
"""

from __future__ import annotations

import json
import os
import platform
import shutil
import signal
import socket
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HOST_VERSION = "1.1.0"
DEFAULT_ALLOWED_TOOLS = [
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
]
MAX_TIMEOUT_SEC = 300
DEFAULT_TIMEOUT_SEC = 30
DEFAULT_MAX_OUTPUT_BYTES = 32768
DEFAULT_MAX_READ_BYTES = 131072
MAX_NATIVE_MSG_BYTES = 1024 * 1024  # Chrome Native Messaging host->browser limit is 1 MB


def get_data_dir() -> Path:
    env_dir = os.environ.get("ARENA_BRIDGE_DATA_DIR")
    if env_dir:
        return Path(env_dir).expanduser().resolve()
    return Path.home() / ".arena-local-bridge"


def get_config_path() -> Path:
    env_cfg = os.environ.get("ARENA_BRIDGE_CONFIG")
    if env_cfg:
        return Path(env_cfg).expanduser().resolve()
    return get_data_dir() / "config.json"


def load_config() -> Dict[str, Any]:
    cfg_path = get_config_path()
    defaults: Dict[str, Any] = {
        "workspace_root": "",
        "full_system_access": False,
        "allowed_tools": list(DEFAULT_ALLOWED_TOOLS),
        "default_timeout_sec": DEFAULT_TIMEOUT_SEC,
        "max_output_bytes": DEFAULT_MAX_OUTPUT_BYTES,
        "max_read_bytes": DEFAULT_MAX_READ_BYTES,
        "lock_workspace": True,
    }
    if cfg_path.is_file():
        try:
            with cfg_path.open("r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                defaults.update(loaded)
        except Exception as exc:
            defaults["_config_error"] = f"Failed to parse config.json: {exc}"
    return defaults


def audit_log(entry: Dict[str, Any]) -> None:
    try:
        log_dir = get_data_dir()
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "audit.log"
        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            **entry,
        }
        with log_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass


def setup_binary_stdio() -> None:
    if os.name == "nt":
        import msvcrt  # type: ignore

        msvcrt.setmode(sys.stdin.fileno(), os.O_BINARY)
        msvcrt.setmode(sys.stdout.fileno(), os.O_BINARY)


def read_native_message() -> Optional[Dict[str, Any]]:
    raw_len = sys.stdin.buffer.read(4)
    if not raw_len:
        return None
    if len(raw_len) < 4:
        raise EOFError("Incomplete native message length header")
    (msg_len,) = struct.unpack("<I", raw_len)
    if msg_len == 0:
        return {}
    if msg_len > 16 * 1024 * 1024:
        raise ValueError(f"Incoming message too large: {msg_len} bytes")
    payload = sys.stdin.buffer.read(msg_len)
    if len(payload) < msg_len:
        raise EOFError("Incomplete native message payload")
    data = json.loads(payload.decode("utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Native message JSON must be an object")
    return data


def write_native_message(message: Dict[str, Any]) -> None:
    encoded = json.dumps(message, ensure_ascii=False).encode("utf-8")
    if len(encoded) > MAX_NATIVE_MSG_BYTES - 1024:
        encoded = json.dumps(
            {
                "id": message.get("id"),
                "ok": False,
                "error": f"Response exceeded Chrome 1MB Native Messaging limit ({len(encoded)} bytes)",
            },
            ensure_ascii=False,
        ).encode("utf-8")
    header = struct.pack("<I", len(encoded))
    sys.stdout.buffer.write(header)
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def is_full_access(config: Dict[str, Any]) -> bool:
    return bool(config.get("full_system_access", False))


def get_workspace_root(config: Dict[str, Any]) -> str:
    raw = str(config.get("workspace_root") or "").strip()
    if not raw:
        if is_full_access(config):
            return os.path.realpath(str(Path.home()))
        raise PermissionError(
            "workspace_root ayarlanmamis. Lutfen install.py calistirin veya ~/.arena-local-bridge/config.json dosyasini duzenleyin."
        )
    resolved = os.path.realpath(os.path.expanduser(raw))
    if not os.path.isdir(resolved):
        raise FileNotFoundError(f"workspace_root klasoru bulunamadi: {resolved}")
    return resolved


def resolve_safe_path(
    workspace_root: str,
    target_path: Optional[str],
    full_access: bool = False,
) -> Tuple[str, str]:
    """
    Resolve target_path.
    In restricted mode (full_access=False), enforces strict workspace_root jail.
    In full_access mode (full_access=True), allows any path on the system.
    Returns (absolute_real_path, display_path).
    """
    if target_path is None or str(target_path).strip() == "":
        candidate = workspace_root
    else:
        raw = str(target_path)
        if "\x00" in raw:
            raise ValueError("Path contains null byte")
        expanded = os.path.expanduser(raw)
        if os.path.isabs(expanded):
            candidate = expanded
        else:
            candidate = os.path.join(workspace_root, expanded)

    ws_real = os.path.realpath(workspace_root)
    target_real = os.path.realpath(candidate)

    if full_access:
        try:
            common = os.path.commonpath([ws_real, target_real])
        except ValueError:
            common = ""
        if common == ws_real:
            rel = os.path.relpath(target_real, ws_real)
            return target_real, ("." if rel == "." else rel.replace(os.sep, "/"))
        return target_real, target_real

    try:
        common = os.path.commonpath([ws_real, target_real])
    except ValueError as exc:
        raise PermissionError(f"Path outside workspace_root: {target_path}") from exc

    if common != ws_real:
        raise PermissionError(
            f"Guvenlik engeli: '{target_path}' yolu workspace_root ({ws_real}) disina cikiyor."
        )

    rel = os.path.relpath(target_real, ws_real)
    rel_posix = "." if rel == "." else rel.replace(os.sep, "/")
    return target_real, rel_posix


def truncate_text(text: str, max_bytes: int) -> Tuple[str, bool]:
    raw = text.encode("utf-8", errors="replace")
    if len(raw) <= max_bytes:
        return text, False
    head_bytes = max_bytes // 2
    tail_bytes = max_bytes - head_bytes
    head = raw[:head_bytes].decode("utf-8", errors="ignore")
    tail = raw[-tail_bytes:].decode("utf-8", errors="ignore")
    omitted = len(raw) - max_bytes
    return f"{head}\n\n... [{omitted} bytes truncated] ...\n\n{tail}", True


def handle_ping(config: Dict[str, Any]) -> Dict[str, Any]:
    full = is_full_access(config)
    raw_ws = str(config.get("workspace_root") or "").strip()
    if not raw_ws and full:
        raw_ws = str(Path.home())
    resolved_ws = os.path.realpath(os.path.expanduser(raw_ws)) if raw_ws else ""
    return {
        "tool": "ping",
        "host_version": HOST_VERSION,
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "workspace_root": resolved_ws,
        "workspace_exists": bool(resolved_ws and os.path.isdir(resolved_ws)),
        "full_system_access": full,
        "allowed_tools": config.get("allowed_tools", DEFAULT_ALLOWED_TOOLS),
        "default_timeout_sec": config.get("default_timeout_sec", DEFAULT_TIMEOUT_SEC),
        "lock_workspace": bool(config.get("lock_workspace", True)),
        "config_path": str(get_config_path()),
        "config_error": config.get("_config_error"),
    }


def handle_list_dir(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    rel_arg = args.get("path", ".")
    target_real, display_path = resolve_safe_path(ws, rel_arg, full_access=full)
    if not os.path.isdir(target_real):
        raise NotADirectoryError(f"Klasor degil: {display_path}")

    include_hidden = bool(args.get("include_hidden", False))
    max_entries = int(args.get("max_entries", 200))
    max_entries = max(1, min(max_entries, 1000))

    entries: List[Dict[str, Any]] = []
    with os.scandir(target_real) as it:
        for entry in it:
            if not include_hidden and entry.name.startswith("."):
                continue
            try:
                is_dir = entry.is_dir(follow_symlinks=False)
                is_link = entry.is_symlink()
                size = 0 if is_dir else entry.stat(follow_symlinks=False).st_size
                etype = "symlink" if is_link else ("dir" if is_dir else "file")
            except OSError:
                etype = "unknown"
                size = 0
            entries.append({"name": entry.name, "type": etype, "size": size})

    entries.sort(key=lambda e: (0 if e["type"] == "dir" else 1, e["name"].lower()))
    truncated = len(entries) > max_entries
    return {
        "tool": "list_dir",
        "path": display_path,
        "total_entries": len(entries),
        "truncated": truncated,
        "entries": entries[:max_entries],
    }


def handle_read_file(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    path_arg = args.get("path")
    if not path_arg or not isinstance(path_arg, str):
        raise ValueError("read_file icin 'path' parametresi gerekli.")

    target_real, display_path = resolve_safe_path(ws, path_arg, full_access=full)
    if not os.path.isfile(target_real):
        raise FileNotFoundError(f"Dosya bulunamadi: {display_path}")

    max_read_bytes = int(config.get("max_read_bytes", DEFAULT_MAX_READ_BYTES))
    file_size = os.path.getsize(target_real)

    with open(target_real, "rb") as f:
        sample = f.read(4096)
        if b"\x00" in sample:
            raise ValueError(f"Ikili (binary) dosya metin olarak okunamaz: {display_path}")

    with open(target_real, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

    total_lines = len(lines)
    offset = max(1, int(args.get("offset", 1)))
    limit = args.get("limit")
    if limit is not None:
        limit_int = max(1, min(int(limit), 2000))
        selected = lines[offset - 1 : offset - 1 + limit_int]
    else:
        selected = lines[offset - 1 :]

    joined = "".join(selected)
    content, truncated_bytes = truncate_text(joined, max_read_bytes)
    truncated = truncated_bytes or (offset > 1) or (offset - 1 + len(selected) < total_lines)

    return {
        "tool": "read_file",
        "path": display_path,
        "file_size": file_size,
        "total_lines": total_lines,
        "offset": offset,
        "lines_returned": len(selected),
        "truncated": truncated,
        "content": content,
    }


def handle_write_file(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    path_arg = args.get("path")
    content = args.get("content")
    if not path_arg or not isinstance(path_arg, str):
        raise ValueError("write_file icin 'path' parametresi gerekli.")
    if content is None or not isinstance(content, str):
        raise ValueError("write_file icin 'content' (string) parametresi gerekli.")

    target_real, display_path = resolve_safe_path(ws, path_arg, full_access=full)
    create_dirs = bool(args.get("create_dirs", True))
    parent = os.path.dirname(target_real)
    if create_dirs:
        os.makedirs(parent, exist_ok=True)
    elif not os.path.isdir(parent):
        raise FileNotFoundError(f"Ust klasor bulunamadi: {os.path.dirname(display_path)}")

    encoded = content.encode("utf-8")
    with open(target_real, "wb") as f:
        f.write(encoded)

    return {
        "tool": "write_file",
        "path": display_path,
        "bytes_written": len(encoded),
    }


def handle_edit_file(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    path_arg = args.get("path")
    old_text = args.get("old_text")
    new_text = args.get("new_text")
    if not path_arg or not isinstance(path_arg, str):
        raise ValueError("edit_file icin 'path' parametresi gerekli.")
    if not old_text or not isinstance(old_text, str):
        raise ValueError("edit_file icin bos olmayan 'old_text' parametresi gerekli.")
    if new_text is None or not isinstance(new_text, str):
        raise ValueError("edit_file icin 'new_text' (string) parametresi gerekli.")

    target_real, display_path = resolve_safe_path(ws, path_arg, full_access=full)
    if not os.path.isfile(target_real):
        raise FileNotFoundError(f"Dosya bulunamadi: {display_path}")

    with open(target_real, "r", encoding="utf-8") as f:
        original = f.read()

    count = original.count(old_text)
    if count == 0:
        raise ValueError(f"'old_text' dosya icinde bulunamadi: {display_path}")

    replace_all = bool(args.get("replace_all", False))
    if count > 1 and not replace_all:
        raise ValueError(
            f"'old_text' dosyada {count} kez geciyor. Daha ozgul bir metin verin veya replace_all=true kullanin."
        )

    updated = original.replace(old_text, new_text) if replace_all else original.replace(old_text, new_text, 1)
    with open(target_real, "w", encoding="utf-8") as f:
        f.write(updated)

    return {
        "tool": "edit_file",
        "path": display_path,
        "replacements": count if replace_all else 1,
    }


def handle_delete_path(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    path_arg = args.get("path")
    if not path_arg or not isinstance(path_arg, str):
        raise ValueError("delete_path icin 'path' parametresi gerekli.")

    target_real, display_path = resolve_safe_path(ws, path_arg, full_access=full)
    if target_real in ("/", os.path.abspath(os.sep), os.path.realpath(str(Path.home()))):
        raise PermissionError(f"Kritik kok dizin silinemez: {target_real}")
    if not os.path.lexists(target_real):
        raise FileNotFoundError(f"Yol bulunamadi: {display_path}")

    recursive = bool(args.get("recursive", False))
    if os.path.isdir(target_real) and not os.path.islink(target_real):
        if recursive:
            shutil.rmtree(target_real)
        else:
            os.rmdir(target_real)
        deleted_type = "dir"
    else:
        os.unlink(target_real)
        deleted_type = "file"

    return {
        "tool": "delete_path",
        "path": display_path,
        "type": deleted_type,
        "deleted": True,
    }


def _kill_process_tree(proc: subprocess.Popen[bytes]) -> None:
    try:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        else:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass


def handle_run_command(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    command = args.get("command")
    if not command or not isinstance(command, str) or not command.strip():
        raise ValueError("run_command icin bos olmayan 'command' parametresi gerekli.")

    cwd_arg = args.get("cwd", ".")
    cwd_real, cwd_display = resolve_safe_path(ws, cwd_arg, full_access=full)
    if not os.path.isdir(cwd_real):
        raise NotADirectoryError(f"Calisma klasoru bulunamadi: {cwd_display}")

    stdin_str = args.get("stdin")
    stdin_bytes = stdin_str.encode("utf-8") if isinstance(stdin_str, str) else None

    default_t = int(config.get("default_timeout_sec", DEFAULT_TIMEOUT_SEC))
    req_t = args.get("timeout", default_t)
    timeout_sec = max(1, min(int(req_t), MAX_TIMEOUT_SEC))
    max_output = int(config.get("max_output_bytes", DEFAULT_MAX_OUTPUT_BYTES))

    popen_kwargs: Dict[str, Any] = {
        "shell": True,
        "cwd": cwd_real,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
    }
    if stdin_bytes is not None:
        popen_kwargs["stdin"] = subprocess.PIPE
    if os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
    else:
        popen_kwargs["start_new_session"] = True

    started = time.monotonic()
    proc = subprocess.Popen(command, **popen_kwargs)
    timed_out = False
    try:
        stdout_b, stderr_b = proc.communicate(input=stdin_bytes, timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        timed_out = True
        _kill_process_tree(proc)
        try:
            stdout_b, stderr_b = proc.communicate(timeout=5)
        except Exception:
            stdout_b, stderr_b = b"", b""

    duration_ms = int((time.monotonic() - started) * 1000)
    stdout_text = (stdout_b or b"").decode("utf-8", errors="replace")
    stderr_text = (stderr_b or b"").decode("utf-8", errors="replace")

    stdout_text, trunc_out = truncate_text(stdout_text, max_output)
    stderr_text, trunc_err = truncate_text(stderr_text, max_output // 2)

    return {
        "tool": "run_command",
        "command": command,
        "cwd": cwd_display,
        "exit_code": -1 if timed_out else proc.returncode,
        "timed_out": timed_out,
        "timeout_sec": timeout_sec,
        "duration_ms": duration_ms,
        "stdout": stdout_text,
        "stderr": stderr_text,
        "truncated": trunc_out or trunc_err,
    }


def _query_daemon(info: Dict[str, Any], action: str, args: Dict[str, Any], timeout: float = 15.0) -> Dict[str, Any]:
    port = int(info["port"])
    token = str(info["token"])
    payload = (json.dumps({"token": token, "action": action, "args": args}, ensure_ascii=False) + "\n").encode("utf-8")
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.sendall(payload)
        chunks: List[bytes] = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
            if b"\n" in data:
                break
    raw = b"".join(chunks).split(b"\n", 1)[0]
    return json.loads(raw.decode("utf-8"))


def ensure_terminal_daemon() -> Dict[str, Any]:
    data_dir = get_data_dir()
    data_dir.mkdir(parents=True, exist_ok=True)
    info_path = data_dir / "daemon.json"

    if info_path.is_file():
        try:
            info = json.loads(info_path.read_text(encoding="utf-8"))
            ping_res = _query_daemon(info, "ping", {}, timeout=1.0)
            if ping_res.get("ok"):
                return info
        except Exception:
            pass

    daemon_py = Path(__file__).resolve().parent / "terminal_daemon.py"
    if not daemon_py.is_file():
        raise FileNotFoundError(f"terminal_daemon.py bulunamadi: {daemon_py}")

    popen_kwargs: Dict[str, Any] = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
        "close_fds": True,
    }
    if os.name == "nt":
        popen_kwargs["creationflags"] = (
            subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
        )
    else:
        popen_kwargs["start_new_session"] = True

    subprocess.Popen([sys.executable, str(daemon_py), "--data-dir", str(data_dir)], **popen_kwargs)

    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        if info_path.is_file():
            try:
                info = json.loads(info_path.read_text(encoding="utf-8"))
                ping_res = _query_daemon(info, "ping", {}, timeout=1.0)
                if ping_res.get("ok"):
                    return info
            except Exception:
                pass
        time.sleep(0.1)

    raise RuntimeError("Terminal daemon baslatilamadi.")


def handle_terminal_tool(tool: str, args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    action_map = {
        "terminal_start": "start",
        "terminal_write": "write",
        "terminal_read": "read",
        "terminal_list": "list",
        "terminal_kill": "kill",
    }
    action = action_map[tool]

    daemon_args = dict(args)
    if tool == "terminal_start":
        ws = get_workspace_root(config)
        full = is_full_access(config)
        cwd_real, _ = resolve_safe_path(ws, daemon_args.get("cwd", "."), full_access=full)
        daemon_args["cwd"] = cwd_real

    info = ensure_terminal_daemon()
    resp = _query_daemon(info, action, daemon_args, timeout=20.0)
    if not resp.get("ok"):
        raise RuntimeError(resp.get("error") or "Terminal daemon hatasi")
    result = resp.get("result") or {}
    result["tool"] = tool

    if isinstance(result.get("output"), str):
        max_out = int(config.get("max_output_bytes", DEFAULT_MAX_OUTPUT_BYTES))
        trimmed, trunc = truncate_text(result["output"], max_out)
        result["output"] = trimmed
        if trunc:
            result["truncated"] = True

    return result


def handle_open_terminal_window(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    full = is_full_access(config)
    cwd_real, cwd_display = resolve_safe_path(ws, args.get("cwd", "."), full_access=full)
    if not os.path.isdir(cwd_real):
        raise NotADirectoryError(f"Klasor bulunamadi: {cwd_display}")

    command = str(args.get("command") or "").strip()
    keep_open = bool(args.get("keep_open", True))

    if os.name == "nt":
        if shutil.which("wt.exe"):
            cmd_line = ["wt.exe", "-d", cwd_real]
            if command:
                ps_flag = "-NoExit" if keep_open else ""
                cmd_line += ["powershell.exe", *( [ps_flag] if ps_flag else [] ), "-Command", command]
            subprocess.Popen(cmd_line, creationflags=subprocess.DETACHED_PROCESS)  # type: ignore[attr-defined]
            launcher = "wt.exe"
        else:
            flag = "/k" if keep_open else "/c"
            full_cmd = f'start "" cmd.exe {flag} "{command}"' if command else 'start "" cmd.exe'
            subprocess.Popen(full_cmd, shell=True, cwd=cwd_real)
            launcher = "cmd.exe"
        return {"tool": "open_terminal_window", "opened": True, "launcher": launcher, "cwd": cwd_display, "command": command}

    if sys.platform == "darwin":
        cd_cmd = f"cd {json.dumps(cwd_real)}"
        script_body = f"{cd_cmd}; {command}" if command else cd_cmd
        osa = f'tell application "Terminal" to do script {json.dumps(script_body)}\ntell application "Terminal" to activate'
        subprocess.Popen(["osascript", "-e", osa])
        return {"tool": "open_terminal_window", "opened": True, "launcher": "Terminal.app", "cwd": cwd_display, "command": command}

    # Linux / BSD desktop
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        raise RuntimeError(
            "Masaustu grafik oturumu (DISPLAY/WAYLAND_DISPLAY) bulunamadi. "
            "Bunun yerine 'terminal_start' + 'terminal_write' kullanabilirsiniz."
        )

    shell = os.environ.get("SHELL") or "/bin/bash"
    tail = f"; exec {shell}" if (command and keep_open) else ""
    shell_cmd = f"{command}{tail}" if command else shell

    candidates = [
        ("x-terminal-emulator", lambda: ["x-terminal-emulator", "-e", shell, "-lc", shell_cmd]),
        ("gnome-terminal", lambda: ["gnome-terminal", "--working-directory", cwd_real, "--", shell, "-lc", shell_cmd]),
        ("konsole", lambda: ["konsole", "--workdir", cwd_real, "-e", shell, "-lc", shell_cmd]),
        ("xfce4-terminal", lambda: ["xfce4-terminal", "--working-directory", cwd_real, "-e", f"{shell} -lc {json.dumps(shell_cmd)}"]),
        ("kitty", lambda: ["kitty", "--directory", cwd_real, shell, "-lc", shell_cmd]),
        ("alacritty", lambda: ["alacritty", "--working-directory", cwd_real, "-e", shell, "-lc", shell_cmd]),
        ("xterm", lambda: ["xterm", "-e", shell, "-lc", shell_cmd]),
    ]
    for bin_name, build_cmd in candidates:
        if shutil.which(bin_name):
            subprocess.Popen(build_cmd(), cwd=cwd_real, start_new_session=True)
            return {
                "tool": "open_terminal_window",
                "opened": True,
                "launcher": bin_name,
                "cwd": cwd_display,
                "command": command,
            }

    raise RuntimeError("Sistemde desteklenen masaustu terminal uygulamasi bulunamadi. 'terminal_start' kullanabilirsiniz.")


def dispatch(request: Dict[str, Any]) -> Dict[str, Any]:
    req_id = request.get("id")
    tool = request.get("tool")
    args = request.get("args") or {}
    if not isinstance(args, dict):
        return {"id": req_id, "ok": False, "error": "'args' bir JSON nesnesi olmalidir."}

    config = load_config()
    allowed = config.get("allowed_tools", DEFAULT_ALLOWED_TOOLS)
    if tool not in allowed:
        audit_log({"tool": tool, "ok": False, "reason": "tool_not_allowed"})
        return {
            "id": req_id,
            "ok": False,
            "error": f"'{tool}' araci config.json tarafindan devre disi birakilmis.",
        }

    try:
        if tool == "ping":
            result = handle_ping(config)
        elif tool == "list_dir":
            result = handle_list_dir(args, config)
        elif tool == "read_file":
            result = handle_read_file(args, config)
        elif tool == "write_file":
            result = handle_write_file(args, config)
        elif tool == "edit_file":
            result = handle_edit_file(args, config)
        elif tool == "delete_path":
            result = handle_delete_path(args, config)
        elif tool == "run_command":
            result = handle_run_command(args, config)
        elif tool in ("terminal_start", "terminal_write", "terminal_read", "terminal_list", "terminal_kill"):
            result = handle_terminal_tool(tool, args, config)
        elif tool == "open_terminal_window":
            result = handle_open_terminal_window(args, config)
        else:
            raise ValueError(f"Bilinmeyen arac: {tool}")

        audit_log(
            {
                "id": req_id,
                "tool": tool,
                "ok": True,
                "target": args.get("path") or args.get("command") or args.get("session_id") or args.get("input") or ".",
                "exit_code": result.get("exit_code"),
            }
        )
        return {"id": req_id, "ok": True, "result": result}
    except Exception as exc:
        audit_log(
            {
                "id": req_id,
                "tool": tool,
                "ok": False,
                "error": str(exc),
                "target": args.get("path") or args.get("command") or args.get("session_id"),
            }
        )
        return {"id": req_id, "ok": False, "error": str(exc)}


def main() -> int:
    setup_binary_stdio()
    while True:
        try:
            msg = read_native_message()
            if msg is None:
                return 0
            response = dispatch(msg)
            write_native_message(response)
        except EOFError:
            return 0
        except Exception as exc:
            try:
                write_native_message({"id": None, "ok": False, "error": f"Host error: {exc}"})
            except Exception:
                return 1


if __name__ == "__main__":
    sys.exit(main())
