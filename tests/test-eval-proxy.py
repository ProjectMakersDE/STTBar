#!/usr/bin/env python3
"""Synthetic HTTP tests; no personal files and no upstream network calls."""
import contextlib
import http.client
import importlib.util
import io
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
with patch("sys.argv", ["stt-eval-proxy.py"]):
    spec = importlib.util.spec_from_file_location("stt_eval_proxy", ROOT / "stt-eval-proxy.py")
    proxy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(proxy)


class StaticAssetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "repo"
        self.assets = self.repo / "eval-assets"
        self.assets.mkdir(parents=True)
        (self.repo / ".env").write_text("synthetic-secret")
        (self.assets / "index.html").write_text("synthetic-page")
        (self.assets / ".env").write_text("synthetic-secret")
        (self.assets / "script.py").write_text("synthetic-source")
        (self.assets / "escape.html").symlink_to(self.repo / ".env")
        sibling = self.repo.parent / "repo-sibling"
        sibling.mkdir()
        (sibling / "index.html").write_text("synthetic-sibling")
        self.settings = patch.multiple(proxy, ROOT=str(self.repo), STATIC_ROOT=self.assets, PAGE="index.html", create=True)
        self.settings.start()
        self.server = proxy.ThreadingHTTPServer(("127.0.0.1", 0), proxy.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.settings.stop()
        self.temp.cleanup()

    def request(self, path, method="GET", headers=None, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                conn.request(method, path, headers=headers or {}, body=body)
                response = conn.getresponse()
                return response.status, dict(response.getheaders()), response.read()
        finally:
            conn.close()

    def testOnlyDedicatedAssetsAreServed(self):
        self.assertEqual(self.request("/")[2], b"synthetic-page")
        self.assertEqual(self.request("/index.html?cache=1")[0], 200)
        for path in ["/.env", "/%2eenv", "/script.py", "/escape.html", "/../.env", "/../repo-sibling/index.html", "/%2e%2e/repo-sibling/index.html"]:
            self.assertEqual(self.request(path)[0], 404, path)

    def testCrossOriginRequestsCannotReadOrWrite(self):
        for method, path in [("GET", "/"), ("POST", "/save"), ("POST", "/v1/chat/completions")]:
            status, headers, _ = self.request(path, method=method, headers={"Origin": "https://untrusted.example"}, body=b"{}" if method == "POST" else None)
            self.assertEqual(status, 403)
            self.assertNotIn("Access-Control-Allow-Origin", headers)
        self.assertFalse((self.repo / "eval-results").exists())

    def testUnrelatedPostDoesNotForward(self):
        with patch.object(proxy.urllib.request, "urlopen") as upstream:
            self.assertEqual(self.request("/unrelated", method="POST", body=b"{}")[0], 404)
            upstream.assert_not_called()

    def testSameOriginSaveAndAPIRoutesRemainAvailable(self):
        origin = f"http://127.0.0.1:{self.server.server_port}"
        status, _, _ = self.request("/save", method="POST", headers={"Origin": origin}, body=b"{\"synthetic\":true}")
        self.assertEqual(status, 200)
        self.assertEqual((self.repo / "eval-results/latest.json").read_bytes(), b"{\"synthetic\":true}")
        response = unittest.mock.MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = b"{\"ok\":true}"
        response.status = 200
        response.headers = {"Content-Type": "application/json"}
        with patch.object(proxy.urllib.request, "urlopen", return_value=response) as upstream:
            self.assertEqual(self.request("/v1/models")[0], 200)
            self.assertTrue(upstream.call_args.args[0].full_url.endswith("/v1/models"))


if __name__ == "__main__":
    unittest.main()
