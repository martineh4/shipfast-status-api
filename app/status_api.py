"""ShipFast internal status-check API.

A deliberately small, dependency-free HTTP service (Python standard library only)
used to demonstrate the GitOps delivery workflow. Endpoints:

    GET /         service banner
    GET /healthz  liveness probe   - process is up
    GET /readyz   readiness probe  - ready to receive traffic
    GET /status   build + runtime metadata (version, commit, environment, uptime)

Configuration is read from environment variables so the same image can be
promoted unchanged between environments.
"""

import json
import logging
import os
import signal
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE_NAME = "shipfast-status-api"
TEAM = "platform"
STARTED_AT = time.time()

log = logging.getLogger(SERVICE_NAME)


def build_status():
    return {
        "service": SERVICE_NAME,
        "team": TEAM,
        "status": "ok",
        "version": os.environ.get("APP_VERSION", "dev"),
        "commit": os.environ.get("GIT_COMMIT", "unknown"),
        "environment": os.environ.get("APP_ENV", "local"),
        "hostname": socket.gethostname(),
        "uptime_seconds": round(time.time() - STARTED_AT, 3),
    }


class StatusHandler(BaseHTTPRequestHandler):
    server_version = SERVICE_NAME

    routes = {
        "/": lambda: {"service": SERVICE_NAME, "endpoints": ["/healthz", "/readyz", "/status"]},
        "/healthz": lambda: {"status": "ok"},
        "/readyz": lambda: {"status": "ready"},
        "/status": build_status,
    }

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        route = self.routes.get(path)
        if route is None:
            self._send_json(404, {"error": "not found", "path": path})
            return
        self._send_json(200, route())

    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Structured one-line access logs to stdout; skip probe noise.
        if self.path in ("/healthz", "/readyz"):
            return
        log.info(json.dumps({"client": self.client_address[0], "request": fmt % args}))


def make_server(host="0.0.0.0", port=8080):
    return ThreadingHTTPServer((host, port), StatusHandler)


def main():
    logging.basicConfig(level=logging.INFO, stream=sys.stdout, format="%(message)s")
    port = int(os.environ.get("PORT", "8080"))
    server = make_server(port=port)

    # Kubernetes sends SIGTERM on pod shutdown; stop accepting and exit cleanly.
    def shutdown(signum, _frame):
        log.info(json.dumps({"event": "shutdown", "signal": signum}))
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    log.info(json.dumps({"event": "startup", "port": port, **build_status()}))
    server.serve_forever()
    server.server_close()


if __name__ == "__main__":
    main()
