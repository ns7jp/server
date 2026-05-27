"""Secure server monitoring dashboard and Prometheus exporter."""

from __future__ import annotations

import datetime
import hmac
import os
import platform
import socket
import time
from pathlib import Path

import psutil
from flask import Flask, Response, jsonify, render_template, request
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Gauge, generate_latest

_PROCESS_START_TIME = time.time()


def _bool_env(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def _secret_value(value_name: str, file_name: str, default: str = "") -> str:
    path = os.getenv(file_name)
    if path:
        try:
            return Path(path).read_text(encoding="utf-8").strip()
        except OSError:
            return default
    return os.getenv(value_name, default)


app = Flask(__name__)
app.config.update(
    MONITOR_AUTH_DISABLED=_bool_env("MONITOR_AUTH_DISABLED"),
    MONITOR_USERNAME=_secret_value("MONITOR_USERNAME", "MONITOR_USERNAME_FILE", "monitor"),
    MONITOR_PASSWORD=_secret_value("MONITOR_PASSWORD", "MONITOR_PASSWORD_FILE"),
    MONITOR_METRICS_TOKEN=_secret_value("MONITOR_METRICS_TOKEN", "MONITOR_METRICS_TOKEN_FILE"),
    MONITOR_NODE_NAME=os.getenv("MONITOR_NODE_NAME", "monitored-node"),
    MONITOR_SHOW_HOSTNAME=_bool_env("MONITOR_SHOW_HOSTNAME"),
    MONITOR_SHOW_USERNAMES=_bool_env("MONITOR_SHOW_USERNAMES"),
)


def _secure_equals(left: str | None, right: str) -> bool:
    return left is not None and hmac.compare_digest(left, right)


def _dashboard_authenticated() -> bool:
    if app.config["MONITOR_AUTH_DISABLED"]:
        return True
    auth = request.authorization
    return bool(
        auth
        and _secure_equals(auth.username, app.config["MONITOR_USERNAME"])
        and _secure_equals(auth.password, app.config["MONITOR_PASSWORD"])
    )


@app.before_request
def protect_sensitive_routes() -> Response | None:
    """Require credentials before returning host or metric information."""
    if request.path == "/healthz":
        return None

    if request.path == "/metrics":
        token = app.config["MONITOR_METRICS_TOKEN"]
        if not token:
            return Response("metrics token is not configured\n", status=503, mimetype="text/plain")
        expected = f"Bearer {token}"
        if not _secure_equals(request.headers.get("Authorization"), expected):
            return Response(
                "metrics authentication required\n",
                status=401,
                headers={"WWW-Authenticate": "Bearer"},
                mimetype="text/plain",
            )
        return None

    if not app.config["MONITOR_AUTH_DISABLED"] and not app.config["MONITOR_PASSWORD"]:
        return Response("dashboard credentials are not configured\n", status=503, mimetype="text/plain")

    if not _dashboard_authenticated():
        return Response(
            "authentication required\n",
            status=401,
            headers={"WWW-Authenticate": 'Basic realm="server-monitor"'},
            mimetype="text/plain",
        )
    return None


@app.after_request
def apply_security_headers(response: Response) -> Response:
    """Defense in depth: headers protect even when no reverse proxy is in front."""
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    if request.path != "/healthz":
        response.headers.setdefault("Cache-Control", "no-store")
    return response


def _collect_stats() -> dict:
    cpu_percent = psutil.cpu_percent(interval=0.1)
    cpu_per_core = psutil.cpu_percent(interval=0, percpu=True)
    try:
        frequency = psutil.cpu_freq()
        cpu_frequency_current = round(frequency.current, 0) if frequency else 0
        cpu_frequency_max = round(frequency.max, 0) if frequency else 0
    except Exception:
        cpu_frequency_current = 0
        cpu_frequency_max = 0

    memory = psutil.virtual_memory()
    swap = psutil.swap_memory()
    disks = []
    for partition in psutil.disk_partitions(all=False):
        try:
            usage = psutil.disk_usage(partition.mountpoint)
        except (PermissionError, OSError):
            continue
        disks.append(
            {
                "device": partition.device,
                "mountpoint": partition.mountpoint,
                "fstype": partition.fstype,
                "total": usage.total,
                "used": usage.used,
                "free": usage.free,
                "percent": usage.percent,
            }
        )

    network = psutil.net_io_counters()
    boot_time = datetime.datetime.fromtimestamp(psutil.boot_time())
    uptime = datetime.datetime.now() - boot_time
    hostname = (
        socket.gethostname()
        if app.config["MONITOR_SHOW_HOSTNAME"]
        else app.config["MONITOR_NODE_NAME"]
    )

    try:
        load_1, load_5, load_15 = os.getloadavg()
    except (AttributeError, OSError):
        load_1 = load_5 = load_15 = 0.0

    try:
        process_count = len(psutil.pids())
    except OSError:
        process_count = 0

    return {
        "cpu": {
            "percent": cpu_percent,
            "count_logical": psutil.cpu_count(logical=True),
            "count_physical": psutil.cpu_count(logical=False),
            "per_core": cpu_per_core,
            "freq_current": cpu_frequency_current,
            "freq_max": cpu_frequency_max,
        },
        "load_average": {
            "1m": round(load_1, 2),
            "5m": round(load_5, 2),
            "15m": round(load_15, 2),
        },
        "memory": {
            "total": memory.total,
            "used": memory.used,
            "available": memory.available,
            "percent": memory.percent,
        },
        "swap": {"total": swap.total, "used": swap.used, "percent": swap.percent},
        "disk": disks,
        "network": {
            "bytes_sent": network.bytes_sent,
            "bytes_recv": network.bytes_recv,
            "packets_sent": network.packets_sent,
            "packets_recv": network.packets_recv,
        },
        "system": {
            "os": platform.system(),
            "os_release": platform.release(),
            "hostname": hostname,
            "machine": platform.machine(),
            "processor": platform.processor() or "N/A",
            "python_version": platform.python_version(),
            "boot_time": boot_time.strftime("%Y-%m-%d %H:%M:%S"),
            "uptime_seconds": int(uptime.total_seconds()),
            "process_count": process_count,
        },
        "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }


@app.get("/healthz")
def healthz() -> tuple[dict[str, str], int]:
    """Liveness endpoint: it intentionally exposes no system information."""
    return {"status": "ok"}, 200


@app.get("/")
def index() -> str:
    return render_template("index.html")


@app.get("/api/stats")
def stats() -> Response:
    return jsonify(_collect_stats())


@app.get("/api/processes")
def processes() -> Response:
    show_usernames = app.config["MONITOR_SHOW_USERNAMES"]
    attributes = ["pid", "name", "cpu_percent", "memory_percent"]
    if show_usernames:
        attributes.append("username")

    process_list = []
    for process in psutil.process_iter(attributes):
        try:
            info = process.info
            process_list.append(
                {
                    "pid": info["pid"],
                    "name": info["name"] or "Unknown",
                    "cpu_percent": round(info["cpu_percent"] or 0, 1),
                    "memory_percent": round(info["memory_percent"] or 0, 2),
                    "username": (info.get("username") or "N/A") if show_usernames else "hidden",
                }
            )
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    process_list.sort(key=lambda process: process["cpu_percent"], reverse=True)
    return jsonify(process_list[:15])


@app.get("/metrics")
def metrics() -> Response:
    data = _collect_stats()
    registry = CollectorRegistry()
    labels = ["node"]
    node = app.config["MONITOR_NODE_NAME"]

    Gauge(
        "server_monitor_cpu_usage_percent",
        "CPU usage percentage sampled by server-monitor.",
        labels,
        registry=registry,
    ).labels(node).set(data["cpu"]["percent"])
    Gauge(
        "server_monitor_memory_usage_percent",
        "Memory usage percentage sampled by server-monitor.",
        labels,
        registry=registry,
    ).labels(node).set(data["memory"]["percent"])
    Gauge(
        "server_monitor_uptime_seconds",
        "Monitored system uptime in seconds.",
        labels,
        registry=registry,
    ).labels(node).set(data["system"]["uptime_seconds"])
    Gauge(
        "server_monitor_process_count",
        "Total number of processes visible to server-monitor.",
        labels,
        registry=registry,
    ).labels(node).set(data["system"]["process_count"])
    Gauge(
        "server_monitor_process_start_time_seconds",
        "Unix epoch start time of the server-monitor application process.",
        labels,
        registry=registry,
    ).labels(node).set(_PROCESS_START_TIME)
    load_gauge = Gauge(
        "server_monitor_load_average",
        "System load average sampled by server-monitor.",
        ["node", "window"],
        registry=registry,
    )
    for window, value in data["load_average"].items():
        load_gauge.labels(node, window).set(value)
    disk_gauge = Gauge(
        "server_monitor_disk_usage_percent",
        "Disk usage percentage; paths are deliberately not exported as labels.",
        ["node", "disk"],
        registry=registry,
    )
    for index, disk in enumerate(data["disk"]):
        disk_gauge.labels(node, f"disk_{index}").set(disk["percent"])

    return Response(generate_latest(registry), content_type=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
