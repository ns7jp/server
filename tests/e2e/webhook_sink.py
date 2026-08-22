"""Small in-memory Alertmanager webhook receiver used only by E2E tests."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock


EVENTS: list[dict[str, object]] = []
EVENTS_LOCK = Lock()


class Handler(BaseHTTPRequestHandler):
    server_version = "server-monitor-e2e-sink/1"

    def _reply(self, status: int, payload: object) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        if self.path == "/healthz":
            self._reply(200, {"status": "ok"})
            return
        if self.path == "/events":
            with EVENTS_LOCK:
                snapshot = list(EVENTS)
            self._reply(200, snapshot)
            return
        self._reply(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler API
        if self.path != "/alerts":
            self._reply(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
        except (ValueError, json.JSONDecodeError):
            self._reply(400, {"error": "invalid JSON"})
            return

        event = {
            "received_at": datetime.now(timezone.utc).isoformat(),
            "status": payload.get("status"),
            "alerts": [
                {
                    "status": alert.get("status"),
                    "labels": alert.get("labels", {}),
                }
                for alert in payload.get("alerts", [])
            ],
        }
        with EVENTS_LOCK:
            EVENTS.append(event)
        self._reply(200, {"accepted": True})

    def log_message(self, format: str, *args: object) -> None:
        # Keep container logs deterministic and avoid echoing request bodies.
        print(f"webhook-sink: {format % args}", flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8081), Handler).serve_forever()
