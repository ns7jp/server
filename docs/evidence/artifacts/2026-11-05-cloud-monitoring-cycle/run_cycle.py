"""Observe one real application stop/recovery cycle in an isolated lab."""

import json
import os
import pathlib
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone


ROOT = pathlib.Path(__file__).resolve().parent
SOURCE = ROOT / "source"
RESULT = {"actor": "Codex", "scope": "isolated cloud Compose / local webhook", "checks": []}
ENV = dict(os.environ)
for name in ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH"):
    ENV.pop(name, None)
COMPOSE = ["docker", "--host=unix:///var/run/docker.sock", "compose", "-p", "portfolio-cloud-cycle-20261105",
           "-f", "compose.yaml", "-f", "compose.e2e.yaml", "-f", "compose.cloud.yaml"]


def now():
    return datetime.now(timezone.utc).isoformat()


def save():
    (ROOT / "result.json").write_text(json.dumps(RESULT, indent=2) + "\n")


def mark(check, **data):
    row = {"check": check, "observed_at": now(), **data}
    RESULT["checks"].append(row)
    save()
    print(json.dumps(row), flush=True)


def request(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.load(response)


def http_status():
    try:
        with urllib.request.urlopen("http://127.0.0.1:28080/healthz", timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except (urllib.error.URLError, TimeoutError):
        return 0


def metric():
    query = urllib.parse.urlencode({"query": 'up{job="server-monitor",instance="app:5000"}'})
    response = request("http://127.0.0.1:29090/api/v1/query?" + query)
    data = response.get("data", {}).get("result", [])
    return data[0]["value"][1] if data else None


def seen(status):
    events = request("http://127.0.0.1:28081/events")
    for event in events:
        if event["status"] != status:
            continue
        for alert in event["alerts"]:
            if (alert.get("status") == status
                    and alert["labels"].get("alertname") == "ServerMonitorUnavailable"
                    and alert["labels"].get("instance") == "app:5000"):
                return event
    return None


def wait_for(predicate, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(2)
    raise RuntimeError(f"condition did not become true within {timeout}s")


def compose(*args):
    subprocess.run(COMPOSE + list(args), cwd=SOURCE, env=ENV, check=True)


stopped = False
RESULT["source_sha"] = (ROOT / "source-sha.txt").read_text().strip()
RESULT["started_at"] = now()
save()
try:
    wait_for(lambda: http_status() == 200 and metric() == "1", 90)
    if seen("firing") or seen("resolved"):
        raise RuntimeError("receiver already contains a matching cycle")
    mark("baseline", http_status=200, app_up="1", preexisting_cycle=False)
    compose("stop", "app")
    stopped = True
    mark("app_stopped", operation="docker compose stop app")
    wait_for(lambda: http_status() == 502 and metric() == "0", 60)
    mark("fault_observed", http_status=502, app_up="0")
    event = wait_for(lambda: seen("firing"), 240)
    mark("firing_received", event=event)
    alerts = request("http://127.0.0.1:29090/api/v1/alerts")["data"]["alerts"]
    matching = [a for a in alerts if a["labels"].get("alertname") == "ServerMonitorUnavailable"]
    if not any(a["state"] == "firing" for a in matching):
        raise RuntimeError("Prometheus firing state not confirmed")
    mark("prometheus_firing", alerts=matching)
    compose("start", "app")
    stopped = False
    mark("app_restarted", operation="docker compose start app")
    wait_for(lambda: http_status() == 200 and metric() == "1", 90)
    mark("recovery_observed", http_status=200, app_up="1")
    event = wait_for(lambda: seen("resolved"), 120)
    mark("resolved_received", event=event)
    RESULT["result"] = "PASS"
except Exception as error:
    RESULT["result"] = "FAIL"
    RESULT["error"] = str(error)
    raise
finally:
    if stopped:
        compose("start", "app")
        mark("cleanup_restart", operation="docker compose start app")
    RESULT["ended_at"] = now()
    save()
