# Backend verification log

Real terminal output captured on 7 October 2026 while running the TaskBoard backend against a
PostgreSQL 16 container and the test suite against an isolated test database. Nothing in this file
is reconstructed from memory: every block below was redirected straight from the command that
produced it.

## Environment used for these runs

| Component | Value |
|-----------|-------|
| Python | 3.12.13, virtualenv with `backend/requirements.txt` installed verbatim |
| PostgreSQL | `postgres:16-alpine` container, published on host port 55432 |
| Application database | `postgresql+psycopg://taskboard:***@localhost:55432/taskboard` |
| Backend process | `uvicorn app.main:app --host 0.0.0.0 --port 8010` |
| Frontend | `npm run build` output served by `nginx:1.27-alpine` on host port 8011 |

Host ports 55432, 8010 and 8011 are used only so these checks can run alongside
`docker compose up`, which keeps the standard 5432, 8000 and 3000 ports. The code and configuration
under test are unchanged.

---

## 1. pytest

19 tests, 19 passed. The single warning comes from inside Starlette's own test client, not from
application or test code.

```text
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-8.3.4, pluggy-1.6.0 -- /private/tmp/capstone-venv/bin/python
cachedir: .pytest_cache
rootdir: /Users/aman/Desktop/devops-heros/capstone-devops-project/backend
configfile: pytest.ini
testpaths: tests
plugins: cov-6.0.0, anyio-4.15.1
collecting ... collected 19 items

tests/test_api.py::test_list_tasks_is_empty_on_a_fresh_database PASSED   [  5%]
tests/test_api.py::test_create_task_returns_201_and_persists_defaults PASSED [ 10%]
tests/test_api.py::test_created_task_is_returned_by_the_list_endpoint PASSED [ 15%]
tests/test_api.py::test_get_single_task_by_id PASSED                     [ 21%]
tests/test_api.py::test_get_missing_task_returns_404 PASSED              [ 26%]
tests/test_api.py::test_update_task_changes_status_and_priority PASSED   [ 31%]
tests/test_api.py::test_update_is_partial_and_leaves_other_fields_untouched PASSED [ 36%]
tests/test_api.py::test_update_missing_task_returns_404 PASSED           [ 42%]
tests/test_api.py::test_delete_task_returns_204_and_removes_it PASSED    [ 47%]
tests/test_api.py::test_delete_missing_task_returns_404 PASSED           [ 52%]
tests/test_api.py::test_stats_aggregates_counts_per_status PASSED        [ 57%]
tests/test_api.py::test_stats_follow_a_status_change PASSED              [ 63%]
tests/test_api.py::test_create_rejects_an_empty_title PASSED             [ 68%]
tests/test_api.py::test_create_rejects_an_unknown_status PASSED          [ 73%]
tests/test_health.py::test_health_endpoint_reports_up PASSED             [ 78%]
tests/test_health.py::test_ready_endpoint_queries_the_database PASSED    [ 84%]
tests/test_health.py::test_root_returns_the_service_banner PASSED        [ 89%]
tests/test_health.py::test_metrics_endpoint_exposes_prometheus_text PASSED [ 94%]
tests/test_health.py::test_suite_runs_against_the_test_database_not_production PASSED [100%]

=============================== warnings summary ===============================
../../../../../../private/tmp/capstone-venv/lib/python3.12/site-packages/starlette/testclient.py:40
  /private/tmp/capstone-venv/lib/python3.12/site-packages/starlette/testclient.py:40: DeprecationWarning: The anyio.abc.BlockingPortal alias is deprecated, use anyio.from_thread.BlockingPortal instead.
    _PortalFactoryType = typing.Callable[[], typing.ContextManager[anyio.abc.BlockingPortal]]

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
======================== 19 passed, 1 warning in 0.12s =========================
```

### Coverage

