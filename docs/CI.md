# Containers, pipeline and image scanning

This document covers three parts of the capstone: how the application is containerised (M4), how the
GitHub Actions pipeline builds, tests and publishes it (M5), and how Trivy gates the images on
HIGH and CRITICAL CVEs (M6).

Everything below is real captured output. Where the rubric asks for a screenshot there is terminal
output or a GitHub Actions log excerpt instead, because this environment has no screen-capture
tooling. No run id, digest, CVE or count in this file was invented; each one can be re-fetched with
the `gh` command shown beside it.

| | |
| --- | --- |
| Repository | <https://github.com/AmanYadav7015/devops-capstone-taskboard> |
| Branch | `main` |
| Workflow | `.github/workflows/ci-cd.yml`, named **CI/CD Pipeline** |
| Runner | `ubuntu-latest`, GitHub-hosted |
| Registry | `ghcr.io/amanyadav7015` |

### The four runs this document refers to

| Run | Commit | Trigger | Result | What it shows |
| --- | --- | --- | --- | --- |
| [37636355888](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37636355888) | `461f7a3` | push to `main` | success | the first full green pipeline |
| [37636813874](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37636813874) | `a4c43f6` | push to `main` | success | a second green pipeline on an unrelated commit |
| [37636821565](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37636821565) | `5893f91` | push to `main` | **failure** | the pytest gate stopping the build |
| [37637249006](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37637249006) | `638f9bb` | push to `main` | success | the gate released again once the test was fixed |

---

## 1. The images

### 1.1 `backend/Dockerfile`

Two stages. The builder stage creates a virtualenv at `/opt/venv` and installs
`backend/requirements.txt` into it. The runtime stage starts from a clean `python:3.12-slim`, copies
only the finished virtualenv, and never sees a compiler or a pip cache.

Three things in the runtime stage are deliberate:

- `apt-get upgrade -y` pulls the current Debian security updates into the layer rather than
  inheriting whatever the base image was built with.
- The `pip`, `setuptools` and `wheel` trees are deleted from both the system interpreter and the
  virtualenv. A running API server has no reason to install packages, and removing the installer
  also removes the packages vendored inside it. That single change took the backend image from seven
  fixable HIGH findings down to three — see section 5.3.
- `USER 10001:10001` is set after every `COPY --chown=10001:10001`, so the application files are
  owned by the account that runs them and nothing in `/app` is writable by a process that does not
  own it.

The container runs `alembic upgrade head` before `uvicorn`, so the schema is migrated on start.
A `HEALTHCHECK` polls `/health` with the standard library, which is what lets Compose and the
pipeline wait for readiness rather than sleeping.

### 1.2 `frontend/Dockerfile`

A multi-stage build exactly as the rubric asks: `node:22-alpine` installs dependencies and runs
`npm run build`, then `nginx:1.31-alpine` serves the resulting `dist/` directory. The Node toolchain,
`node_modules` and the source tree are all left behind in the build stage; only the compiled bundle
is copied forward.

Running nginx as a non-root user needs three adjustments, all of them in the Dockerfile so that
`frontend/nginx.conf` can stay a plain nginx config:

- `setcap cap_net_bind_service=+ep /usr/sbin/nginx` lets an unprivileged process bind port 80.
  `libcap` is added as a virtual package and deleted in the same layer.
- `/var/cache/nginx`, `/var/log/nginx`, `/var/run/nginx.pid`, `/etc/nginx/conf.d` and
  `/usr/share/nginx/html` are chowned to `nginx:nginx`.
- `USER nginx` is uid 101 in the official image.

Keeping port 80 rather than moving to 8080 matters: `helm/taskboard/templates/frontend-service.yaml`
targets port 80 and the frontend Deployment probes port 80, so the capability approach keeps the
Helm chart and the Compose stack serving from the same port.

`apk upgrade --no-cache` runs first. Section 5.4 explains what that fixes.

### 1.3 Both images run as non-root

