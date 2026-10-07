import pytest

from app.app import app as flask_app


@pytest.fixture
def client():
    flask_app.config.update(TESTING=True)
    with flask_app.test_client() as c:
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_echo(client):
    r = client.post("/api/echo", json={"message": "hello"})
    assert r.status_code == 200
    assert r.get_json()["echo"] == "hello"


def test_echo_rejects_long_input(client):
    r = client.post("/api/echo", json={"message": "x" * 1001})
    assert r.status_code == 400


def test_config_does_not_leak_secrets(client):
    r = client.get("/api/config")
    body = r.get_json()
    assert "api_key" not in body
    assert set(body) == {"environment", "api_key_configured", "database_configured"}
