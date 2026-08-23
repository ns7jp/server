"""AP tier: the only component that talks to the database.

`/healthz` と `/readyz` を分けているのが、この層の設計上の要点。

- `/healthz` は「プロセスが生きているか」だけを返し、DB を見ない。
- `/readyz` は「DB まで含めて要求を処理できるか」を返す。

分けておくと、障害時に
「web は 200 / ap の healthz は 200 / ap の readyz が 503」
という並びから、web でも ap でもなく DB 側が原因だと切り分けられる。
両方を混ぜて 1 つの health endpoint にすると、この区別ができない。
"""

from __future__ import annotations

import os
import socket

import psycopg
from flask import Flask, jsonify, render_template_string, request

app = Flask(__name__)

DB_SETTINGS = {
    "host": os.getenv("THREE_TIER_DB_HOST", "db"),
    "port": os.getenv("THREE_TIER_DB_PORT", "5432"),
    "dbname": os.getenv("THREE_TIER_DB_NAME", "inventory"),
    "user": os.getenv("THREE_TIER_DB_USER", "app"),
    "password": os.getenv("THREE_TIER_DB_PASSWORD", ""),
}
# DB が落ちているときに要求が積み上がらないよう、短いタイムアウトを明示する。
# 既定のままだと接続試行が長く残り、AP 層のワーカーを食い潰す。
CONNECT_TIMEOUT_SECONDS = int(os.getenv("THREE_TIER_DB_CONNECT_TIMEOUT", "3"))

PAGE = """<!doctype html>
<title>3-tier lab: inventory</title>
<h1>Inventory ({{ rows | length }} rows)</h1>
<p>served by AP node <code>{{ node }}</code></p>
<table border="1" cellpadding="4">
  <tr><th>id</th><th>sku</th><th>name</th><th>quantity</th></tr>
  {% for row in rows %}
  <tr><td>{{ row[0] }}</td><td>{{ row[1] }}</td><td>{{ row[2] }}</td><td>{{ row[3] }}</td></tr>
  {% endfor %}
</table>
"""


def _connect() -> psycopg.Connection:
    return psycopg.connect(connect_timeout=CONNECT_TIMEOUT_SECONDS, **DB_SETTINGS)


@app.get("/healthz")
def healthz():
    """AP プロセスの生存だけを返す。DB には触らない。"""
    return {"status": "ok", "tier": "ap", "node": socket.gethostname()}, 200


@app.get("/readyz")
def readyz():
    """DB まで含めて要求を処理できるかを返す。"""
    try:
        with _connect() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except Exception as error:  # noqa: BLE001 - 呼び出し元へ理由を返すため広く捕捉する
        return (
            jsonify(
                {
                    "status": "unavailable",
                    "tier": "ap",
                    "dependency": "db",
                    "error": type(error).__name__,
                    "detail": str(error).strip().splitlines()[0] if str(error).strip() else "",
                }
            ),
            503,
        )
    return {"status": "ok", "tier": "ap", "dependency": "db"}, 200


@app.get("/")
def index():
    with _connect() as connection, connection.cursor() as cursor:
        cursor.execute("SELECT id, sku, name, quantity FROM items ORDER BY id")
        rows = cursor.fetchall()
    return render_template_string(PAGE, rows=rows, node=socket.gethostname())


@app.get("/api/items")
def list_items():
    with _connect() as connection, connection.cursor() as cursor:
        cursor.execute("SELECT id, sku, name, quantity FROM items ORDER BY id")
        rows = cursor.fetchall()
    return jsonify(
        [{"id": r[0], "sku": r[1], "name": r[2], "quantity": r[3]} for r in rows]
    )


@app.get("/api/items/count")
def count_items():
    """復元演習で件数を突き合わせるための端点。"""
    with _connect() as connection, connection.cursor() as cursor:
        cursor.execute("SELECT count(*) FROM items")
        (count,) = cursor.fetchone()
    return {"count": count}


@app.post("/api/items")
def create_item():
    payload = request.get_json(silent=True) or {}
    sku = str(payload.get("sku", "")).strip()
    name = str(payload.get("name", "")).strip()
    quantity = payload.get("quantity", 0)
    if not sku or not name:
        return {"error": "sku and name are required"}, 400
    try:
        quantity = int(quantity)
    except (TypeError, ValueError):
        return {"error": "quantity must be an integer"}, 400

    with _connect() as connection, connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO items (sku, name, quantity) VALUES (%s, %s, %s) RETURNING id",
            (sku, name, quantity),
        )
        (new_id,) = cursor.fetchone()
        connection.commit()
    return {"id": new_id, "sku": sku, "name": name, "quantity": quantity}, 201


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