From the green run [37637249006](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37637249006),
step *Prove both application images run as non-root*:

```text
backend:
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
frontend:
uid=101(nginx) gid=101(nginx) groups=101(nginx),101(nginx)
```

The same check runs again in the publish job against the freshly built images, and it can be
reproduced against the published images without checking anything out:

```console
$ docker run --rm --entrypoint id ghcr.io/amanyadav7015/taskboard-backend:638f9bb
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)

$ docker run --rm --entrypoint id ghcr.io/amanyadav7015/taskboard-frontend:638f9bb
uid=101(nginx) gid=101(nginx) groups=101(nginx),101(nginx)
```

---

## 2. `docker compose up --build`

`docker-compose.yml` defines the three services the rubric asks for — `postgres`, `backend`,
`frontend` — and chains them with health conditions rather than plain `depends_on`:

- `postgres` is healthy when `pg_isready` succeeds.
- `backend` starts only once `postgres` is healthy, and is healthy when `/health` answers 200.
- `frontend` starts only once `backend` is healthy.

That ordering is why the stack comes up correctly on the first attempt instead of the backend
crash-looping while PostgreSQL finishes initialising.

Host ports are `${FRONTEND_PORT:-3000}`, `${BACKEND_PORT:-8000}` and `${POSTGRES_PORT:-5432}`. The
defaults are the ones the rubric expects; the variables exist so the stack can be brought up on a
machine where those ports are already taken.

### 2.1 The stack running in the pipeline

The pipeline has a dedicated `Docker Compose stack` job so this evidence is produced on a clean
machine on every push. From run
[37637249006](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37637249006):

```text
$ docker compose up --build --detach --wait
$ docker compose ps
NAME                IMAGE                               COMMAND                  SERVICE    CREATED          STATUS                    PORTS
capstone-backend    capstone-taskboard-backend:local    "sh -c 'alembic upgr…"   backend    17 seconds ago   Up 11 seconds (healthy)   0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp
capstone-frontend   capstone-taskboard-frontend:local   "/docker-entrypoint.…"   frontend   17 seconds ago   Up 5 seconds (healthy)    0.0.0.0:3000->80/tcp, [::]:3000->80/tcp
capstone-postgres   postgres:16-alpine                  "docker-entrypoint.s…"   postgres   17 seconds ago   Up 16 seconds (healthy)   0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp
```

`--wait` makes the step fail if any service never reaches `healthy`, so a green job means all three
containers really did pass their health checks.

The job then drives the application over HTTP:

```text
$ curl -fsS http://localhost:8000/health
{"status":"UP"}
$ curl -fsS http://localhost:8000/ready
{"status":"READY"}

$ curl -fsS -o /dev/null -w 'frontend HTTP %{http_code}\n' http://localhost:3000/
frontend HTTP 200
$ curl -fsS http://localhost:3000/api/tasks/stats
{"total":0,"todo":0,"inProgress":0,"done":0}

$ curl -fsS -X POST http://localhost:3000/api/tasks -H 'Content-Type: application/json' -d '{...}'
{"title":"Pipeline smoke test","description":"Created by the CI compose job","priority":"HIGH","status":"TODO","assignee":"pipeline","id":1,"created_at":"2026-10-07T14:31:36.866742Z"}
$ curl -fsS http://localhost:3000/api/tasks/stats
{"total":1,"todo":1,"inProgress":0,"done":0}
```

The POST goes to port 3000, which is nginx, not the API. nginx proxies `/api/` to `http://backend:8000`
over the Compose network, so a 201 here proves frontend-to-backend service discovery works. The last
step reads the row straight out of PostgreSQL to prove the write reached the database rather than
some in-memory store:

```text
$ docker compose exec -T postgres psql -U taskboard -d taskboard -c 'select id, title, priority, status, assignee from tasks;'
 id |        title        | priority | status | assignee
----+---------------------+----------+--------+----------
  1 | Pipeline smoke test | HIGH     | TODO   | pipeline
(1 row)
```

