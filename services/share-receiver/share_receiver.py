#!/usr/bin/env python3
"""OpenMinis Share Receiver — a tiny HTTP service that accepts URL/text
shares from another device on the LAN, appends them to a single buffer file,
and lets the running OpenMinis agent pick them up as its next user message.

Endpoint(s):
  POST /share          {"url", "text", "title", "source"}
  GET  /health          {"ok": true}
  GET  /             -> a tiny HTML status page (optional convenience)

No dependencies beyond Python 3 stdlib. Bind 0.0.0.0 on the given port.
"""
import json
import os
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

# Stable on-disk buffer path. Kept under this service's own directory (not the
# volatile /var/minis workspace) so the receiver stays usable even if the app
# sandbox's workspace is isolated/cleared. The running agent reads it via
# share_reader.py --consume.
OUTPUT_FILE = "/root/services/share-receiver/data/incoming-share.txt"
OUTPUT_FILE = os.environ.get("SHARE_OUTPUT", OUTPUT_FILE)


class ShareHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ---- helpers ----

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST,GET,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "content-type")

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _append_share(self, data: dict) -> int:
        os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
        source = data.get("source", "device")
        title = (data.get("title") or "").strip()
        url = (data.get("url") or "").strip()
        text = (data.get("text") or "").strip()
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        lines = [f"## 来自 {source} 的分享 · {ts}"]
        if title:
            lines.append(f"**标题**: {title}")
        if url:
            lines.append(f"**URL**: {url}")
        if text:
            lines.append("")
            lines.append(text)
        lines.append("---")
        lines.append("")

        with open(OUTPUT_FILE, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return len(lines)

    # ---- HTTP methods ----

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path in ("/health", "/api/health"):
            self._json(200, {"ok": True, "saved": OUTPUT_FILE})
            return
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(_HTML)))
            self._cors()
            self.end_headers()
            self.wfile.write(_HTML.encode())
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/share":
            self._json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json(400, {"error": "invalid JSON"})
            return
        if not isinstance(data, dict):
            self._json(400, {"error": "expected object"})
            return
        has_content = bool(
            data.get("url") or data.get("text") or data.get("title")
        )
        if not has_content:
            self._json(400, {"error": "share is empty"})
            return
        n = self._append_share(data)
        self._json(200, {"ok": True, "added": n, "file": OUTPUT_FILE})


_HTML = """<!doctype html><html lang="zh"><meta charset="utf-8">
<title>OpenMinis Share</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{background:#0c1018;color:#e7ecf3;font-family:sans-serif;padding:32px}
h1{color:#3b6cf6}</style>
<body><h1>OpenMinis · 分享接收端</h1>
<p>服务运行中。Firefox 扩展会向本服务发送分享。</p>
<p><code>POST /share</code>  { "url","text","title","source" }</p>
<p>缓冲文件: <code>%s</code></p></body></html>""" % OUTPUT_FILE


def main():
    port = 8741
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"bad port {sys.argv[1]}, using {port}")
    server = HTTPServer(("0.0.0.0", port), ShareHandler)
    print(f"[share-receiver] listening on 0.0.0.0:{port} -> {OUTPUT_FILE}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()


if __name__ == "__main__":
    main()
