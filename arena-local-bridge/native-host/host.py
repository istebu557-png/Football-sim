#!/usr/bin/env python3
"""
Arena.ai Local Bridge - Chrome Native Messaging Host
Pure Python 3 stdlib implementation with strict workspace isolation.
"""

from __future__ import annotations

import json
import os
import platform
import signal
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HOST_VERSION = "1.0.0"
DEFAULT_ALLOWED_TOOLS = ["ping", "list_dir", "read_file", "write_file", "run_command"]
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
        # Shrink overly large fields if needed so Chrome does not reject >1MB response
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


def get_workspace_root(config: Dict[str, Any]) -> str:
    raw = str(config.get("workspace_root") or "").strip()
    if not raw:
        raise PermissionError(
            "workspace_root ayarlanmamis. Lutfen install.py calistirin veya ~/.arena-local-bridge/config.json dosyasini duzenleyin."
        )
    resolved = os.path.realpath(os.path.expanduser(raw))
    if not os.path.isdir(resolved):
        raise FileNotFoundError(f"workspace_root klasoru bulunamadi: {resolved}")
    return resolved


def resolve_safe_path(workspace_root: str, target_path: Optional[str]) -> Tuple[str, str]:
    """
    Resolve target_path safely within workspace_root.
    Returns (absolute_real_path, relative_posix_path).
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
    raw_ws = str(config.get("workspace_root") or "").strip()
    resolved_ws = os.path.realpath(os.path.expanduser(raw_ws)) if raw_ws else ""
    return {
        "tool": "ping",
        "host_version": HOST_VERSION,
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "workspace_root": resolved_ws,
        "workspace_exists": bool(resolved_ws and os.path.isdir(resolved_ws)),
        "allowed_tools": config.get("allowed_tools", DEFAULT_ALLOWED_TOOLS),
        "default_timeout_sec": config.get("default_timeout_sec", DEFAULT_TIMEOUT_SEC),
        "lock_workspace": bool(config.get("lock_workspace", True)),
        "config_path": str(get_config_path()),
        "config_error": config.get("_config_error"),
    }


def handle_list_dir(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    rel_arg = args.get("path", ".")
    target_real, rel_posix = resolve_safe_path(ws, rel_arg)
    if not os.path.isdir(target_real):
        raise NotADirectoryError(f"Klasor degil: {rel_posix}")

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
        "path": rel_posix,
        "total_entries": len(entries),
        "truncated": truncated,
        "entries": entries[:max_entries],
    }


def handle_read_file(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    path_arg = args.get("path")
    if not path_arg or not isinstance(path_arg, str):
        raise ValueError("read_file icin 'path' parametresi gerekli.")

    target_real, rel_posix = resolve_safe_path(ws, path_arg)
    if not os.path.isfile(target_real):
        raise FileNotFoundError(f"Dosya bulunamadi: {rel_posix}")

    max_read_bytes = int(config.get("max_read_bytes", DEFAULT_MAX_READ_BYTES))
    file_size = os.path.getsize(target_real)

    with open(target_real, "rb") as f:
        sample = f.read(4096)
        if b"\x00" in sample:
            raise ValueError(f"Ikili (binary) dosya metin olarak okunamaz: {rel_posix}")

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
        "path": rel_posix,
        "file_size": file_size,
        "total_lines": total_lines,
        "offset": offset,
        "lines_returned": len(selected),
        "truncated": truncated,
        "content": content,
    }


def handle_write_file(args: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    ws = get_workspace_root(config)
    path_arg = args.get("path")
    content = args.get("content")
    if not path_arg or not isinstance(path_arg, str):
        raise ValueError("write_file icin 'path' parametresi gerekli.")
    if content is None or not isinstance(content, str):
        raise ValueError("write_file icin 'content' (string) parametresi gerekli.")

    target_real, rel_posix = resolve_safe_path(ws, path_arg)
    create_dirs = bool(args.get("create_dirs", True))
    parent = os.path.dirname(target_real)
    if create_dirs:
        os.makedirs(parent, exist_ok=True)
    elif not os.path.isdir(parent):
        raise FileNotFoundError(f"Ust klasor bulunamadi: {os.path.dirname(rel_posix)}")

    encoded = content.encode("utf-8")
    with open(target_real, "wb") as f:
        f.write(encoded)

    return {
        "tool": "write_file",
        "path": rel_posix,
        "bytes_written": len(encoded),
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
    command = args.get("command")
    if not command or not isinstance(command, str) or not command.strip():
        raise ValueError("run_command icin bos olmayan 'command' parametresi gerekli.")

    cwd_arg = args.get("cwd", ".")
    cwd_real, cwd_rel = resolve_safe_path(ws, cwd_arg)
    if not os.path.isdir(cwd_real):
        raise NotADirectoryError(f"Calisma klasoru bulunamadi: {cwd_rel}")

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
    if os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
    else:
        popen_kwargs["start_new_session"] = True

    started = time.monotonic()
    proc = subprocess.Popen(command, **popen_kwargs)
    timed_out = False
    try:
        stdout_b, stderr_b = proc.communicate(timeout=timeout_sec)
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
        "cwd": cwd_rel,
        "exit_code": -1 if timed_out else proc.returncode,
        "timed_out": timed_out,
        "timeout_sec": timeout_sec,
        "duration_ms": duration_ms,
        "stdout": stdout_text,
        "stderr": stderr_text,
        "truncated": trunc_out or trunc_err,
    }


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
        elif tool == "run_command":
            result = handle_run_command(args, config)
        else:
            raise ValueError(f"Bilinmeyen arac: {tool}")

        audit_log(
            {
                "id": req_id,
                "tool": tool,
                "ok": True,
                "target": args.get("path") or args.get("command") or ".",
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
                "target": args.get("path") or args.get("command"),
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
