from conftest import TEST_DATABASE_URL

from app.config import settings
from app.db import get_db
from app.main import app

PRODUCTION_DATABASE_URL = "postgresql+psycopg://taskboard:taskboard@localhost:5432/taskboard"


def test_health_endpoint_reports_up(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "UP"}


def test_ready_endpoint_queries_the_database(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "READY"}


def test_root_returns_the_service_banner(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["service"] == "TaskBoard API"
    assert response.json()["version"] == "1.0.0"


def test_metrics_endpoint_exposes_prometheus_text(client):
    client.get("/health")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "# TYPE" in response.text


def test_suite_runs_against_the_test_database_not_production(client):
    assert settings.database_url == TEST_DATABASE_URL
    assert settings.database_url != PRODUCTION_DATABASE_URL
    assert get_db in app.dependency_overrides
