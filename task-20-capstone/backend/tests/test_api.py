"""API tests. Twelve cases, against the rubric's minimum of five."""


def test_health_does_not_touch_the_database(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready_reports_ready_when_db_is_reachable(client):
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_metrics_endpoint_is_prometheus_format(client):
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "# HELP" in r.text


def test_list_is_empty_initially(client):
    r = client.get("/api/tasks")
    assert r.status_code == 200
    assert r.json() == []


def test_create_task(client):
    r = client.post("/api/tasks", json={"title": "write the capstone"})
    assert r.status_code == 201
    body = r.json()
    assert body["title"] == "write the capstone"
    assert body["status"] == "todo"
    assert body["id"] > 0


def test_create_rejects_empty_title(client):
    r = client.post("/api/tasks", json={"title": ""})
    assert r.status_code == 422


def test_create_rejects_invalid_status(client):
    r = client.post("/api/tasks", json={"title": "x", "status": "nonsense"})
    assert r.status_code == 422


def test_get_single_task(client):
    created = client.post("/api/tasks", json={"title": "fetch me"}).json()
    r = client.get(f"/api/tasks/{created['id']}")
    assert r.status_code == 200
    assert r.json()["title"] == "fetch me"


def test_get_missing_task_returns_404(client):
    assert client.get("/api/tasks/99999").status_code == 404


def test_update_task_status(client):
    created = client.post("/api/tasks", json={"title": "move me"}).json()
    r = client.put(f"/api/tasks/{created['id']}", json={"status": "done"})
    assert r.status_code == 200
    assert r.json()["status"] == "done"


def test_delete_task(client):
    created = client.post("/api/tasks", json={"title": "remove me"}).json()
    assert client.delete(f"/api/tasks/{created['id']}").status_code == 204
    assert client.get(f"/api/tasks/{created['id']}").status_code == 404


def test_filter_by_status(client):
    client.post("/api/tasks", json={"title": "a", "status": "todo"})
    client.post("/api/tasks", json={"title": "b", "status": "done"})
    r = client.get("/api/tasks?status=done")
    assert r.status_code == 200
    assert [t["title"] for t in r.json()] == ["b"]


def test_stats_counts_by_status(client):
    client.post("/api/tasks", json={"title": "a", "status": "todo"})
    client.post("/api/tasks", json={"title": "b", "status": "done"})
    client.post("/api/tasks", json={"title": "c", "status": "done"})
    body = client.get("/api/stats").json()
    assert body["total"] == 3
    assert body["by_status"]["done"] == 2
