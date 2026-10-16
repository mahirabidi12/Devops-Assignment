import os
os.environ["DATABASE_URL"] = "sqlite:///./test.db"

import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.db import engine, Base
from app import models  # ensure all models are registered with Base

@pytest.fixture(scope="session", autouse=True)
def create_test_tables():
    """Create all tables before the test session and drop them after."""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)

client = TestClient(app)

def test_health():
    assert client.get("/health").json() == {"status": "UP"}

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["service"] == "TaskBoard API"

def test_create_task_validation():
    response = client.post("/api/tasks", json={"title": "Deploy application", "priority": "HIGH", "assignee": "Student"})
    assert response.status_code == 201
    assert response.json()["title"] == "Deploy application"
