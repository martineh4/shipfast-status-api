import json
import os
import threading
import unittest
import urllib.error
import urllib.request

import status_api


class StatusApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ.update({"APP_VERSION": "1.2.3", "GIT_COMMIT": "abc1234", "APP_ENV": "test"})
        cls.server = status_api.make_server(host="127.0.0.1", port=0)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=5) as resp:
                return resp.status, resp.headers, json.loads(resp.read())
        except urllib.error.HTTPError as err:
            with err:
                return err.code, err.headers, json.loads(err.read())

    def test_healthz(self):
        code, headers, body = self.get("/healthz")
        self.assertEqual(code, 200)
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(body, {"status": "ok"})

    def test_readyz(self):
        code, _, body = self.get("/readyz")
        self.assertEqual(code, 200)
        self.assertEqual(body, {"status": "ready"})

    def test_status_reports_build_metadata(self):
        code, _, body = self.get("/status")
        self.assertEqual(code, 200)
        self.assertEqual(body["service"], "shipfast-status-api")
        self.assertEqual(body["team"], "platform")
        self.assertEqual(body["version"], "1.2.3")
        self.assertEqual(body["commit"], "abc1234")
        self.assertEqual(body["environment"], "test")
        self.assertGreaterEqual(body["uptime_seconds"], 0)

    def test_query_string_is_ignored_for_routing(self):
        code, _, _ = self.get("/status?verbose=1")
        self.assertEqual(code, 200)

    def test_unknown_path_returns_404(self):
        code, _, body = self.get("/nope")
        self.assertEqual(code, 404)
        self.assertEqual(body["path"], "/nope")


if __name__ == "__main__":
    unittest.main()
