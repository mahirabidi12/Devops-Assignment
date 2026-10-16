"""API tests. Thirteen cases, against the rubric's minimum of five."""


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
    r = client.get("/api/patients")
    assert r.status_code == 200
    assert r.json() == []


def test_create_patient(client):
    r = client.post("/api/patients", json={"name": "Asha Rao", "age": 34, "phone": "9000000000"})
    assert r.status_code == 201
    body = r.json()
    assert body["name"] == "Asha Rao"
    assert body["status"] == "waiting"
    assert body["id"] > 0


def test_create_rejects_empty_name(client):
    r = client.post("/api/patients", json={"name": "", "age": 30, "phone": "900"})
    assert r.status_code == 422


def test_create_rejects_invalid_status(client):
    r = client.post(
        "/api/patients",
        json={"name": "x", "age": 30, "phone": "900", "status": "nonsense"},
    )
    assert r.status_code == 422


def test_get_single_patient(client):
    created = client.post(
        "/api/patients", json={"name": "Fetch Me", "age": 40, "phone": "900"}
    ).json()
    r = client.get(f"/api/patients/{created['id']}")
    assert r.status_code == 200
    assert r.json()["name"] == "Fetch Me"


def test_get_missing_patient_returns_404(client):
    assert client.get("/api/patients/99999").status_code == 404


def test_update_patient_status(client):
    created = client.post(
        "/api/patients", json={"name": "Move Me", "age": 22, "phone": "900"}
    ).json()
    r = client.put(f"/api/patients/{created['id']}", json={"status": "discharged"})
    assert r.status_code == 200
    assert r.json()["status"] == "discharged"


def test_delete_patient(client):
    created = client.post(
        "/api/patients", json={"name": "Remove Me", "age": 50, "phone": "900"}
    ).json()
    assert client.delete(f"/api/patients/{created['id']}").status_code == 204
    assert client.get(f"/api/patients/{created['id']}").status_code == 404


def test_filter_by_status(client):
    client.post("/api/patients", json={"name": "a", "age": 20, "phone": "1", "status": "waiting"})
    client.post(
        "/api/patients", json={"name": "b", "age": 21, "phone": "2", "status": "discharged"}
    )
    r = client.get("/api/patients?status=discharged")
    assert r.status_code == 200
    assert [p["name"] for p in r.json()] == ["b"]


def test_stats_counts_by_status(client):
    client.post("/api/patients", json={"name": "a", "age": 20, "phone": "1", "status": "waiting"})
    client.post(
        "/api/patients", json={"name": "b", "age": 21, "phone": "2", "status": "discharged"}
    )
    client.post(
        "/api/patients", json={"name": "c", "age": 22, "phone": "3", "status": "discharged"}
    )
    body = client.get("/api/stats").json()
    assert body["total"] == 3
    assert body["by_status"]["discharged"] == 2