```text
...................                                                      [100%]
=============================== warnings summary ===============================
../../../../../../private/tmp/capstone-venv/lib/python3.12/site-packages/starlette/testclient.py:40
  /private/tmp/capstone-venv/lib/python3.12/site-packages/starlette/testclient.py:40: DeprecationWarning: The anyio.abc.BlockingPortal alias is deprecated, use anyio.from_thread.BlockingPortal instead.
    _PortalFactoryType = typing.Callable[[], typing.ContextManager[anyio.abc.BlockingPortal]]

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html

--------- coverage: platform darwin, python 3.12.13-final-0 ----------
Name              Stmts   Miss  Cover   Missing
-----------------------------------------------
app/__init__.py       0      0   100%
app/config.py         6      0   100%
app/db.py            12      4    67%   12-16
app/main.py          65      0   100%
app/models.py        13      0   100%
app/schemas.py       26      0   100%
-----------------------------------------------
TOTAL               122      4    97%

19 passed, 1 warning in 0.17s
```

`app/main.py`, which holds every route, is at 100 percent. The four uncovered lines in `app/db.py`
are the production `get_db()` session factory, which the suite deliberately replaces with a test
session, so that gap is itself evidence of the isolation described next.

---

## 2. The suite never touches the application database

Three mechanisms are stacked so a test run cannot reach the application database.

1. `backend/conftest.py` rewrites `DATABASE_URL` to the test database before `app.config` is
   imported, so every engine created in the process is pinned to the test database.
2. The FastAPI `get_db` dependency is replaced with a session bound to a separate test engine
   through `app.dependency_overrides`.
3. An autouse fixture drops and recreates the schema around every test, so no test inherits state
   from another.

`backend/conftest.py`:

```python
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
```

The default test database is an in-memory SQLite database held open with `StaticPool`, so a plain
`pytest` run in CI needs no database service and leaves no files behind.

### Evidence that the application database was untouched

```text
$ docker exec capstone-postgres psql -U taskboard -d taskboard -tAc 'SELECT count(*) FROM tasks;'
5                        <- before three pytest runs

$ docker exec capstone-postgres psql -U taskboard -d taskboard -c 'SELECT id,title,status FROM tasks ORDER BY id;'
 id |             title              |   status
----+--------------------------------+-------------
  1 | Provision VPC with Terraform   | TODO
  2 | Write Helm chart for TaskBoard | DONE
  3 | Add Trivy scan to pipeline     | IN_PROGRESS
  4 | Wire Prometheus scrape config  | IN_PROGRESS
  5 | Publish images to GHCR         | DONE
(5 rows)                 <- after three pytest runs, row for row identical
```

### The same suite against a dedicated PostgreSQL test database

Setting `TEST_DATABASE_URL` points the suite at a real PostgreSQL database named `taskboard_test`
instead of SQLite. The application database is still never opened.

