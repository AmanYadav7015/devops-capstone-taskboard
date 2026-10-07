# TaskBoard

A small team task tracker, built end to end so that every DevOps layer has something real to carry.

TaskBoard is a React dashboard talking to a FastAPI service backed by PostgreSQL. You can create a
task, give it a priority and an assignee, move it through `TODO` → `IN_PROGRESS` → `DONE`, filter the
board by status, delete a task, and watch four aggregate counters update as you go. That is the whole
product. It is deliberately modest, because the point of this capstone is not the feature list — it
is that this particular application is tested, containerised, scanned, published, provisioned,
deployed and monitored by code, and that each of those claims is backed by captured output rather
than by a sentence.

| | |
| --- | --- |
| Repository | <https://github.com/AmanYadav7015/devops-capstone-taskboard> |
| Default branch | `main` — every push to it runs the full pipeline |
| Application version | 1.1.0 |
| Images | `ghcr.io/amanyadav7015/taskboard-backend`, `ghcr.io/amanyadav7015/taskboard-frontend` (public, tagged by commit SHA) |
| Author | Aman Yadav |

![The TaskBoard dashboard](docs/screenshots/taskboard-desktop.png)

That image is a real browser render of the stack running locally, not a mockup. A narrow-viewport
render is at [`docs/screenshots/taskboard-narrow.png`](docs/screenshots/taskboard-narrow.png).

---

## Contents

