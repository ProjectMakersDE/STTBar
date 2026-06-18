#!/usr/bin/env python3
"""
stt-eval-proxy.py — lokaler Server fuer die Testseite (loest das
"Failed to fetch"-Problem endgueltig).

WARUM das noetig ist:
  Wird stt-postprocess-eval.html per Doppelklick als file:// geoeffnet, hat die
  Seite eine "null"-Origin. Browser blockieren dann Requests an private LAN-IPs
  (192.168.x.x) bzw. an http:// ueberhaupt — das ist Private Network Access /
  Mixed-Content, NICHT das klassische CORS. Darum schlaegt es fehl, obwohl der
  LM-Studio-Server von ueberall sonst (curl, andere Tools) erreichbar ist, und
  darum macht "Proxy" vs. "direkt" keinen Unterschied: beides sind private IPs.

LOESUNG:
  Dieser Server liefert die HTML-Seite selbst aus (http://127.0.0.1:1235/) UND
  leitet die API-Calls (/api/..., /v1/...) an LM Studio weiter. Damit sind Seite
  und API dieselbe Origin -> kein CORS, kein Private-Network-Block, kein
  Mixed-Content. Der Sprung ins LAN passiert in Python, nicht im Browser.

START (Defaults passen zu deinem Setup):
    python3 stt-eval-proxy.py
  dann im Browser oeffnen:
    http://127.0.0.1:1235/

EIGENES ZIEL / PORT:
    python3 stt-eval-proxy.py http://192.168.30.30:1234 1235
"""
import os
import sys
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ---- Konfiguration ----
TARGET = os.environ.get("STT_PROXY_TARGET", "http://192.168.30.30:1234")
LISTEN_HOST = os.environ.get("STT_PROXY_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("STT_PROXY_PORT", "1235"))
PAGE = os.environ.get("STT_PROXY_PAGE", "stt-postprocess-eval.html")
ROOT = os.path.dirname(os.path.abspath(__file__))

_args = [a for a in sys.argv[1:] if a]
if len(_args) >= 1:
    TARGET = _args[0]
if len(_args) >= 2:
    LISTEN_PORT = int(_args[1])
TARGET = TARGET.rstrip("/")

# Pfad-Praefixe, die an LM Studio weitergeleitet werden (alles andere = statische Datei)
API_PREFIXES = ("/api", "/v1")
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".txt": "text/plain; charset=utf-8",
    ".svg": "image/svg+xml",
}


def _cors(h):
    h.send_header("Access-Control-Allow-Origin", "*")
    h.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
    h.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
    h.send_header("Access-Control-Allow-Private-Network", "true")
    h.send_header("Access-Control-Max-Age", "86400")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _is_api(self):
        p = self.path.split("?", 1)[0]
        return p.startswith(API_PREFIXES)

    # ---------- statische Datei ausliefern ----------
    def _serve_static(self):
        p = self.path.split("?", 1)[0]
        if p in ("/", ""):
            p = "/" + PAGE
        rel = p.lstrip("/")
        full = os.path.normpath(os.path.join(ROOT, rel))
        if not full.startswith(ROOT) or not os.path.isfile(full):
            self.send_response(404)
            _cors(self)
            self.send_header("Content-Length", "0")
            self.end_headers()
            print(f"  GET {self.path} -> 404 (nicht gefunden)", flush=True)
            return
        ext = os.path.splitext(full)[1].lower()
        ctype = CONTENT_TYPES.get(ext, "application/octet-stream")
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        _cors(self)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        print(f"  GET {self.path} -> 200 ({len(data)} B, {ctype})", flush=True)

    # ---------- an LM Studio weiterleiten ----------
    def _forward(self, method):
        t0 = time.time()
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else None
        url = TARGET + self.path
        req = urllib.request.Request(url, data=body, method=method)
        ct = self.headers.get("Content-Type")
        if ct:
            req.add_header("Content-Type", ct)
        auth = self.headers.get("Authorization")
        if auth:
            req.add_header("Authorization", auth)
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                data = r.read()
                status = r.status
                rct = r.headers.get("Content-Type", "application/json")
        except urllib.error.HTTPError as e:
            data = e.read()
            status = e.code
            rct = (e.headers.get("Content-Type", "application/json")
                   if e.headers else "application/json")
        except Exception as e:
            data = ('{"error":"proxy_forward_failed","detail":%s}'
                    % _json_str(str(e))).encode("utf-8")
            status = 502
            rct = "application/json"
            print(f"  !! Weiterleitung an {url} fehlgeschlagen: {e}", flush=True)
        self.send_response(status)
        _cors(self)
        self.send_header("Content-Type", rct)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        ms = int((time.time() - t0) * 1000)
        print(f"  {method} {self.path} -> {status} ({len(data)} B, {ms} ms) [an {TARGET}]", flush=True)

    def do_OPTIONS(self):
        self.send_response(204)
        _cors(self)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if self._is_api():
            self._forward("GET")
        else:
            self._serve_static()

    # ---------- Ergebnisse auf Platte speichern ----------
    def _save(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else b"{}"
        outdir = os.path.join(ROOT, "eval-results")
        os.makedirs(outdir, exist_ok=True)
        ts = time.strftime("%Y%m%d-%H%M%S")
        fpath = os.path.join(outdir, "stt-eval-%s.json" % ts)
        try:
            with open(fpath, "wb") as f:
                f.write(body)
            with open(os.path.join(outdir, "latest.json"), "wb") as f:
                f.write(body)
            rel = os.path.relpath(fpath, ROOT)
            resp = ('{"ok":true,"file":%s}' % _json_str(rel)).encode("utf-8")
            status = 200
            print(f"  POST /save -> gespeichert: {rel} ({len(body)} B)", flush=True)
        except Exception as e:
            resp = ('{"ok":false,"error":%s}' % _json_str(str(e))).encode("utf-8")
            status = 500
            print(f"  !! /save fehlgeschlagen: {e}", flush=True)
        self.send_response(status)
        _cors(self)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def do_POST(self):
        if self.path.split("?", 1)[0] == "/save":
            self._save()
        else:
            self._forward("POST")


def _json_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    bar = "=" * 66
    print(bar)
    print("  STT-Eval Server (Seite + API, same-origin)")
    print(f"  Seite oeffnen : http://{LISTEN_HOST}:{LISTEN_PORT}/")
    print(f"  Leitet API an : {TARGET}")
    print(f"  Endpoint i.d. Seite (Default): http://{LISTEN_HOST}:{LISTEN_PORT}/api/v1/chat")
    print("  -> Kein CORS / kein Private-Network-Block, weil Seite und API")
    print("     dieselbe Origin haben. (Beenden mit Ctrl+C)")
    print(bar, flush=True)
    httpd = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer beendet.")


if __name__ == "__main__":
    main()
