import base64
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app import app


def _basic_auth(username="monitor", password="dashboard-secret"):
    value = base64.b64encode(f"{username}:{password}".encode()).decode()
    return {"Authorization": f"Basic {value}"}


@pytest.fixture(autouse=True)
def secure_configuration():
    original = app.config.copy()
    app.config.update(
        TESTING=True,
        MONITOR_AUTH_DISABLED=False,
        MONITOR_USERNAME="monitor",
        MONITOR_PASSWORD="dashboard-secret",
        MONITOR_METRICS_TOKEN="metrics-secret",
        MONITOR_NODE_NAME="test-node",
        MONITOR_SHOW_HOSTNAME=False,
        MONITOR_SHOW_USERNAMES=False,
    )
    yield
    app.config.clear()
    app.config.update(original)


def test_health_endpoint_does_not_require_authentication():
    response = app.test_client().get("/healthz")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_dashboard_rejects_unauthenticated_request():
    response = app.test_client().get("/")

    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"].startswith("Basic")


def test_index_renders_dashboard_with_basic_authentication():
    response = app.test_client().get("/", headers=_basic_auth())

    assert response.status_code == 200
    assert "Server Monitor" in response.get_data(as_text=True)


def test_stats_api_masks_hostname_by_default():
    response = app.test_client().get("/api/stats", headers=_basic_auth())
    data = response.get_json()

    assert response.status_code == 200
    assert {"cpu", "memory", "swap", "disk", "network", "system", "timestamp"} <= data.keys()
    assert isinstance(data["cpu"]["percent"], (int, float))
    assert data["system"]["hostname"] == "test-node"


def test_processes_api_masks_usernames_by_default():
    response = app.test_client().get("/api/processes", headers=_basic_auth())
    data = response.get_json()

    assert response.status_code == 200
    assert isinstance(data, list)
    if data:
        assert {"pid", "name", "cpu_percent", "memory_percent", "username"} <= data[0].keys()
        assert data[0]["username"] == "hidden"


def test_metrics_requires_bearer_token():
    client = app.test_client()

    assert client.get("/metrics").status_code == 401
    response = client.get("/metrics", headers={"Authorization": "Bearer metrics-secret"})

    assert response.status_code == 200
    assert "server_monitor_cpu_usage_percent" in response.get_data(as_text=True)
    assert 'node="test-node"' in response.get_data(as_text=True)


def test_missing_credentials_fail_closed():
    client = app.test_client()
    app.config["MONITOR_PASSWORD"] = ""

    assert client.get("/").status_code == 503

    app.config["MONITOR_METRICS_TOKEN"] = ""
    assert client.get("/metrics").status_code == 503


def test_explicit_local_development_mode_can_disable_dashboard_authentication():
    app.config["MONITOR_AUTH_DISABLED"] = True

    assert app.test_client().get("/").status_code == 200
