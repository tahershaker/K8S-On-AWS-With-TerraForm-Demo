"""
Visitor Counter - a small Flask app for the K8S-On-AWS-With-TerraForm-Demo repo.

Tracks how many times it has been visited and exposes basic info about
the pod it is running in. The count is kept in memory only, so it
resets whenever the pod restarts.
"""

import os
import platform
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify

app = Flask(__name__)

visit_count = 0
start_time = datetime.now(timezone.utc)


@app.route("/")
def home():
    global visit_count
    visit_count += 1
    hostname = socket.gethostname()
    return (
        f"<h1>Visitor Counter</h1>"
        f"<p>This page has been visited <strong>{visit_count}</strong> time(s).</p>"
        f"<p>Served by pod: <strong>{hostname}</strong></p>"
        f"<p>Try <a href='/api/visits'>/api/visits</a>, "
        f"<a href='/health'>/health</a>, or <a href='/info'>/info</a>.</p>"
    )


@app.route("/api/visits")
def api_visits():
    return jsonify(
        {
            "visits": visit_count,
            "hostname": socket.gethostname(),
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200


@app.route("/info")
def info():
    return jsonify(
        {
            "hostname": socket.gethostname(),
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "started_at": start_time.isoformat(),
            "env_message": os.environ.get("APP_MESSAGE", "no APP_MESSAGE env var set"),
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