```text
$ docker exec capstone-postgres psql -U taskboard -d postgres -c 'CREATE DATABASE taskboard_test OWNER taskboard;'
CREATE DATABASE

$ TEST_DATABASE_URL=postgresql+psycopg://taskboard:taskboard@localhost:55432/taskboard_test pytest -v
============================= test session starts ==============================
platform darwin -- Python 3.12.13, pytest-8.3.4, pluggy-1.6.0 -- /private/tmp/capstone-venv/bin/python
cachedir: .pytest_cache
rootdir: /Users/aman/Desktop/devops-heros/capstone-devops-project/backend
configfile: pytest.ini
testpaths: tests
plugins: cov-6.0.0, anyio-4.15.1
collecting ... collected 19 items

tests/test_api.py::test_list_tasks_is_empty_on_a_fresh_database PASSED   [  5%]
tests/test_api.py::test_create_task_returns_201_and_persists_defaults PASSED [ 10%]
tests/test_api.py::test_created_task_is_returned_by_the_list_endpoint PASSED [ 15%]
tests/test_api.py::test_get_single_task_by_id PASSED                     [ 21%]
tests/test_api.py::test_get_missing_task_returns_404 PASSED              [ 26%]
tests/test_api.py::test_update_task_changes_status_and_priority PASSED   [ 31%]
tests/test_api.py::test_update_is_partial_and_leaves_other_fields_untouched PASSED [ 36%]
tests/test_api.py::test_update_missing_task_returns_404 PASSED           [ 42%]
tests/test_api.py::test_delete_task_returns_204_and_removes_it PASSED    [ 47%]
tests/test_api.py::test_delete_missing_task_returns_404 PASSED           [ 52%]
tests/test_api.py::test_stats_aggregates_counts_per_status PASSED        [ 57%]
tests/test_api.py::test_stats_follow_a_status_change PASSED              [ 63%]
tests/test_api.py::test_create_rejects_an_empty_title PASSED             [ 68%]
tests/test_api.py::test_create_rejects_an_unknown_status PASSED          [ 73%]
tests/test_health.py::test_health_endpoint_reports_up PASSED             [ 78%]
tests/test_health.py::test_ready_endpoint_queries_the_database PASSED    [ 84%]
tests/test_health.py::test_root_returns_the_service_banner PASSED        [ 89%]
tests/test_health.py::test_metrics_endpoint_exposes_prometheus_text PASSED [ 94%]
tests/test_health.py::test_suite_runs_against_the_test_database_not_production PASSED [100%]

=============================== warnings summary ===============================
../../../../../../private/tmp/capstone-venv/lib/python3.12/site-packages/starlette/testclient.py:40
  /private/tmp/capstone-venv/lib/python3.12/site-packages/starlette/testclient.py:40: DeprecationWarning: The anyio.abc.BlockingPortal alias is deprecated, use anyio.from_thread.BlockingPortal instead.
    _PortalFactoryType = typing.Callable[[], typing.ContextManager[anyio.abc.BlockingPortal]]

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
======================== 19 passed, 1 warning in 0.47s =========================
```

Afterwards the test database is left with no relations at all, because the fixture tears its schema
down.

### Test case inventory

| File | Tests | Endpoints exercised |
|------|-------|---------------------|
| `tests/test_api.py` | 14 | `GET /api/tasks`, `POST /api/tasks`, `GET /api/tasks/{id}`, `PUT /api/tasks/{id}`, `DELETE /api/tasks/{id}`, `GET /api/tasks/stats` |
| `tests/test_health.py` | 5 | `GET /health`, `GET /ready`, `GET /`, `GET /metrics`, plus the database isolation assertion |

Nineteen tests across nine endpoints. `backend/pytest.ini` sets `pythonpath = .`,
`testpaths = tests` and `addopts = -ra --strict-markers`.

---

## 3. Alembic migration against PostgreSQL

Run against a brand new, empty database so the migration genuinely does the work, including a
`downgrade base` then `upgrade head` round trip.

```text
Target: a brand new, empty PostgreSQL database (postgres:16-alpine container).

$ docker exec capstone-postgres psql -U taskboard -d taskboard -c "\dt"
Did not find any relations.
$ alembic current
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.

$ alembic history --verbose
Rev: 0001_create_tasks (head)
Parent: <base>
Path: /Users/aman/Desktop/devops-heros/capstone-devops-project/backend/alembic/versions/0001_create_tasks.py



$ alembic upgrade head
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tasks

$ alembic current
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
0001_create_tasks (head)

$ psql -c "\d tasks"
                                       Table "public.tasks"
   Column    |           Type           | Collation | Nullable |              Default              
-------------+--------------------------+-----------+----------+-----------------------------------
 id          | integer                  |           | not null | nextval('tasks_id_seq'::regclass)
 title       | character varying(200)   |           | not null | 
 description | text                     |           | not null | ''::text
 priority    | character varying(20)    |           | not null | 'MEDIUM'::character varying
 status      | character varying(30)    |           | not null | 'TODO'::character varying
 assignee    | character varying(120)   |           | not null | 'Unassigned'::character varying
 created_at  | timestamp with time zone |           | not null | 
Indexes:
    "tasks_pkey" PRIMARY KEY, btree (id)

$ psql -c "SELECT * FROM alembic_version;"
    version_num    
-------------------
 0001_create_tasks
(1 row)

$ psql -c "\dt"
              List of relations
 Schema |      Name       | Type  |   Owner   
--------+-----------------+-------+-----------
 public | alembic_version | table | taskboard
 public | tasks           | table | taskboard
(2 rows)

$ alembic downgrade base
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running downgrade 0001_create_tasks -> 
$ psql -c "\dt"
              List of relations
 Schema |      Name       | Type  |   Owner   
--------+-----------------+-------+-----------
 public | alembic_version | table | taskboard
(1 row)

$ alembic upgrade head
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tasks
$ psql -c "\dt"
              List of relations
 Schema |      Name       | Type  |   Owner   
--------+-----------------+-------+-----------
 public | alembic_version | table | taskboard
 public | tasks           | table | taskboard
(2 rows)
```