The backend log for the same run shows Alembic running before Uvicorn, which is how the `tasks`
table exists at all:

```text
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tasks
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

### 2.2 Running it locally

```console
$ docker compose up --build
```

On a machine where 3000, 8000 or 5432 are already in use, override them:

```console
$ FRONTEND_PORT=3210 BACKEND_PORT=3211 POSTGRES_PORT=3212 docker compose up --build
```

That is how the stack was verified on the development machine, because another project was already
listening on 3000 and 8000. The result was identical to the pipeline's: three healthy containers, a
201 through the nginx proxy, and the row visible in `psql`.

---

## 3. The pipeline

`.github/workflows/ci-cd.yml`, one workflow, five jobs.

```text
backend-tests ─┐
               ├─> compose-stack ──────┐
frontend-build ┘                       ├─> pipeline-summary
               └─> build-scan-publish ─┘
```

| Job | What it does |
| --- | --- |
| `Backend tests (pytest)` | installs `backend/requirements.txt`, runs `pytest -v` with coverage, uploads `coverage.xml` |
| `Frontend build (Vite)` | `npm install` and `npm run build`, uploads `frontend/dist` as an artifact |
| `Docker Compose stack` | the whole stack brought up and exercised, as in section 2 |
| `Build, scan and publish images` | builds both images, scans both with Trivy, pushes both to GHCR |
| `Pipeline summary` | writes the per-job results and the published image references to the run summary |

Triggers:

```yaml
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main
  workflow_dispatch:
