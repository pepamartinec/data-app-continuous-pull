#!/usr/bin/env python3
"""Tiny HTTP server: POST /_api/pull triggers an immediate git pull."""
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PULL_ONCE = "/tmp/continuous-pull/scripts/pull_once.sh"
PORT = 8051


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/_api/pull":
            self.send_error(404)
            return
        try:
            result = subprocess.run(
                ["bash", PULL_ONCE],
                capture_output=True,
                text=True,
                timeout=300,
            )
        except subprocess.TimeoutExpired:
            self.send_error(504, "pull_once timed out")
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
