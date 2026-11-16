#!/usr/bin/env python3
"""Minimal obs-websocket (protocol v5) client for the bird cam scripts. Standard library only.

Usage: obs-ws.py streaming | start-stream | stop-stream

  streaming     exit 0 if OBS is streaming, 1 if not
  start-stream  start streaming (no-op if already streaming)
  stop-stream   stop streaming (no-op if not streaming)

Any command exits 3 if OBS can't be reached (not running, or WebSocket server disabled)
and 4 if the request fails. The port and password come from OBS's obs-websocket config;
OBS_WS_HOST, OBS_WS_PORT and OBS_WS_PASSWORD override them.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys

CONFIG = os.path.expanduser("~/.config/obs-studio/plugin_config/obs-websocket/config.json")


class Unreachable(Exception):
    pass


class RequestFailed(Exception):
    pass


class ObsWs:
    def __init__(self, host, port, password, timeout=5):
        try:
            self.sock = socket.create_connection((host, port), timeout=timeout)
        except OSError as e:
            raise Unreachable(f"can't connect to obs-websocket at {host}:{port} ({e})")
        self.buf = b""
        self._handshake(host, port)
        self._identify(password)
        self.next_id = 0

    # --- WebSocket transport ---

    def _handshake(self, host, port):
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            f"GET / HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: obswebsocket.json\r\n\r\n"
        ).encode())
        while b"\r\n\r\n" not in self.buf:
            self.buf += self._recv_some()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise Unreachable("obs-websocket refused the connection: " + head.decode(errors="replace"))

    def _recv_some(self):
        chunk = self.sock.recv(65536)
        if not chunk:
            raise Unreachable("obs-websocket closed the connection")
        return chunk

    def _recv_exact(self, n):
        while len(self.buf) < n:
            self.buf += self._recv_some()
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    def _send_frame(self, opcode, payload):
        mask = os.urandom(4)
        n = len(payload)
        if n < 126:
            header = struct.pack("!BB", 0x80 | opcode, 0x80 | n)
        elif n < 1 << 16:
            header = struct.pack("!BBH", 0x80 | opcode, 0x80 | 126, n)
        else:
            header = struct.pack("!BBQ", 0x80 | opcode, 0x80 | 127, n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def _recv_message(self):
        message = b""
        while True:
            b0, b1 = self._recv_exact(2)
            opcode, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = struct.unpack("!H", self._recv_exact(2))[0]
            elif n == 127:
                n = struct.unpack("!Q", self._recv_exact(8))[0]
            mask = self._recv_exact(4) if b1 & 0x80 else None
            payload = self._recv_exact(n)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x8:  # close
                code = struct.unpack("!H", payload[:2])[0] if len(payload) >= 2 else None
                reason = payload[2:].decode(errors="replace")
                if code == 4009:
                    raise Unreachable("obs-websocket rejected the password")
                raise Unreachable(f"obs-websocket closed the connection ({code} {reason})".strip())
            if opcode == 0x9:  # ping
                self._send_frame(0xA, payload)
                continue
            if opcode == 0xA:  # pong
                continue
            message += payload
            if b0 & 0x80:  # FIN
                return json.loads(message)

    def _send(self, op, d):
        self._send_frame(0x1, json.dumps({"op": op, "d": d}).encode())

    # --- obs-websocket protocol ---

    def _identify(self, password):
        hello = self._recv_message()
        identify = {"rpcVersion": 1, "eventSubscriptions": 0}
        auth = hello["d"].get("authentication")
        if auth:
            if not password:
                raise Unreachable("obs-websocket requires a password, but none is configured")
            secret = base64.b64encode(hashlib.sha256((password + auth["salt"]).encode()).digest())
            identify["authentication"] = base64.b64encode(
                hashlib.sha256(secret + auth["challenge"].encode()).digest()).decode()
        self._send(1, identify)
        msg = self._recv_message()
        if msg.get("op") != 2:
            raise Unreachable(f"unexpected reply to Identify: {msg}")

    def request(self, request_type, data=None):
        """Send a request; return (status code, responseData)."""
        self.next_id += 1
        rid = str(self.next_id)
        self._send(6, {"requestType": request_type, "requestId": rid, "requestData": data or {}})
        while True:
            msg = self._recv_message()
            if msg.get("op") == 7 and msg["d"].get("requestId") == rid:
                status = msg["d"]["requestStatus"]
                if not status["result"] and status["code"] not in (500, 501):
                    raise RequestFailed(f"{request_type} failed: {status.get('code')} {status.get('comment', '')}")
                return status["code"], msg["d"].get("responseData", {})


def connect():
    cfg = {}
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        pass
    host = os.environ.get("OBS_WS_HOST", "127.0.0.1")
    port = int(os.environ.get("OBS_WS_PORT", cfg.get("server_port", 4455)))
    password = os.environ.get("OBS_WS_PASSWORD", cfg.get("server_password", "") if cfg.get("auth_required", True) else "")
    return ObsWs(host, port, password)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("streaming", "start-stream", "stop-stream"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        obs = connect()
        if sys.argv[1] == "streaming":
            _, data = obs.request("GetStreamStatus")
            return 0 if data.get("outputActive") else 1
        if sys.argv[1] == "start-stream":
            obs.request("StartStream")  # 500 OutputRunning = already streaming; fine
        else:
            obs.request("StopStream")  # 501 OutputNotRunning = already stopped; fine
        return 0
    except Unreachable as e:
        print(f"obs-ws: {e}", file=sys.stderr)
        return 3
    except (RequestFailed, OSError, ValueError, KeyError) as e:
        print(f"obs-ws: {e}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
