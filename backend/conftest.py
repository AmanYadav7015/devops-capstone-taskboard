import os

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL", "sqlite+pysqlite:///:memory:")

# The test suite must never reach the production database. Overriding DATABASE_URL
# before app.config is imported pins every engine in the process to the test database.
os.environ["DATABASE_URL"] = TEST_DATABASE_URL

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app

if TEST_DATABASE_URL.startswith("sqlite"):
    test_engine = create_engine(
        TEST_DATABASE_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
else:
    test_engine = create_engine(TEST_DATABASE_URL, pool_pre_ping=True)

TestingSessionLocal = sessionmaker(bind=test_engine, autoflush=False, autocommit=False)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db


@pytest.fixture(autouse=True)
def fresh_schema():
    Base.metadata.drop_all(bind=test_engine)
    Base.metadata.create_all(bind=test_engine)
    yield
    Base.metadata.drop_all(bind=test_engine)


@pytest.fixture()
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def seeded_tasks(client):
    payloads = [
        {"title": "Provision VPC with Terraform", "priority": "HIGH", "assignee": "Aman Yadav", "status": "TODO"},
        {"title": "Write Helm chart", "priority": "MEDIUM", "assignee": "Aman Yadav", "status": "IN_PROGRESS"},
        {"title": "Publish images to GHCR", "priority": "LOW", "assignee": "Aman Yadav", "status": "DONE"},
    ]
    return [client.post("/api/tasks", json=payload).json() for payload in payloads]