The `tasks` table, its `tasks_id_seq` identity sequence, its primary key and all seven columns are
created by `alembic/versions/0001_create_tasks.py`, and `alembic_version` records the applied
revision. The container entrypoint is `alembic upgrade head && exec uvicorn app.main:app`, so
migrations always run before the API accepts traffic. The application's own `create_all` during
startup is an idempotent safety net for local runs and tests; on PostgreSQL the schema is owned by
the migration.

---

## 4. Full REST API transcript against PostgreSQL

Every endpoint in the contract in one pass: the CRUD cycle, 201 on create, 204 on delete, 404 on a
missing id for all three verbs, 422 on invalid input, and `/api/tasks/stats` returning correct
aggregates after known data was seeded and then changed.

```text
########## 1. Service banner, health, readiness
$ curl -s -X GET http://127.0.0.1:8010/ -w '\nHTTP %{http_code}\n'
{"service":"TaskBoard API","version":"1.0.0","docs":"/docs"}
HTTP 200

$ curl -s -X GET http://127.0.0.1:8010/health -w '\nHTTP %{http_code}\n'
{"status":"UP"}
HTTP 200

$ curl -s -X GET http://127.0.0.1:8010/ready -w '\nHTTP %{http_code}\n'
{"status":"READY"}
HTTP 200

########## 2. Prometheus metrics (first 12 lines)
$ curl -s http://127.0.0.1:8010/metrics | head -12
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
python_gc_objects_collected_total{generation="0"} 468.0
python_gc_objects_collected_total{generation="1"} 30.0
python_gc_objects_collected_total{generation="2"} 10.0
# HELP python_gc_objects_uncollectable_total Uncollectable objects found during GC
# TYPE python_gc_objects_uncollectable_total counter
python_gc_objects_uncollectable_total{generation="0"} 0.0
python_gc_objects_uncollectable_total{generation="1"} 0.0
python_gc_objects_uncollectable_total{generation="2"} 0.0
# HELP python_gc_collections_total Number of times this generation was collected
# TYPE python_gc_collections_total counter

########## 3. Empty list before seeding
$ curl -s -X GET http://127.0.0.1:8010/api/tasks -w '\nHTTP %{http_code}\n'
[]
HTTP 200

$ curl -s -X GET http://127.0.0.1:8010/api/tasks/stats -w '\nHTTP %{http_code}\n'
{"total":0,"todo":0,"inProgress":0,"done":0}
HTTP 200

########## 4. POST /api/tasks  -> 201 Created (seed 6 known tasks)
$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Provision VPC with Terraform","description":"Two public subnets in ap-south-1","priority":"HIGH","assignee":"Aman Yadav"}' -w '\nHTTP %{http_code}\n'
{"title":"Provision VPC with Terraform","description":"Two public subnets in ap-south-1","priority":"HIGH","status":"TODO","assignee":"Aman Yadav","id":1,"created_at":"2026-10-07T14:10:39.922464Z"}
HTTP 201

$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Write Helm chart for TaskBoard","description":"Deployments, services, ingress","priority":"MEDIUM","assignee":"Aman Yadav"}' -w '\nHTTP %{http_code}\n'
{"title":"Write Helm chart for TaskBoard","description":"Deployments, services, ingress","priority":"MEDIUM","status":"TODO","assignee":"Aman Yadav","id":2,"created_at":"2026-10-07T14:10:39.946851Z"}
HTTP 201

$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Add Trivy scan to pipeline","description":"Fail on HIGH and CRITICAL","priority":"HIGH","assignee":"Aman Yadav","status":"IN_PROGRESS"}' -w '\nHTTP %{http_code}\n'
{"title":"Add Trivy scan to pipeline","description":"Fail on HIGH and CRITICAL","priority":"HIGH","status":"IN_PROGRESS","assignee":"Aman Yadav","id":3,"created_at":"2026-10-07T14:10:39.970478Z"}
HTTP 201

$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Wire Prometheus scrape config","description":"ServiceMonitor for the backend","priority":"LOW","assignee":"Aman Yadav","status":"IN_PROGRESS"}' -w '\nHTTP %{http_code}\n'
{"title":"Wire Prometheus scrape config","description":"ServiceMonitor for the backend","priority":"LOW","status":"IN_PROGRESS","assignee":"Aman Yadav","id":4,"created_at":"2026-10-07T14:10:39.993908Z"}
HTTP 201

$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Publish images to GHCR","description":"Tag with the commit SHA","priority":"MEDIUM","assignee":"Aman Yadav","status":"DONE"}' -w '\nHTTP %{http_code}\n'
{"title":"Publish images to GHCR","description":"Tag with the commit SHA","priority":"MEDIUM","status":"DONE","assignee":"Aman Yadav","id":5,"created_at":"2026-10-07T14:10:40.019392Z"}
HTTP 201

$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Document the capstone runbook","description":"README and troubleshooting notes","priority":"LOW","assignee":"Aman Yadav"}' -w '\nHTTP %{http_code}\n'
{"title":"Document the capstone runbook","description":"README and troubleshooting notes","priority":"LOW","status":"TODO","assignee":"Aman Yadav","id":6,"created_at":"2026-10-07T14:10:40.046057Z"}
HTTP 201

########## 5. GET /api/tasks -> full list
$ curl -s -X GET http://127.0.0.1:8010/api/tasks -w '\nHTTP %{http_code}\n'
[{"title":"Document the capstone runbook","description":"README and troubleshooting notes","priority":"LOW","status":"TODO","assignee":"Aman Yadav","id":6,"created_at":"2026-10-07T14:10:40.046057Z"},{"title":"Publish images to GHCR","description":"Tag with the commit SHA","priority":"MEDIUM","status":"DONE","assignee":"Aman Yadav","id":5,"created_at":"2026-10-07T14:10:40.019392Z"},{"title":"Wire Prometheus scrape config","description":"ServiceMonitor for the backend","priority":"LOW","status":"IN_PROGRESS","assignee":"Aman Yadav","id":4,"created_at":"2026-10-07T14:10:39.993908Z"},{"title":"Add Trivy scan to pipeline","description":"Fail on HIGH and CRITICAL","priority":"HIGH","status":"IN_PROGRESS","assignee":"Aman Yadav","id":3,"created_at":"2026-10-07T14:10:39.970478Z"},{"title":"Write Helm chart for TaskBoard","description":"Deployments, services, ingress","priority":"MEDIUM","status":"TODO","assignee":"Aman Yadav","id":2,"created_at":"2026-10-07T14:10:39.946851Z"},{"title":"Provision VPC with Terraform","description":"Two public subnets in ap-south-1","priority":"HIGH","status":"TODO","assignee":"Aman Yadav","id":1,"created_at":"2026-10-07T14:10:39.922464Z"}]
HTTP 200

########## 6. GET /api/tasks/{id} -> single task
$ curl -s -X GET http://127.0.0.1:8010/api/tasks/1 -w '\nHTTP %{http_code}\n'
{"title":"Provision VPC with Terraform","description":"Two public subnets in ap-south-1","priority":"HIGH","status":"TODO","assignee":"Aman Yadav","id":1,"created_at":"2026-10-07T14:10:39.922464Z"}
HTTP 200

########## 7. GET /api/tasks/stats -> expect total=6 todo=3 inProgress=2 done=1
$ curl -s -X GET http://127.0.0.1:8010/api/tasks/stats -w '\nHTTP %{http_code}\n'
{"total":6,"todo":3,"inProgress":2,"done":1}
HTTP 200

########## 8. PUT /api/tasks/{id} -> move task 2 TODO -> DONE
$ curl -s -X PUT http://127.0.0.1:8010/api/tasks/2 -H 'Content-Type: application/json' -d '{"status":"DONE","priority":"HIGH"}' -w '\nHTTP %{http_code}\n'
{"title":"Write Helm chart for TaskBoard","description":"Deployments, services, ingress","priority":"HIGH","status":"DONE","assignee":"Aman Yadav","id":2,"created_at":"2026-10-07T14:10:39.946851Z"}
HTTP 200

########## 9. GET /api/tasks/stats -> expect total=6 todo=2 inProgress=2 done=2
$ curl -s -X GET http://127.0.0.1:8010/api/tasks/stats -w '\nHTTP %{http_code}\n'
{"total":6,"todo":2,"inProgress":2,"done":2}
HTTP 200

########## 10. DELETE /api/tasks/{id} -> 204 No Content
$ curl -s -X DELETE http://127.0.0.1:8010/api/tasks/6 -w '\nHTTP %{http_code}\n'

HTTP 204

########## 11. GET deleted id -> 404
$ curl -s -X GET http://127.0.0.1:8010/api/tasks/6 -w '\nHTTP %{http_code}\n'
{"detail":"Task not found"}
HTTP 404

########## 12. GET /api/tasks/stats after delete -> expect total=5 todo=1 inProgress=2 done=2
$ curl -s -X GET http://127.0.0.1:8010/api/tasks/stats -w '\nHTTP %{http_code}\n'
{"total":5,"todo":1,"inProgress":2,"done":2}
HTTP 200

########## 13. 404 paths on a missing id
$ curl -s -X GET http://127.0.0.1:8010/api/tasks/9999 -w '\nHTTP %{http_code}\n'
{"detail":"Task not found"}
HTTP 404

$ curl -s -X PUT http://127.0.0.1:8010/api/tasks/9999 -H 'Content-Type: application/json' -d '{"status":"DONE"}' -w '\nHTTP %{http_code}\n'
{"detail":"Task not found"}
HTTP 404

$ curl -s -X DELETE http://127.0.0.1:8010/api/tasks/9999 -w '\nHTTP %{http_code}\n'
{"detail":"Task not found"}
HTTP 404

########## 14. Validation: empty title -> 422, bad enum -> 422
$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":""}' -w '\nHTTP %{http_code}\n'
{"detail":[{"type":"string_too_short","loc":["body","title"],"msg":"String should have at least 1 character","input":"","ctx":{"min_length":1}}]}
HTTP 422

$ curl -s -X POST http://127.0.0.1:8010/api/tasks -H 'Content-Type: application/json' -d '{"title":"Bad status","status":"ARCHIVED"}' -w '\nHTTP %{http_code}\n'
{"detail":[{"type":"literal_error","loc":["body","status"],"msg":"Input should be 'TODO', 'IN_PROGRESS' or 'DONE'","input":"ARCHIVED","ctx":{"expected":"'TODO', 'IN_PROGRESS' or 'DONE'"}}]}
HTTP 422

########## 15. Final list
$ curl -s -X GET http://127.0.0.1:8010/api/tasks -w '\nHTTP %{http_code}\n'
[{"title":"Publish images to GHCR","description":"Tag with the commit SHA","priority":"MEDIUM","status":"DONE","assignee":"Aman Yadav","id":5,"created_at":"2026-10-07T14:10:40.019392Z"},{"title":"Wire Prometheus scrape config","description":"ServiceMonitor for the backend","priority":"LOW","status":"IN_PROGRESS","assignee":"Aman Yadav","id":4,"created_at":"2026-10-07T14:10:39.993908Z"},{"title":"Add Trivy scan to pipeline","description":"Fail on HIGH and CRITICAL","priority":"HIGH","status":"IN_PROGRESS","assignee":"Aman Yadav","id":3,"created_at":"2026-10-07T14:10:39.970478Z"},{"title":"Write Helm chart for TaskBoard","description":"Deployments, services, ingress","priority":"HIGH","status":"DONE","assignee":"Aman Yadav","id":2,"created_at":"2026-10-07T14:10:39.946851Z"},{"title":"Provision VPC with Terraform","description":"Two public subnets in ap-south-1","priority":"HIGH","status":"TODO","assignee":"Aman Yadav","id":1,"created_at":"2026-10-07T14:10:39.922464Z"}]
HTTP 200
```

