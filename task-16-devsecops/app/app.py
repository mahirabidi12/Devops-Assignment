"""A small Flask API, used as the thing the DevSecOps pipeline scans."""
import os

from flask import Flask, jsonify, request

app = Flask(__name__)

# Configuration comes from the environment, never from a literal in the source.
# A hardcoded secret here is exactly what the secret-scanning stage looks for.
API_KEY = os.environ.get("API_KEY", "")
DATABASE_URL = os.environ.get("DATABASE_URL", "")


@app.route("/health")
def health():
    return jsonify(status="ok"), 200


@app.route("/ready")
def ready():
    configured = bool(DATABASE_URL)
    return jsonify(ready=configured), (200 if configured else 503)


@app.route("/api/echo", methods=["POST"])
def echo():
    payload = request.get_json(silent=True) or {}
    message = payload.get("message", "")

    # Length-bound the input. Unbounded echo is a cheap denial-of-service.
    if len(message) > 1000:
        return jsonify(error="message too long"), 400

    return jsonify(echo=message), 200


@app.route("/api/config")
def config():
    # Never return secrets. Report only whether they are present.
    return jsonify(
        environment=os.environ.get("ENVIRONMENT", "development"),
        api_key_configured=bool(API_KEY),
        database_configured=bool(DATABASE_URL),
    ), 200


if __name__ == "__main__":
    # Bind to all interfaces so the container is reachable, but never enable
    # debug mode outside local development - it exposes an RCE console.
    #
    # Bandit flags this as B104 (hardcoded_bind_all_interfaces). Inside a
    # container it is correct and necessary: binding to 127.0.0.1 would make the
    # process unreachable from outside the container, which is the exact problem
    # hit in the Docker task earlier in this homework. The network boundary here
    # is the container and the Kubernetes NetworkPolicy, not the bind address.
    app.run(
        host="0.0.0.0",  # nosec B104 # containers must bind all interfaces
        port=int(os.environ.get("PORT", 5000)),
        debug=False,
    )
