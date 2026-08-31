"""A minimal Chrome DevTools Protocol driver — enough to TYPE and CLICK.

The web harness could only ever screenshot. That is why the web is the one
platform that has never been verified in a multiplayer run: joining a room needs
a team name typed and a Join button pressed, and `--screenshot` cannot press
anything. Every native platform has a driven-join hook; the web had no equivalent
and no way to act, so "the web can join a hosted game" was untested in both
directions — not failing, just never asked.

The alternative was to add a URL parameter that auto-joins. That would be changing
the product to make a test pass, and it would put a "join as any name" link into a
shipped app for the harness's convenience. Driving the real browser the way a
person does costs ~120 lines and tests the real thing.

Stdlib only: CDP is JSON over a WebSocket, and a client-side WebSocket is a
handshake plus masked frames. No new dependency for the repo to carry.
"""
import base64
import json
import os
import socket
import struct
import subprocess
import time
import urllib.request

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


class WS:
    """Just enough WebSocket for CDP: text frames, client-masked, no extensions."""

    def __init__(self, url, timeout=20):
        _, rest = url.split("://", 1)
        hostport, path = rest.split("/", 1)
        host, port = hostport.split(":")
        self.sock = socket.create_connection((host, int(port)), timeout=timeout)
        self.sock.settimeout(timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n".encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.sock.recv(4096)
        if b"101" not in buf.split(b"\r\n")[0]:
            raise RuntimeError(f"websocket handshake refused: {buf[:120]!r}")
        self.buf = buf.split(b"\r\n\r\n", 1)[1]
        self._id = 0

    def _recv(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed mid-frame")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, obj):
        data = json.dumps(obj).encode()
        n = len(data)
        head = bytes([0x81])
        if n < 126:
            head += bytes([0x80 | n])
        elif n < 1 << 16:
            head += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            head += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(head + mask + masked)

    def recv(self):
        b0, b1 = self._recv(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", self._recv(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self._recv(8))[0]
        payload = self._recv(n)
        if (b0 & 0x0F) != 1:                 # ignore ping/pong/binary
            return None
        return json.loads(payload)

    def call(self, method, params=None, timeout=20):
        self._id += 1
        mid = self._id
        self.send({"id": mid, "method": method, "params": params or {}})
        deadline = time.time() + timeout
        while time.time() < deadline:
            msg = self.recv()
            if msg and msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
        raise TimeoutError(method)


class Browser:
    """A headed Chrome on a private profile, driven over CDP.

    HEADED, not headless: the site is a PWA whose service worker and IndexedDB
    behave differently under `--headless`, and the point of this harness is to
    exercise what a person's browser does.
    """

    def __init__(self, port=9333, profile="/tmp/tidbits-cdp-profile", headless=True):
        self.proc = subprocess.Popen(
            [CHROME, f"--remote-debugging-port={port}", f"--user-data-dir={profile}",
             "--no-first-run", "--no-default-browser-check",
             "--disable-features=Translate,MediaRouter",
             *(["--headless=new", "--disable-gpu"] if headless else []),
             "--window-size=390,844", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.port = port
        target = None
        deadline = time.time() + 25
        while time.time() < deadline and target is None:
            time.sleep(0.4)
            try:
                pages = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{port}/json/list", timeout=3).read())
                target = next((p for p in pages if p.get("type") == "page"), None)
            except Exception:                       # noqa: BLE001
                continue
        if target is None:
            self.close()
            raise RuntimeError("Chrome never exposed a debuggable page")
        self.ws = WS(target["webSocketDebuggerUrl"])
        self.ws.call("Page.enable")
        self.ws.call("Runtime.enable")

    def goto(self, url, settle=3.0):
        self.ws.call("Page.navigate", {"url": url}, timeout=30)
        time.sleep(settle)

    def js(self, expr, timeout=20):
        """Evaluate and return the JSON value. `await` is supported."""
        r = self.ws.call("Runtime.evaluate",
                         {"expression": expr, "returnByValue": True,
                          "awaitPromise": True, "userGesture": True},
                         timeout=timeout)
        if r.get("exceptionDetails"):
            raise RuntimeError(str(r["exceptionDetails"])[:300])
        return r.get("result", {}).get("value")

    def text(self):
        return self.js("document.body.innerText") or ""

    def screenshot(self, path):
        r = self.ws.call("Page.captureScreenshot", {"captureBeyondViewport": False},
                         timeout=30)
        with open(path, "wb") as f:
            f.write(base64.b64decode(r["data"]))
        return os.path.exists(path)

    def close(self):
        try:
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:                            # noqa: BLE001
            self.proc.kill()