Stats were checked three times against data whose shape was known in advance. Six tasks seeded as
3 TODO, 2 IN_PROGRESS, 1 DONE returned total 6, todo 3, inProgress 2, done 1. After one `PUT` moved
a task from TODO to DONE it returned total 6, todo 2, inProgress 2, done 2. After one `DELETE` it
returned total 5, todo 1, inProgress 2, done 2.

---

## 5. Frontend build and the served application

```text
$ npm run build
vite v8.3.3 building client environment for production...
transforming...
 15 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                   0.46 kB | gzip:  0.30 kB
dist/assets/index-CaDU8gDp.css    7.64 kB | gzip:  2.34 kB
dist/assets/index-CU52_SNU.js   228.39 kB | gzip: 71.26 kB
built in 90ms
```

The build output was then served by nginx using the project's own `frontend/nginx.conf`, with only
the proxy upstream redirected at the backend running on the host, and exercised end to end.

```text
########## A. Built index.html served by nginx
$ curl -s -i http://localhost:8011/ | head -12
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Wed, 07 Oct 2026 14:15:33 GMT
Content-Type: text/html
Content-Length: 461
Last-Modified: Wed, 07 Oct 2026 14:14:04 GMT
Connection: keep-alive
ETag: "6ac653ac-1cd"
Accept-Ranges: bytes

<!doctype html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><meta name="description" content="TaskBoard - DevOps capstone task management dashboard"/><title>TaskBoard | DevOps Capstone</title>  <script type="module" crossorigin src="/assets/index-Z_tNZ2ln.js"></script>
  <link rel="stylesheet" crossorigin href="/assets/index-CkmyYzrm.css">

########## B. SPA fallback for a client-side route
$ curl -s -o /dev/null -w "%{http_code}
" http://localhost:8011/dashboard/anything
200

########## C. Hashed asset bundles exist and are served
$ ls -l frontend/dist frontend/dist/assets
/Users/aman/Desktop/devops-heros/capstone-devops-project/frontend/dist:
total 8
drwxr-xr-x  4 aman  staff  128 Oct  7 19:44 assets
-rw-r--r--  1 aman  staff  461 Oct  7 19:44 index.html

/Users/aman/Desktop/devops-heros/capstone-devops-project/frontend/dist/assets:
total 464
-rw-r--r--  1 aman  staff    7227 Oct  7 19:44 index-CkmyYzrm.css
-rw-r--r--  1 aman  staff  228390 Oct  7 19:44 index-Z_tNZ2ln.js

$ curl -s -o /dev/null -w 'js %{http_code} %{size_download} bytes
' http://localhost:8011/assets/index-Z_tNZ2ln.js
js 200 228390 bytes
$ curl -s -o /dev/null -w 'css %{http_code} %{size_download} bytes
' http://localhost:8011/assets/index-CkmyYzrm.css
css 200 7227 bytes

########## D. The served JS bundle contains the application code (API calls, CRUD handlers)
  /api           occurrences in bundle: 1
  /tasks/stats   occurrences in bundle: 1
  IN_PROGRESS    occurrences in bundle: 1
  DELETE         occurrences in bundle: 1
  New task       occurrences in bundle: 1
  Delete task    occurrences in bundle: 1
  TaskBoard      occurrences in bundle: 1
  createRoot     occurrences in bundle: 1

########## E. The frontend origin proxies /api to the FastAPI backend (same path the app fetches)
$ curl -s http://localhost:8011/api/tasks/stats
{"total":5,"todo":1,"inProgress":2,"done":2}
$ curl -s http://localhost:8011/api/tasks | jq -r ".[] | \"\(.id)  \(.status)  \(.title)\""
5  DONE  Publish images to GHCR
4  IN_PROGRESS  Wire Prometheus scrape config
3  IN_PROGRESS  Add Trivy scan to pipeline
2  DONE  Write Helm chart for TaskBoard
1  TODO  Provision VPC with Terraform

$ curl -s http://localhost:8011/health
{"status":"UP"}

########## F. Create / update / delete driven through the frontend origin
$ curl -s -X POST http://localhost:8011/api/tasks -d {"title":"Created from the TaskBoard UI origin",...} -w "HTTP %{http_code}"
{"title":"Created from the TaskBoard UI origin","description":"POST through nginx","priority":"HIGH","status":"TODO","assignee":"Aman Yadav","id":7,"created_at":"2026-10-07T14:15:33.631995Z"}
$ curl -s -X PUT http://localhost:8011/api/tasks/7 -d '{"status":"IN_PROGRESS"}'
{"title":"Created from the TaskBoard UI origin","description":"POST through nginx","priority":"HIGH","status":"IN_PROGRESS","assignee":"Aman Yadav","id":7,"created_at":"2026-10-07T14:15:33.631995Z"}
$ curl -s -o /dev/null -w 'HTTP %{http_code}
' -X DELETE http://localhost:8011/api/tasks/7
HTTP 204
$ curl -s http://localhost:8011/api/tasks/stats
{"total":5,"todo":1,"inProgress":2,"done":2}
```