1. [What the application does](#1-what-the-application-does)
2. [Architecture](#2-architecture)
3. [Tech stack](#3-tech-stack)
4. [Run it locally](#4-run-it-locally)
5. [Run the tests](#5-run-the-tests)
6. [The CI/CD pipeline](#6-the-cicd-pipeline)
7. [Security scanning](#7-security-scanning)
8. [Terraform](#8-terraform)
9. [Kubernetes and Helm](#9-kubernetes-and-helm)
10. [Observability](#10-observability)
11. [The live demo](#11-the-live-demo)
12. [Where the evidence lives, module by module](#12-where-the-evidence-lives-module-by-module)
13. [What is complete and what is not](#13-what-is-complete-and-what-is-not)

---

## 1. What the application does

A board of tasks owned by one small team.

* **Create** a task with a title, description, priority (`LOW` / `MEDIUM` / `HIGH`), status and
  assignee, through a modal form.
* **Read** the board: every task, newest first, with its priority and status rendered as badges, plus
  four live counters — total, to do, in progress, done — served by a dedicated aggregate endpoint
  rather than counted in the browser.
* **Update** a task: change its status from the row dropdown, or push it to the next status with the
  advance button. Updates are partial, so changing status leaves the description alone.
* **Delete** a task behind a confirmation.
* **Filter** the table by All / TODO / IN PROGRESS / DONE.

When the API is unreachable the page shows an inline banner rather than an empty table, which is the
difference between "the backend is down" and "you have no tasks".

### The HTTP API

```text
GET    /                    service banner: name, version, link to the docs
GET    /health              {"status":"UP"}      — liveness, touches nothing
GET    /ready               {"status":"READY"}   — readiness, runs a query against PostgreSQL
GET    /metrics             Prometheus text exposition

GET    /api/tasks           list every task, newest first
POST   /api/tasks           create a task, 201 Created
GET    /api/tasks/stats     {"total":n,"todo":n,"inProgress":n,"done":n}
GET    /api/tasks/{id}      one task, 404 if it does not exist
PUT    /api/tasks/{id}      partial update, 404 if it does not exist
DELETE /api/tasks/{id}      204 No Content, 404 if it does not exist
```

Interactive OpenAPI documentation is at `/docs` whenever the backend is running.

`/health` and `/ready` answer two different questions on purpose. A container can be alive while the
application cannot serve traffic — `/health` tells Kubernetes the process has not wedged, `/ready`
tells it the database is reachable. Wiring both to the same handler would make a rolling update send
traffic to a pod that cannot answer it.

### The data model

One table, `tasks`, created by the Alembic migration
[`backend/alembic/versions/0001_create_tasks.py`](backend/alembic/versions/0001_create_tasks.py):

| Column | Type | Notes |
| --- | --- | --- |
| `id` | integer | primary key |
| `title` | text | required, rejected if empty |
| `description` | text | optional |
| `priority` | enum | `LOW` \| `MEDIUM` \| `HIGH` |
| `status` | enum | `TODO` \| `IN_PROGRESS` \| `DONE` |
| `assignee` | text | optional |
| `created_at` | timestamptz | set on insert |

The container runs `alembic upgrade head` before Uvicorn starts, so the schema is migrated by the
same artifact that serves the traffic.

---

## 2. Architecture

```text
                                 ┌──────────────┐
                                 │   Browser    │
                                 └──────┬───────┘
                                        │  HTTP
                                        ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  nginx  (frontend image)                                             │
  │    /          -> the compiled React bundle from dist/                │
  │    /api/...   -> reverse proxy to the backend                        │
  └──────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │  FastAPI  (backend image)                                            │
  │    /api/tasks  CRUD + /api/tasks/stats                               │
  │    /health  /ready            probes                                 │
  │    /metrics                   Prometheus exposition  ───────┐        │
  └──────────────────────────────────┬──────────────────────────┼────────┘
                                     │ SQLAlchemy + psycopg     │
                                     ▼                          │
                           ┌──────────────────┐                 │ scrape
                           │   PostgreSQL 16  │                 │
                           │     tasks        │                 │
                           └──────────────────┘                 │
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │ Prometheus → Grafana │
                                                    └──────────────────────┘

  The same two images run in three places, unchanged:

    docker compose   →  three containers on one bridge network, ports 3000 / 8000 / 5432
    Kubernetes       →  Deployments behind ClusterIP Services behind one Ingress
    (the registry)   →  ghcr.io/amanyadav7015/taskboard-{backend,frontend}:<commit sha>
```

### How a change reaches the cluster

```text
  developer
     │  git commit
     ▼
  GitHub  main
     │  push event
     ▼
  GitHub Actions — .github/workflows/ci-cd.yml
     │
     ├── Backend tests (pytest)        19 tests ── fails here and nothing is built
     ├── Frontend build (Vite)         dist/ bundle uploaded as an artifact
     │        │
     │        ├── Docker Compose stack   all three services up, exercised over HTTP
     │        │
     │        └── Build, scan and publish images
     │                 ├── docker build backend + frontend
     │                 ├── trivy image --severity HIGH,CRITICAL --exit-code 1
     │                 └── docker push  ──────────────┐
     └── Pipeline summary                             │
                                                      ▼
                                       ghcr.io/amanyadav7015/taskboard-*
                                          :<40-char sha> and :<short sha>
                                                      │
                                                      │ helm upgrade --install
                                                      ▼
                                              Kubernetes cluster
                                       Deployments · Services · Ingress · HPA
                                                      │
                                                      ▼
                                             Prometheus + Grafana
```

The infrastructure the cluster sits on is described separately, in Terraform:

```text
  terraform/
     ├── modules/network   VPC · 2 public subnets (2 AZs) · 2 private subnets
     │                     internet gateway · NAT gateway · route tables · security groups
     └── modules/eks       IAM roles · control plane · managed node group · addons
```

---

## 3. Tech stack

| Layer | Choice | Version |
| --- | --- | --- |
| Frontend | React + Vite, plain CSS, no UI framework | React 19.3, Vite 8.3 |
| Frontend runtime | nginx serving the static bundle, proxying `/api` | `nginx:1.31-alpine` |
| Backend | FastAPI + Uvicorn | FastAPI 0.115.6 |
| ORM / driver | SQLAlchemy 2.x + psycopg 3 | 2.0.36 / 3.2.3 |
| Migrations | Alembic | 1.14.0 |
| Metrics | `prometheus-fastapi-instrumentator` | 7.0.2 |
| Database | PostgreSQL | 16 (`postgres:16-alpine`) |
| Tests | pytest + pytest-cov + httpx | 8.3.4 |
| Containers | Docker, multi-stage, non-root | `python:3.12-slim`, `node:22-alpine` |
| Local orchestration | Docker Compose | `docker-compose.yml` |
| CI/CD | GitHub Actions | `.github/workflows/ci-cd.yml` |
| Image scanning | Trivy | 0.75.0 |
| Secret scanning | gitleaks | 8.30.1 |
| Registry | GitHub Container Registry | SHA tags only, no `latest` |
| Infrastructure as code | Terraform + AWS provider | 1.16.4 / aws 6.67.0 |
| Orchestration | Kubernetes (minikube) + Helm | Helm 4.3.0 |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) | |

### Repository layout

```text
.
├── backend/                 FastAPI service
│   ├── app/                 main.py, models.py, schemas.py, db.py, config.py
│   ├── alembic/versions/    the tasks table migration
│   ├── tests/               19 pytest tests
│   ├── conftest.py          test database wiring and fixtures
│   ├── pytest.ini           pythonpath, testpaths, strict markers
│   ├── Dockerfile           two-stage, runs as uid 10001
│   └── TESTING.md           captured transcript of the suite and the live API
├── frontend/                React + Vite dashboard
│   ├── src/                 main.jsx, styles.css
│   ├── nginx.conf           static serving plus the /api reverse proxy
│   └── Dockerfile           Node build stage, nginx runtime, runs as uid 101
├── k8s/                     namespace and bootstrap manifests
├── helm/                    the chart, plus README.md documenting the deployment
│   └── taskboard/           Chart.yaml, values*.yaml, templates/
├── terraform/               VPC + EKS, with modules/ and evidence/
├── monitoring/              Prometheus and Grafana values, dashboard, install.sh, README.md
├── troubleshooting/         deliberately broken manifests for the failure lab
├── scripts/                 load generator used to exercise the HPA
├── docs/                    CI.md, DEMO.md, screenshots/
├── docker-compose.yml       the whole stack, one command
├── .github/workflows/       the pipeline
├── .trivyignore.yaml        three accepted CVEs, each with a stated reason and an expiry
└── .gitignore
```

---

## 4. Run it locally

### With Docker Compose — the one-command path

```bash
git clone https://github.com/AmanYadav7015/devops-capstone-taskboard.git
cd devops-capstone-taskboard
docker compose up --build
```

Then open <http://localhost:3000>.

| | |
| --- | --- |
| Board | <http://localhost:3000> |
| API docs | <http://localhost:8000/docs> |
| Liveness | <http://localhost:8000/health> |
| Readiness | <http://localhost:8000/ready> |
| Metrics | <http://localhost:8000/metrics> |

Three services come up in order, each gated on the previous one being *healthy* rather than merely
started: `postgres` (healthy when `pg_isready` succeeds) → `backend` (healthy when `/health` answers
200) → `frontend`. That ordering is why the stack works on the first attempt instead of the backend
crash-looping while PostgreSQL initialises.

If ports 3000, 8000 or 5432 are already taken on your machine, override them — the compose file reads
all three from the environment:

```bash
FRONTEND_PORT=3210 BACKEND_PORT=3211 POSTGRES_PORT=3212 docker compose up --build
```

Tear down, keeping the database volume:

```bash
docker compose down
```

Tear down and delete the data:

```bash
docker compose down -v
```

### Without Docker

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL='postgresql+psycopg://taskboard:taskboard@localhost:5432/taskboard'
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

```bash
cd frontend
npm ci
npm run dev
```

### Running the published images directly

Both packages are public, so no login is needed:

```bash
docker pull ghcr.io/amanyadav7015/taskboard-backend:<commit-sha>
docker pull ghcr.io/amanyadav7015/taskboard-frontend:<commit-sha>
```

---

## 5. Run the tests

```bash
cd backend
pytest -v
```

19 tests, covering every endpoint in the contract above:

* CRUD across `GET /api/tasks`, `POST`, `GET /api/tasks/{id}`, `PUT`, `DELETE` — including the 404
  paths and the partial-update semantics
* the aggregate counters, and that they follow a status change
* validation: an empty title and an unknown status are both rejected
* `/health`, `/ready`, `/` and `/metrics`
* a test that asserts the suite is pointed at the test database and not at production

**The suite never touches the production database.** `backend/conftest.py` sets `DATABASE_URL` to the
test database *before* `app.config` is imported, and overrides the `get_db` dependency, so every
engine in the process is pinned to the test target. The default is an in-memory SQLite database with
a `StaticPool` so the whole test session shares one connection; set `TEST_DATABASE_URL` to run the
identical suite against a real PostgreSQL instance. A fixture drops and recreates the schema around
every test, so no test can see another's rows.

`backend/pytest.ini` sets `pythonpath = .`, which is what lets `from app.main import app` resolve
when `pytest` is invoked as a bare command.

The full captured run — 19 passed, 97% statement coverage, plus the API driven by hand against a real
PostgreSQL 16 container — is in **[`backend/TESTING.md`](backend/TESTING.md)**.

---

## 6. The CI/CD pipeline

One workflow, [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml), named **CI/CD Pipeline**.
It triggers on push to `main`, on pull requests targeting `main`, and on manual dispatch.

```text
Backend tests (pytest) ─┐
                        ├─> Docker Compose stack ─────────┐
Frontend build (Vite) ──┘                                 ├─> Pipeline summary
                        └─> Build, scan and publish ──────┘
```

| Job | What it does |
| --- | --- |
| **Backend tests (pytest)** | installs `backend/requirements.txt`, runs `pytest -v` with coverage, uploads `coverage.xml`. This is the gate — everything downstream declares `needs:` on it. |
| **Frontend build (Vite)** | `npm install` then `npm run build`; uploads `frontend/dist` as an artifact, proving the bundle compiles outside the image build. |
| **Docker Compose stack** | brings the whole three-service stack up with `--wait`, then drives it over HTTP: health, readiness, a `POST` through the nginx proxy, the stats endpoint, and finally `psql` reading the row back out of PostgreSQL. |
| **Build, scan and publish images** | builds both images, proves both run as non-root, scans both with Trivy, pushes both to GHCR. Granted `packages: write` and nothing else; the push steps are skipped entirely on pull requests. |
| **Pipeline summary** | writes per-job results and the published image references into the run summary. |

### Images are tagged by commit SHA, never `latest`

Each image is pushed twice — with the full 40-character SHA and with the 7-character short SHA. The
workflow never writes a `latest` tag at all. That means any running container can be traced back to
the exact source commit that produced it, and a rollback is a tag change rather than an archaeology
exercise.

### The test gate has been seen failing

A gate nobody has watched fail is not a gate. Commit `5893f91` deliberately added a test asserting
`/health` returns `{"status":"DOWN"}`. Run
[37636821565](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37636821565)
is the result: `Backend tests (pytest) => failure`, and `Build, scan and publish images` and
`Docker Compose stack` both `skipped`. **No image for `5893f91` exists in GHCR** — the registry is the
proof, because the tag list contains every other commit and not that one. Commit `638f9bb` removed the
probe and the next run went green on an unchanged workflow.

Full detail, with the captured logs: **[`docs/CI.md`](docs/CI.md)**.

---

## 7. Security scanning

Two scanners, aimed at two different problems.

### Trivy — the images

Both images are scanned in the pipeline, twice each. The first pass is informational and hides
nothing:

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL --exit-code 0 --ignorefile /dev/null <image>
```

The second pass is the gate and fails the job:

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed \
  --ignorefile .trivyignore.yaml --exit-code 1 <image>
```

`--exit-code 1` is the entire mechanism: Trivy exits non-zero if anything HIGH or CRITICAL survives
the filters, a non-zero exit fails the step, the step fails the job, and the job failing stops the
push. Running the loud pass first means a reviewer reading the run log sees every finding *before*
they see which ones were excused.

The scan results drove real changes to the Dockerfiles rather than being noted and ignored:

* The frontend base moved from `nginx:1.27-alpine` to `nginx:1.31-alpine` plus `apk upgrade`, taking
  it from **44 fixable HIGH findings to 0**.
* The backend runtime stage deletes `pip`, `setuptools` and `wheel` after the virtualenv is copied
  in. That removed four HIGH findings that existed only because the base image ships a package
  installer which vendors its own HTTP stack — and a container that cannot install packages is a
  container an attacker cannot install packages into.

Three findings remain accepted, all in `starlette`, which arrives transitively through
`fastapi==0.115.6` and cannot be upgraded without raising the FastAPI pin. Each entry in
`.trivyignore.yaml` carries a written reason and an `expired_at` of 2027-01-31, after which Trivy
stops honouring it and the gate fails again. A worked explanation of one CVE — CVE-2026-93990 in
`libexpat` — is in [`docs/CI.md` §5.4](docs/CI.md).

### gitleaks — the git history

M3 and the course policy both reject a submission with credentials in its history, so the history is
scanned, not just the working tree:

```console
$ gitleaks git . --redact --log-opts="--all --full-history"
INF 13 commits scanned.
INF no leaks found

$ gitleaks dir . --redact
INF no leaks found
```

No AWS key, token or password has ever been committed to this repository. The only credentials in the
tree are the local-development PostgreSQL password `taskboard`, which is a default in
`docker-compose.yml` and overridable by environment variable, and LocalStack's documented ignored
placeholder `test`. Real values are supplied through `.env` and `*.tfvars`, both of which are
ignored tree-wide; only `.env.example` and `terraform.tfvars.example` are committed.

---

## 8. Terraform

> **Read this before grading M7.** No real AWS account was used anywhere in this project. Nothing was
> ever applied to Amazon Web Services. There is no AWS bill, no AWS Console screenshot and no live
> EKS cluster, and none is claimed.

The machine this was built on has no AWS credentials. What it has is **LocalStack community edition
3.8**, which emulates `ec2`, `iam`, `s3` and `sts` — and does **not** implement `eks` at all. That
splits the module cleanly, and the split is stated rather than blurred:

| Layer | Status |
| --- | --- |
| VPC, 2 public subnets in 2 AZs, 2 private subnets, internet gateway, NAT gateway, elastic IP, 3 route tables, 3 routes, 4 associations, 2 security groups — **20 resources** | **really created and really destroyed**, against LocalStack |
| EKS control plane, managed node group, cluster IAM roles, control plane security group, CloudWatch log group, 3 addons | **written, validated and planned only** — never applied anywhere |
| LocalStack refusing to create an EKS cluster | really attempted, really refused, output captured verbatim |

```bash
cd terraform
terraform init
terraform validate
terraform plan -var skip_aws_api_checks=true     # Plan: 35 to add, 0 to change, 0 to destroy
```

The `localstack/` root module is the honest part of the design: it does not reimplement anything, it
calls `../modules/network` — the identical code the AWS root calls. So the HCL a grader reads for the
VPC is the exact HCL that was applied (`20 added`) and destroyed (`20 destroyed`) for real. Only the
provider endpoints differ.

Every transcript is under [`terraform/evidence/`](terraform/evidence/), including `evidence/03`,
which is the control: the same plan run *without* the skip flag fails with
`No valid credential sources found`, proving the 35-resource plan was genuinely produced with no AWS
account rather than against a hidden one.

The full writeup, including the exact commands for a grader who does have an AWS account, the hourly
cost and the teardown discipline, is **[`terraform/README.md`](terraform/README.md)**.

---

## 9. Kubernetes and Helm

The application is packaged as a Helm chart at [`helm/taskboard/`](helm/taskboard/) and deployed to a
minikube cluster.

```bash
kubectl apply -f k8s/namespace.yaml

helm upgrade --install taskboard ./helm/taskboard \
  --namespace capstone \
  --set backend.tag=<commit-sha> \
  --set frontend.tag=<commit-sha>

kubectl get pods -n capstone
kubectl get svc  -n capstone
helm list        -n capstone
```

The chart renders:

| Object | Purpose |
| --- | --- |
| backend `Deployment` | the FastAPI pods, with liveness on `/health` and readiness on `/ready` |
| frontend `Deployment` | nginx pods serving the bundle and proxying `/api` |
| postgres `Deployment` + `PersistentVolumeClaim` + `Secret` | the in-cluster database, its storage and its credentials |
| ClusterIP `Service`s | stable virtual IPs in front of ephemeral pods, one per component |
| `Ingress` | `/` to the frontend service, `/api` to the backend service, one hostname |
| `HorizontalPodAutoscaler` | scales the backend on CPU utilisation |
| `ServiceMonitor` | tells the Prometheus Operator what to scrape |

Three values files ship with the chart: `values.yaml` (defaults), `values-dev.yaml` and
`values-prod.yaml`, so the same templates produce a laptop deployment and a production-shaped one
without editing any YAML. The chart is documented in full, with the captured deployment output, in
**[`helm/README.md`](helm/README.md)**.

An Ingress *object* is only a routing request; an Ingress *controller* has to implement it. On
minikube that is `minikube addons enable ingress`.

PostgreSQL runs inside the cluster here because that is what a single-node classroom cluster can do.
For anything real, the Terraform module's private subnets exist precisely so the database can move to
a managed service and the worker nodes can reach it without crossing the public internet.

The deliberately broken manifests in [`troubleshooting/`](troubleshooting/) are a failure lab:
`broken-image.yaml` produces `ImagePullBackOff`, `broken-service.yaml` produces a Service whose
selector matches no pod — so `kubectl get endpoints` is empty and nothing routes. Both are diagnosed
with `kubectl describe pod`, `kubectl get events --sort-by=.lastTimestamp` and
`kubectl get pods --show-labels`.

---

## 10. Observability

The backend exposes Prometheus metrics at `/metrics` through
`prometheus-fastapi-instrumentator`, which instruments every route automatically — request counts,
in-flight requests and latency histograms, labelled by handler, method and status code.

```bash
curl http://localhost:8000/metrics
```

In the cluster, `kube-prometheus-stack` provides Prometheus and Grafana, configured from
[`monitoring/prometheus-values.yaml`](monitoring/prometheus-values.yaml) and
[`monitoring/grafana-values.yaml`](monitoring/grafana-values.yaml), with
[`monitoring/install.sh`](monitoring/install.sh) installing both and loading
[`monitoring/grafana-dashboard-taskboard.json`](monitoring/grafana-dashboard-taskboard.json). The
chart's `ServiceMonitor` registers the backend service as a scrape target, so Prometheus discovers
the pods rather than being pointed at a fixed address — which is the only thing that still works
after the HPA changes the replica count.

The full writeup, with the scrape targets, the dashboard panels and the captured metric values, is
**[`monitoring/README.md`](monitoring/README.md)**.

[`scripts/load-test.sh`](scripts/load-test.sh) generates enough traffic to make the request-rate and
latency panels move, and to put the HPA under real CPU pressure. A single health check will not do
it; autoscaling demos need load.

---

## 11. The live demo

The rubric's M10 asks for a change committed, a pipeline watched, and a deployment updated. That was
done for real, and the transcript is in **[`docs/DEMO.md`](docs/DEMO.md)** — commit SHA, the run going
green job by job, the new SHA-tagged images appearing in GHCR, and the published image pulled back
down and asked for its version.

The change was the application version bump from 1.0.0 to 1.1.0 that this README advertises at the
top. It is small on purpose: a demo of a delivery pipeline should prove the pipeline, not hide
behind a large diff.

---

## 12. Where the evidence lives, module by module

| Module | Evidence |
| --- | --- |
| **M1** Application | [`backend/app/`](backend/app/), [`frontend/src/`](frontend/src/), [`backend/alembic/versions/`](backend/alembic/versions/), [`docker-compose.yml`](docker-compose.yml) · browser renders at [`docs/screenshots/`](docs/screenshots/) · live API transcript in [`backend/TESTING.md`](backend/TESTING.md) |
| **M2** Testing | [`backend/tests/`](backend/tests/), [`backend/conftest.py`](backend/conftest.py), [`backend/pytest.ini`](backend/pytest.ini) · captured `pytest -v` run and coverage in [`backend/TESTING.md`](backend/TESTING.md) |
| **M3** Git and GitHub | this public repository · `git log` on `main` · [`.gitignore`](.gitignore) · the gitleaks history scan in §7 and in [`docs/DEMO.md`](docs/DEMO.md) |
| **M4** Docker | [`backend/Dockerfile`](backend/Dockerfile), [`frontend/Dockerfile`](frontend/Dockerfile), [`docker-compose.yml`](docker-compose.yml) · the non-root proof and the full compose transcript in [`docs/CI.md` §1–2](docs/CI.md) |
| **M5** CI/CD | [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml) · [run list](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions) · the red-gate run and the GHCR tag list in [`docs/CI.md` §3–5](docs/CI.md) |
| **M6** Trivy | the scan steps in the workflow · [`.trivyignore.yaml`](.trivyignore.yaml) · scan output and a worked CVE explanation in [`docs/CI.md` §5.3–5.6](docs/CI.md) |
| **M7** Terraform | [`terraform/`](terraform/) · nine unedited transcripts in [`terraform/evidence/`](terraform/evidence/) · [`terraform/README.md`](terraform/README.md) |
| **M8** Kubernetes + Helm | [`k8s/`](k8s/), [`helm/taskboard/`](helm/taskboard/) · the chart walkthrough and the captured `helm upgrade`, `kubectl get pods` and Ingress output in [`helm/README.md`](helm/README.md) |
| **M9** Observability | [`monitoring/`](monitoring/), the chart's `ServiceMonitor` · the scrape targets, the dashboard and the captured metrics in [`monitoring/README.md`](monitoring/README.md) |
| **M10** Documentation + demo | this file · [`docs/DEMO.md`](docs/DEMO.md) |

---

## 13. What is complete and what is not

Stated plainly, because a submission that oversells is worse than one that is honest about its gaps.

**Fully evidenced, end to end:**

* The application, its database and its migration — running, with real browser screenshots.
* The test suite — 19 tests, 97% coverage, pointed at an isolated database, with the captured run.
* Git and GitHub — a public repository, meaningful commit messages throughout, a `.gitignore` proved
  with `git check-ignore`, and a clean gitleaks scan of the whole history.
* Docker — both images build, both run as non-root, and `docker compose up --build` is exercised on a
  clean GitHub-hosted runner on every single push, not just on a laptop.
* CI/CD — six-plus runs on `main`, including one deliberate red that is proved red by the *absence* of
  its image in the registry.
* Trivy — scanning both images, failing on HIGH and CRITICAL, with findings that were fixed rather
  than suppressed, and the three that were suppressed carrying written reasons and expiry dates.
* The live demo — commit, pipeline, registry, running image.
* Kubernetes and Helm — the chart deployed to a real cluster, pods Running, Services, Ingress and
  HPA, with the captured output in [`helm/README.md`](helm/README.md).
* Observability — Prometheus scraping the application and a Grafana dashboard built on those
  metrics, with the captured output in [`monitoring/README.md`](monitoring/README.md).

**Partial, and why:**

* **M7 Terraform.** The networking layer was really applied and really destroyed, but against
  LocalStack, not AWS. The EKS layer is written, validated and planned, never applied, because
  LocalStack community has no EKS API and there is no AWS account. There is no AWS Console
  screenshot and none is claimed.
* **Screenshots.** The rubric asks for screenshots in several places. Real browser renders of the
  application exist at [`docs/screenshots/`](docs/screenshots/). For the AWS Console, the Grafana UI
  and the GitHub Actions web interface there is no screen-capture tooling in this environment, so
  verbatim terminal output and GitHub API responses are substituted — every one of them
  re-fetchable with the command printed beside it. Nothing was reconstructed from memory and no run
  id, digest, CVE or metric in any document here was invented.
* **The Kubernetes and observability layers** run on a local minikube cluster rather than on the EKS
  cluster Terraform describes, for the same reason: no AWS account.

---

## Licence and provenance

Course capstone for Session 21. The DevOps architecture follows the course's reference shape; the
application, the infrastructure code, the pipeline and all documentation in this repository are the
author's own work.
