#!/usr/bin/env python3
"""YoLoIT terminal runtime daemon.

Dev MVP:
- macOS/Linux PTY host using Python stdlib.
- Localhost HTTP API with NDJSON stream attach.
- Independent from Flutter UI process.
"""

from __future__ import annotations

import argparse
import base64
import fcntl
import json
import os
import pty
import queue
import select
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

PROTOCOL_VERSION = 1


def _default_home() -> Path:
    if os.environ.get("YOLOIT_DEV_RUNTIME") == "1":
        return Path.home() / ".config" / "yoloit-dev" / "runtime"
    return Path(os.environ.get("YOLOIT_RUNTIME_HOME", Path.home() / ".config" / "yoloit" / "runtime"))


class RuntimeSession:
    def __init__(self, session_id: str, cwd: str, command: str, cols: int, rows: int, env: dict[str, str]):
        self.id = session_id
        self.cwd = cwd
        self.command = command
        self.created_at = time.time()
        self.master_fd, slave_fd = pty.openpty()
        self.subscribers: list[queue.Queue[dict[str, Any]]] = []
        self.ring: list[str] = []
        self.ring_bytes = 0
        self.max_ring_bytes = 512 * 1024
        self.alive = True
        self.exit_code: int | None = None
        self._set_size(cols, rows)
        merged_env = os.environ.copy()
        merged_env.update(env)
        merged_env.setdefault("TERM", "xterm-256color")
        merged_env.setdefault("COLORTERM", "truecolor")
        self.process = subprocess.Popen(
            command,
            cwd=cwd,
            env=merged_env,
            shell=True,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True,
            preexec_fn=os.setsid if hasattr(os, "setsid") else None,
        )
        os.close(slave_fd)
        os.set_blocking(self.master_fd, False)
        self.pid = self.process.pid
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "cwd": self.cwd,
            "command": self.command,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.created_at)),
            "alive": self.alive,
            "pid": self.pid,
        }

    def _publish(self, event: dict[str, Any]) -> None:
        for subscriber in list(self.subscribers):
            try:
                subscriber.put_nowait(event)
            except Exception:
                self.subscribers.remove(subscriber)

    def _append_ring(self, data: str) -> None:
        self.ring.append(data)
        self.ring_bytes += len(data.encode("utf-8", "ignore"))
        while self.ring_bytes > self.max_ring_bytes and self.ring:
            removed = self.ring.pop(0)
            self.ring_bytes -= len(removed.encode("utf-8", "ignore"))

    def _read_loop(self) -> None:
        while True:
            try:
                readable, _, _ = select.select([self.master_fd], [], [], 0.1)
                if readable:
                    raw = os.read(self.master_fd, 8192)
                    if raw:
                        data = raw.decode("utf-8", "replace")
                        self._append_ring(data)
                        self._publish({"type": "output", "sessionId": self.id, "data": data})
                if self.process.poll() is not None:
                    while True:
                        try:
                            raw = os.read(self.master_fd, 8192)
                        except BlockingIOError:
                            break
                        if not raw:
                            break
                        data = raw.decode("utf-8", "replace")
                        self._append_ring(data)
                        self._publish({"type": "output", "sessionId": self.id, "data": data})
                    self.alive = False
                    self.exit_code = self.process.returncode
                    self._publish({"type": "exit", "sessionId": self.id, "exitCode": self.exit_code})
                    return
            except OSError:
                self.alive = False
                self._publish({"type": "exit", "sessionId": self.id, "exitCode": self.exit_code})
                return

    def write(self, data: str) -> None:
        if self.alive:
            os.write(self.master_fd, data.encode("utf-8", "ignore"))

    def resize(self, cols: int, rows: int) -> None:
        self._set_size(cols, rows)
        self._publish({"type": "resizeAck", "sessionId": self.id})

    def _set_size(self, cols: int, rows: int) -> None:
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)

    def kill(self) -> None:
        if not self.alive:
            return
        try:
            os.killpg(os.getpgid(self.process.pid), signal.SIGTERM)
        except Exception:
            self.process.terminate()
        self.alive = False


