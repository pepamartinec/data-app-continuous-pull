#!/usr/bin/env python3
"""Tiny HTTP server exposing pull/re-setup triggers for the continuous pull app.

Endpoints:
  POST /_api/pull      - fetch + reset + restart app
  POST /_api/re-setup  - re-run watched app's setup.sh + restart app
"""
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

ROUTES = {
    "/_api/pull": "/tmp/continuous-pull/scripts/pull_once.sh",
    "/_api/re-setup": "/tmp/continuous-pull/scripts/re_setup.sh",
}
PORT = 8051


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        script = ROUTES.get(self.path)
        if script is None:
            self.send_error(404)
            return
        try:
            result = subprocess.run(
                ["bash", script],
                capture_output=True,
                text=True,
                timeout=600,
            )
        except subprocess.TimeoutExpired:
            self.send_error(504, f"{self.path} timed out")
            return

        body = (
            f"exit_code: {result.returncode}\n"
            f"--- stdout ---\n{result.stdout}"
            f"--- stderr ---\n{result.stderr}"
        ).encode()
        self.send_response(200 if result.returncode == 0 else 500)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[pull-api] {self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Pull API listening on 127.0.0.1:{PORT}", flush=True)
    sys.stdout.flush()
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
