from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_endpoint_reports_down():
    assert client.get("/health").json() == {"status": "DOWN"}