class RuntimeState:
    def __init__(self) -> None:
        self.sessions: dict[str, RuntimeSession] = {}
        self.lock = threading.Lock()

    def create(self, payload: dict[str, Any]) -> RuntimeSession:
        if not payload.get("id"):
            raise ValueError("missing session id")
        session_id = str(payload["id"])
        cwd = str(payload.get("cwd") or os.getcwd())
        command = str(payload.get("command") or os.environ.get("SHELL") or "/bin/sh")
        cols = int(payload.get("cols") or 120)
        rows = int(payload.get("rows") or 30)
        env = payload.get("env") if isinstance(payload.get("env"), dict) else {}
        with self.lock:
            existing = self.sessions.get(session_id)
            if existing and existing.alive:
                existing.attached_existing = True
                return existing
            session = RuntimeSession(session_id, cwd, command, cols, rows, {str(k): str(v) for k, v in env.items()})
            session.attached_existing = False
            self.sessions[session_id] = session
            return session


STATE = RuntimeState()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _json(self, obj: dict[str, Any], code: int = 200) -> None:
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length") or "0")
        if length <= 0:
            return {}
        return json.loads(self.rfile.read(length).decode())

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        parts = [p for p in parsed.path.split("/") if p]
        if parsed.path == "/health":
            self._json({"ok": True, "protocolVersion": PROTOCOL_VERSION, "pid": os.getpid()})
            return
        if parts == ["sessions"]:
            self._json({"ok": True, "sessions": [s.to_json() for s in STATE.sessions.values()]})
            return
        if len(parts) == 3 and parts[0] == "sessions" and parts[2] == "stream":
            session = STATE.sessions.get(parts[1])
            if not session:
                self._json({"ok": False, "error": "session not found"}, 404)
                return
            self._stream(session, parse_qs(parsed.query).get("replay", ["1"])[0] != "0")
            return
        self._json({"ok": False, "error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        parts = [p for p in urlparse(self.path).path.split("/") if p]
        payload = self._read_json()
        if parts == ["sessions"]:
            try:
                session = STATE.create(payload)
            except ValueError as exc:
                self._json({"ok": False, "error": str(exc)}, 400)
                return
            self._json({"ok": True, "session": session.to_json(), "existing": getattr(session, "attached_existing", False)})
            return
        if len(parts) == 3 and parts[0] == "sessions":
            session = STATE.sessions.get(parts[1])
            if not session:
                self._json({"ok": False, "error": "session not found"}, 404)
                return
            if parts[2] == "input":
                data = base64.b64decode(str(payload.get("data") or "")).decode("utf-8", "replace")
                session.write(data)
                self._json({"ok": True})
                return
            if parts[2] == "resize":
                session.resize(int(payload.get("cols") or 120), int(payload.get("rows") or 30))
                self._json({"ok": True})
                return
            if parts[2] == "kill":
                session.kill()
                self._json({"ok": True})
                return
        self._json({"ok": False, "error": "not found"}, 404)

    def _stream(self, session: RuntimeSession, replay: bool) -> None:
        q: queue.Queue[dict[str, Any]] = queue.Queue()
        session.subscribers.append(q)
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        try:
            if replay:
                for data in session.ring:
                    self.wfile.write((json.dumps({"type": "output", "sessionId": session.id, "data": data}) + "\n").encode())
                self.wfile.flush()
            while True:
                event = q.get()
                self.wfile.write((json.dumps(event) + "\n").encode())
                self.wfile.flush()
                if event.get("type") == "exit":
                    return
        except Exception:
            pass
        finally:
            if q in session.subscribers:
                session.subscribers.remove(q)

    def log_message(self, fmt: str, *args: Any) -> None:
        return


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", default=str(_default_home()))
    args = parser.parse_args()
    home = Path(args.home).expanduser()
    home.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    (home / "runtime.port").write_text(str(server.server_port))
    (home / "runtime.pid").write_text(str(os.getpid()))
    try:
        server.serve_forever()
    finally:
        for session in list(STATE.sessions.values()):
            session.kill()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