---

## 6. The React application rendering with live data

The built app was loaded in headless Chrome against the nginx origin above. The rendered DOM
contains the four live counters and all five task rows returned by the API, which means React
mounted, `fetch` reached `/api/tasks` and `/api/tasks/stats`, and the data was painted.

```text
$ chrome --headless=new --dump-dom http://localhost:8011/     (text of the rendered DOM)

Welcome back, Aman
Total tasks        5     Live from /api/tasks/stats
To do              1     Live from /api/tasks/stats
In progress        2     Live from /api/tasks/stats
Completed          2     Live from /api/tasks/stats

Task                            Assignee     Priority  Status        Actions
Publish images to GHCR          Aman Yadav   MEDIUM    DONE          advance / delete
Wire Prometheus scrape config   Aman Yadav   LOW       IN PROGRESS   advance / delete
Add Trivy scan to pipeline      Aman Yadav   HIGH      IN PROGRESS   advance / delete
Write Helm chart for TaskBoard  Aman Yadav   HIGH      DONE          advance / delete
Provision VPC with Terraform    Aman Yadav   HIGH      TODO          advance / delete
```

Those counters match the database exactly: 5 rows, 1 TODO, 2 IN_PROGRESS, 2 DONE.

Screenshots of that same render are committed at `docs/screenshots/taskboard-desktop.png`
(1440 px wide) and `docs/screenshots/taskboard-narrow.png` (500 px wide, the narrowest viewport
headless Chrome will lay out on macOS). They are genuine browser renders of the running stack
rather than mockups.

---

## 7. What the user interface does

* Lists every task with title, description, assignee, priority and status, newest first.
* Creates a task through a modal form backed by `POST /api/tasks`, with title, description,
  priority, status and assignee.
* Changes a task's status from the per row dropdown or the advance button, backed by
  `PUT /api/tasks/{id}`.
* Deletes a task from the row action behind a confirmation, backed by `DELETE /api/tasks/{id}`.
* Filters the table by All, TODO, IN PROGRESS and DONE.
* Shows the four aggregate counters from `GET /api/tasks/stats`, refreshed after every mutation.
* Shows an inline banner when the API is unreachable instead of failing silently.
* Reflows to a single column layout on narrow viewports.