```

Push to `main` is the trigger the rubric asks for and is the one every run in the table above used.
The `pull_request` trigger runs the same checks on a proposed change but skips the GHCR login and
push steps, so a fork cannot publish an image. `workflow_dispatch` adds a manual button.

Permissions are `contents: read` for the workflow as a whole; only `build-scan-publish` is granted
`packages: write`, and only for as long as that job runs.

### 3.1 `pythonpath`

`pytest` invoked as a bare command does not add the current directory to `sys.path`, so
`from app.main import app` inside the tests fails with `ModuleNotFoundError`. `backend/pytest.ini`
sets `pythonpath = .`, which is why the `Run pytest` step is a plain `pytest -v` with no
`PYTHONPATH` export in front of it.

### 3.2 Why the image tag is not the application version

`backend/app/main.py` reports `version: "1.0.0"`. The image tag is the commit SHA instead. The two
are deliberately separate: a Docker tag may not contain `+`, so a SemVer build suffix such as
`1.0.0+build.42` is not a legal tag, and more importantly an application version does not change on
every commit while an image must. Tagging by SHA means every image is addressable by the exact
source that produced it.

### 3.3 The owner must be lowercased

`${{ github.repository_owner }}` is `AmanYadav7015`. A Docker reference may not contain uppercase
characters, so `ghcr.io/AmanYadav7015/taskboard-backend` is rejected with `invalid reference format`
before the registry is ever contacted. The `Resolve image references from the commit SHA` step
lowercases it once and every later step uses the step output:

```bash
owner=$(printf '%s' "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
```

---

## 4. The test gate is real

A gate that has never been seen failing is not a gate. Commit `5893f91` deliberately added a test
that asserts the wrong payload:

```python
def test_health_endpoint_reports_down():
    assert client.get("/health").json() == {"status": "DOWN"}
```

Run [37636821565](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37636821565)
is the result. Job conclusions, straight from the API:

```console
$ gh run view 37636821565 --json jobs --jq '.jobs[] | "\(.name) => \(.conclusion)"'
Frontend build (Vite) => success
Backend tests (pytest) => failure
Pipeline summary => success
Build, scan and publish images => skipped
Docker Compose stack => skipped
```

The failure itself:

```text
tests/test_ci_gate_probe.py::test_health_endpoint_reports_down FAILED    [ 75%]
...
=================================== FAILURES ===================================
______________________ test_health_endpoint_reports_down _______________________

    def test_health_endpoint_reports_down():
>       assert client.get("/health").json() == {"status": "DOWN"}
E       AssertionError: assert {'status': 'UP'} == {'status': 'DOWN'}
E
E         Differing items:
E         {'status': 'UP'} != {'status': 'DOWN'}
```

Nineteen tests passed and one failed, and that one failure was enough. `build-scan-publish` and
`compose-stack` both declare `needs: [backend-tests, frontend-build]`, so they were reported
`skipped` without consuming a runner. No image was built and nothing was pushed.

The strongest confirmation is in the registry itself. Listing the tags anonymously after all four
runs, commit `5893f91` is simply absent:

```console
$ curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/amanyadav7015/taskboard-backend/tags/list
{"name":"amanyadav7015/taskboard-backend","tags":["461f7a3bf7b9c04b6d28c8f78efbf4f3dddb3bc0","461f7a3","a4c43f6dd12dbdaf0bca2620ac08866beb0cde2f","a4c43f6","638f9bb66d774f308330aa6837e93f0c37b502f6","638f9bb"]}
```

Three green commits produced six tags. The red commit produced none.

Commit `638f9bb` removed the probe test and run
[37637249006](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37637249006)
went green again on the same pipeline, with no change to the workflow in between:

```text
collecting ... collected 19 items
...
---------- coverage: platform linux, python 3.12.14-final-0 ----------
TOTAL               122      4    97%
======================== 19 passed, 1 warning in 0.44s =========================
```

---

## 5. Publishing and scanning

### 5.1 The frontend really is built in the pipeline

From run [37637249006](https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37637249006),
step *Build the production bundle*:

```text
✓ 15 modules transformed.
dist/index.html                   0.46 kB │ gzip:  0.30 kB
dist/assets/index-CaDU8gDp.css    7.64 kB │ gzip:  2.34 kB
dist/assets/index-CU52_SNU.js   228.39 kB │ gzip: 71.26 kB
✓ built in 145ms
```

The bundle is uploaded as the `frontend-dist` artifact, and the frontend image build runs the same
Vite build again inside its own Node stage so that the image is reproducible from source alone.

### 5.2 GHCR, tagged by commit SHA

Each image is tagged twice, with the full 40-character SHA and with the 7-character short SHA.
Neither is `latest`; the workflow never writes a `latest` tag at all.

```text
$ docker push "ghcr.io/amanyadav7015/taskboard-backend:461f7a3bf7b9c04b6d28c8f78efbf4f3dddb3bc0"
...
461f7a3bf7b9c04b6d28c8f78efbf4f3dddb3bc0: digest: sha256:b037aecd7e1eb34c8015519cba93dec2d40c3b6b4a4d7e7c4928a8aadc9e4f8c size: 2615
```

The digests published by the latest green run:

```text
ghcr.io/amanyadav7015/taskboard-backend@sha256:300c67b0ab723bdb03e4168548476c761f8b30ff3fc34d6f0051c8f6b696bae2
ghcr.io/amanyadav7015/taskboard-frontend@sha256:e1ac3aa43a6d4e8d164c37da447eb79c14aab54d44ff86f0d97da22dcd1cba4a
```

Both packages are public, so the published images can be verified from any machine with no
credentials at all:

```console
$ docker pull ghcr.io/amanyadav7015/taskboard-backend:638f9bb66d774f308330aa6837e93f0c37b502f6
...
Status: Downloaded newer image for ghcr.io/amanyadav7015/taskboard-backend:638f9bb66d774f308330aa6837e93f0c37b502f6
```

Package pages:

- <https://github.com/users/AmanYadav7015/packages/container/package/taskboard-backend>
- <https://github.com/users/AmanYadav7015/packages/container/package/taskboard-frontend>

### 5.3 The Trivy gate

Both images are scanned, in two passes each.

The first pass is informational and hides nothing:

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL --exit-code 0 --ignorefile /dev/null <image>
```

The second pass is the gate and fails the job:

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed \
  --ignorefile .trivyignore.yaml --exit-code 1 <image>
```

`--exit-code 1` is the whole gate: Trivy returns 1 when anything matching `--severity HIGH,CRITICAL`
survives the filters, and a non-zero exit fails the step, which fails the job, which stops the push.

`--ignore-unfixed` drops findings for which no patched package exists yet. Without it the backend
image fails permanently for reasons nobody can act on — the informational pass on run
`37637249006` reported:

```text
ghcr.io/amanyadav7015/taskboard-backend:638f9bb... (debian 13.7)
Total: 44 (HIGH: 44, CRITICAL: 0)
```

Every one of those 44 is a Debian 13 base package — `util-linux`, `ncurses`, `systemd`, `perl`,
`libacl1` — carrying a status of `affected`, `fix_deferred` or `will_not_fix`. There is no newer
`.deb` to install, so failing the build on them would only teach the team to ignore the gate.
Whenever Debian does ship a fix, `apt-get upgrade -y` in the Dockerfile picks it up and the
`--ignore-unfixed` filter stops applying to it automatically.

### 5.4 One CVE, explained: CVE-2026-93990 in libexpat

The frontend image reports a clean scan today. It did not start that way, and the reason is worth
writing down.

The starter's base image, `nginx:1.27-alpine`, is Alpine 3.21.3 and reports **44 HIGH findings, every
one of them with status `fixed`** — a patched Alpine package already exists for all of them. These are
exactly the findings a gate is right to block on, and they are concentrated in a handful of packages:
`libcrypto3`/`libssl3` (11 each, 3.3.3-r0 against a fixed 3.3.7-r2), `libexpat` (7), `libpng` (6),
`libxml2` (6), plus `musl`, `nghttp2-libs`, `zlib` and `c-ares`.

Moving the runtime stage to `nginx:1.31-alpine` (Alpine 3.24.2) takes that from 44 down to 2:

| Package | CVE | Installed | Fixed in |
| --- | --- | --- | --- |
| `libexpat` | CVE-2026-93990 | 2.8.4-r0 | 2.8.5-r0 |
| `pcre2` | CVE-2026-103111 | 10.48-r0 | 10.49-r0 |

Both are still blocking, and the clearer of the two is worth spelling out:

**CVE-2026-93990 — XML injection via malformed UTF-16 input in Expat.**
Severity HIGH. Affected package `libexpat`, installed at `2.8.4-r0`, fixed in `2.8.5-r0`. Expat is
the C XML parser that ships inside the nginx Alpine image as a transitive dependency. A document
crafted with malformed UTF-16 sequences can be parsed in a way that injects structure the author of
the document did not write, so a consumer downstream sees different XML than the parser was handed.
The exposure in this image is small — nginx serves a static React bundle and proxies JSON, so no
attacker-controlled XML reaches Expat — but "probably unreachable" is not a patch, and a fixed
version existed.

The fix is one line at the top of the runtime stage:

```dockerfile
RUN apk upgrade --no-cache \
 && apk add --no-cache --virtual .build-deps libcap \
 ...
```

`apk upgrade` installs the current Alpine packages into the image layer instead of inheriting
whatever was current when the base image was published. After that change, the gate reports:

```text
Report Summary

┌──────────────────────────────────────────────────────────────────────────────────┬────────┬─────────────────┐
│                                      Target                                      │  Type  │ Vulnerabilities │
├──────────────────────────────────────────────────────────────────────────────────┼────────┼─────────────────┤
│ ghcr.io/amanyadav7015/taskboard-frontend:638f9bb... (alpine 3.24.2)               │ alpine │        0        │
└──────────────────────────────────────────────────────────────────────────────────┴────────┴─────────────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)
```

Zero here is the honest kind of zero: the informational pass, which applies no `--ignore-unfixed`
and no ignore file, reports zero for this image too. The 71 Alpine packages in the frontend image
have no known HIGH or CRITICAL vulnerability at the time of the scan. That is a statement about
today's database, not a permanent property — Trivy's database updates daily, and a scan next week
may find something that does not exist today. The value of running it on every push is precisely
that the answer is re-asked every time.

The backend image is in the same position for its OS layer: 0 findings after `--ignore-unfixed`,
with the 44 unfixed Debian findings listed in full by the informational pass.

### 5.5 The three accepted findings

`.trivyignore.yaml` holds three entries, all for the same package:

| CVE | Package | Installed | Fixed in |
| --- | --- | --- | --- |
| CVE-2025-62727 | `starlette` | 0.41.3 | 0.49.1 |
| CVE-2026-48818 | `starlette` | 0.41.3 | 1.1.0 |
| CVE-2026-54283 | `starlette` | 0.41.3 | 1.3.1 |

Starlette is not a direct dependency. It arrives through `fastapi==0.115.6`, whose own metadata
requires `starlette>=0.40.0,<0.42.0`, so none of the three fixed versions can be installed without
raising the FastAPI pin — and installing Starlette 1.x under FastAPI 0.115 would produce an
application that does not run. The honest fix is a FastAPI upgrade (0.142.2 requires
`starlette>=0.46.0` and resolves all three), not a Dockerfile trick.

Until that upgrade lands, each entry in `.trivyignore.yaml` carries a `statement` recording why the
finding is accepted and an `expired_at` date of 2027-01-31, after which Trivy stops honouring it and
the gate fails again. The reasoning per CVE is in the file; in summary, all three are reachable only
through `StaticFiles` or `request.form()`, and this backend mounts no `StaticFiles` route and parses
every request body through Pydantic JSON models.

Trivy announces the suppression in the gate log rather than hiding it:

```text
INFO	Some vulnerabilities have been ignored/suppressed. Use the "--show-suppressed" flag to display them.
```

and the informational pass immediately above it prints all three in full, so a reviewer reading the
run log sees the findings before they see the exception.

### 5.6 Where the suppression was *not* needed

Before the Dockerfile hardening, the backend image reported seven fixable HIGH findings, not three.
The other four were:

| Package | CVE | Where it came from |
| --- | --- | --- |
| `setuptools` 70.3.0 | CVE-2025-47273 | the base image's system interpreter |
| `urllib3` 2.7.0 | CVE-2026-97687, CVE-2026-97689 | vendored inside `pip` |
| `msgpack` 1.1.2 | GHSA-6v7p-g79w-8964 | vendored inside `pip` |

None of them is imported by the application. They exist because the base image ships a package
installer and `pip` vendors its own HTTP stack. Deleting `pip`, `setuptools` and `wheel` from the
runtime stage removed all four findings and shrank the attack surface at the same time — a container
that cannot install packages is a container an attacker cannot install packages into. Suppressing
them in `.trivyignore.yaml` would have been faster and worse.

---

## 6. Reproducing all of it

```console
$ docker compose up --build                     # the whole stack, section 2
$ docker compose ps                             # three services, all healthy
$ docker run --rm --entrypoint id ghcr.io/amanyadav7015/taskboard-backend:638f9bb
$ docker run --rm --entrypoint id ghcr.io/amanyadav7015/taskboard-frontend:638f9bb

$ cd backend && pytest -v                       # 19 tests

$ gh run list  --repo AmanYadav7015/devops-capstone-taskboard
$ gh run view  37636821565 --repo AmanYadav7015/devops-capstone-taskboard --log-failed
$ gh run view  37637249006 --repo AmanYadav7015/devops-capstone-taskboard --log

$ trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed \
    --ignorefile .trivyignore.yaml --exit-code 1 \
    ghcr.io/amanyadav7015/taskboard-backend:638f9bb66d774f308330aa6837e93f0c37b502f6
```
