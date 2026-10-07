# The live demo, and the state of the git history

Two things live here, both captured rather than described.

* **[Part 1](#part-1--the-live-demo)** is the M10 live demo: one real commit, pushed to `main`,
  the pipeline watched from queued to green, the new SHA-tagged images appearing in GHCR, and the
  published image pulled back down and asked what version it serves.
* **[Part 2](#part-2--the-git-history)** is the M3 evidence: the commit log, the `.gitignore`
  proved with `git check-ignore`, and a secret scan of the entire history rather than of the
  working tree.

Everything below is verbatim terminal output. Every run id, SHA and digest can be re-fetched with
the command printed beside it.

---

# Part 1 — the live demo

The chain the rubric asks for, in four links:

```text
  commit 864a1e1                       a real change, pushed to main
        │
        ▼
  run 37641802660                      the pipeline, watched live, five jobs, all green
        │
        ▼
  ghcr.io/amanyadav7015/taskboard-*    two new images, tagged with that commit's SHA
    :864a1e1b0c9b...                   and with nothing else
        │
        ▼
  docker run <that image>              and it serves version 1.1.0, where the previous
  curl /                               image serves 1.0.0
```

## 1. The change

The application version, bumped from 1.0.0 to 1.1.0. Small on purpose: a demonstration of a
delivery pipeline should prove the pipeline, not hide behind a large diff. It is also a change that
can be *observed from the outside* — `GET /` and the OpenAPI document both report the version, so the
running container can be asked whether it really is the new build.

```console
$ git log -1 --stat
commit 864a1e1b0c9b42fb30ca630f9dd80a6387c899d4
Author: Aman Yadav <177647392+AmanYadav7015@users.noreply.github.com>
Date:   Wed Oct 7 20:32:51 2026 +0530

    Release TaskBoard 1.1.0: bump the API version served by the root banner

 backend/app/main.py          | 4 ++--
 backend/tests/test_health.py | 2 +-
 frontend/package.json        | 2 +-
 3 files changed, 4 insertions(+), 4 deletions(-)
```

The diff:

```diff
-app = FastAPI(title=settings.app_name, version="1.0.0", lifespan=lifespan)
+app = FastAPI(title=settings.app_name, version="1.1.0", lifespan=lifespan)

-    return {"service": settings.app_name, "version": "1.0.0", "docs": "/docs"}
+    return {"service": settings.app_name, "version": "1.1.0", "docs": "/docs"}

-    assert response.json()["version"] == "1.0.0"
+    assert response.json()["version"] == "1.1.0"

-  "version": "1.0.0",
+  "version": "1.1.0",
```

The test assertion moves with the code deliberately. If the version had been bumped in `main.py`
alone, the existing banner test would have gone red and the pipeline would have refused to publish —
which is the gate working. Moving both together is what a real release commit looks like.

Checked locally before pushing anything:

```console
$ cd backend && pytest -q
...................                                                      [100%]
19 passed, 1 warning in 0.13s
```

## 2. The push

```console
$ git push origin main
To https://github.com/AmanYadav7015/devops-capstone-taskboard.git
   d378da5..864a1e1  main -> main
```

## 3. Watching the pipeline

```console
$ gh run watch 37641802660 --repo AmanYadav7015/devops-capstone-taskboard --exit-status
Refreshing run status every 10 seconds. Press Ctrl+C to quit.

* main CI/CD Pipeline · 37641802660
Triggered via push less than a minute ago
...
✓ main CI/CD Pipeline · 37641802660
Triggered via push about 2 minutes ago

JOBS
✓ Backend tests (pytest) in 16s (ID 112862817901)
✓ Frontend build (Vite) in 9s (ID 112862818383)
✓ Docker Compose stack in 52s (ID 112862974779)
✓ Build, scan and publish images in 57s (ID 112862974846)
✓ Pipeline summary in 4s (ID 112863446365)
```

`gh run watch --exit-status` exits non-zero if the run fails, so the command returning 0 is itself an
assertion that the run went green. It did.

```console
$ gh run view 37641802660 --json databaseId,displayTitle,headSha,status,conclusion,event,url,createdAt,updatedAt
run        37641802660
title      Release TaskBoard 1.1.0: bump the API version served by the root banner
commit     864a1e1b0c9b42fb30ca630f9dd80a6387c899d4
event      push
status     completed
conclusion success
started    2026-10-07T15:03:01Z
finished   2026-10-07T15:05:16Z
url        https://github.com/AmanYadav7015/devops-capstone-taskboard/actions/runs/37641802660

$ gh run view 37641802660 --json jobs --jq '.jobs[] | "\(.conclusion|ascii_upcase)  \(.name)"'
SUCCESS  Backend tests (pytest)          (15:03:52Z -> 15:04:08Z)
SUCCESS  Frontend build (Vite)           (15:03:52Z -> 15:04:01Z)
SUCCESS  Docker Compose stack            (15:04:11Z -> 15:05:03Z)
SUCCESS  Build, scan and publish images  (15:04:11Z -> 15:05:08Z)
SUCCESS  Pipeline summary                (15:05:11Z -> 15:05:15Z)
```

Two minutes fifteen seconds from push to published images, including the full Compose stack coming up
and both images being scanned.

### 3.1 What each job actually did on this run

All of the following is from `gh run view 37641802660 --log`, with the job/step/timestamp prefix
stripped for readability.

**Backend tests (pytest)** — the gate. The version assertion that would have failed on a stale build
is the one marked at 89%:

```text
tests/test_health.py::test_health_endpoint_reports_up PASSED             [ 78%]
tests/test_health.py::test_ready_endpoint_queries_the_database PASSED    [ 84%]
tests/test_health.py::test_root_returns_the_service_banner PASSED        [ 89%]
tests/test_health.py::test_metrics_endpoint_exposes_prometheus_text PASSED [ 94%]
tests/test_health.py::test_suite_runs_against_the_test_database_not_production PASSED [100%]

---------- coverage: platform linux, python 3.12.14-final-0 ----------
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

======================== 19 passed, 1 warning in 0.28s =========================
```

**Frontend build (Vite)** — the bundle really is compiled in the pipeline, not just inside the image:

```text
✓ 15 modules transformed.
dist/index.html                   0.46 kB │ gzip:  0.30 kB
dist/assets/index-CaDU8gDp.css    7.64 kB │ gzip:  2.34 kB
dist/assets/index-CU52_SNU.js   228.39 kB │ gzip: 71.26 kB
✓ built in 123ms
```

**Docker Compose stack** — the whole three-service stack on a clean runner, then driven over HTTP and
finally read back out of PostgreSQL:

```text
$ curl -fsS http://localhost:8000/health
{"status":"UP"}
$ curl -fsS http://localhost:8000/ready
{"status":"READY"}

$ curl -fsS -o /dev/null -w 'frontend HTTP %{http_code}\n' http://localhost:3000/
frontend HTTP 200
$ curl -fsS http://localhost:3000/api/tasks/stats
{"total":0,"todo":0,"inProgress":0,"done":0}

$ curl -fsS -X POST http://localhost:3000/api/tasks -d '{"title":"Pipeline smoke test",...}'
{"title":"Pipeline smoke test","description":"Created by the CI compose job","priority":"HIGH","status":"TODO","assignee":"pipeline","id":1,"created_at":"2026-10-07T15:04:59.610866Z"}
$ curl -fsS http://localhost:3000/api/tasks/stats
{"total":1,"todo":1,"inProgress":0,"done":0}

$ docker compose exec -T postgres psql -U taskboard -d taskboard -c 'select id, title, priority, status, assignee from tasks;'
 id |        title        | priority | status | assignee
----+---------------------+----------+--------+----------
  1 | Pipeline smoke test | HIGH     | TODO   | pipeline
(1 row)
```

The `POST` goes to port 3000, which is nginx rather than the API, so a 201 there proves the proxy and
the service-to-service networking as well as the endpoint.

**Build, scan and publish images** — the Trivy gate, which has `--exit-code 1` and therefore had to
pass for anything to be pushed:

```text
INFO  Detected OS  family="alpine" version="3.24.2"
INFO  [alpine] Detecting vulnerabilities...  os_version="3.24" repository="3.24" pkg_num=71

Report Summary

┌──────────────────────────────────────────────────────────────────────────────────┬────────┬─────────────────┐
│                                      Target                                      │  Type  │ Vulnerabilities │
├──────────────────────────────────────────────────────────────────────────────────┼────────┼─────────────────┤
│ ghcr.io/amanyadav7015/taskboard-frontend:864a1e1b0c9b42fb30ca630f9dd80a6387c899- │ alpine │        0        │
│ d4 (alpine 3.24.2)                                                               │        │                 │
└──────────────────────────────────────────────────────────────────────────────────┴────────┴─────────────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)
```

## 4. The images appear in GHCR, tagged with this commit

Both pushes, with their digests:

```text
$ docker push "ghcr.io/amanyadav7015/taskboard-backend:864a1e1b0c9b42fb30ca630f9dd80a6387c899d4"
864a1e1b0c9b42fb30ca630f9dd80a6387c899d4: digest: sha256:a1aec7cad67c06cb7cde2338e1bacb8351b2f3a26c52c43418320c18e433a267 size: 2615
$ docker push "ghcr.io/amanyadav7015/taskboard-backend:864a1e1"
864a1e1: digest: sha256:a1aec7cad67c06cb7cde2338e1bacb8351b2f3a26c52c43418320c18e433a267 size: 2615
$ docker push "ghcr.io/amanyadav7015/taskboard-frontend:864a1e1b0c9b42fb30ca630f9dd80a6387c899d4"
864a1e1b0c9b42fb30ca630f9dd80a6387c899d4: digest: sha256:feb9bd6c9265541efce48ca0ea6df75f2f95b50aaa919d20163942265eafdb0d size: 2616
$ docker push "ghcr.io/amanyadav7015/taskboard-frontend:864a1e1"
864a1e1: digest: sha256:feb9bd6c9265541efce48ca0ea6df75f2f95b50aaa919d20163942265eafdb0d size: 2616
```

The registry's own tag list, fetched **anonymously** — no `docker login`, no GitHub token, because
both packages are public:

```console
$ TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:amanyadav7015/taskboard-backend:pull&service=ghcr.io" | jq -r .token)
$ curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/amanyadav7015/taskboard-backend/tags/list
{
    "name": "amanyadav7015/taskboard-backend",
    "tags": [
        "461f7a3bf7b9c04b6d28c8f78efbf4f3dddb3bc0", "461f7a3",
        "a4c43f6dd12dbdaf0bca2620ac08866beb0cde2f", "a4c43f6",
        "638f9bb66d774f308330aa6837e93f0c37b502f6", "638f9bb",
        "13fc94b97ac9429277e6050b09e04a08ffd89cb3", "13fc94b",
        "d378da5adccc22d71587a9de87eebff2606a156f", "d378da5",
        "864a1e1b0c9b42fb30ca630f9dd80a6387c899d4", "864a1e1"
    ]
}
```

(Reformatted onto several lines; the response is a single JSON array.) The frontend list is
identical. Three things are worth reading out of it:

* `864a1e1...` is there, and it was not there before this run — the before-and-after captures are
  `01-baseline` and `06-ghcr-after` in the transcript set this document was assembled from.
* every tag is a commit SHA. There is no `latest`, and the workflow never writes one.
* `5893f91`, the commit that deliberately failed the test gate, **is absent**. Six green commits,
  twelve tags, and nothing at all for the red one. That is the gate, evidenced by the registry
  rather than by a log line.

## 5. The deployment updates

The last link: pull the image the pipeline just published and ask it what it is. For contrast, the
image published for the *previous* commit is started first.

```console
$ docker run -d --name capstone-demo-before \
    -e DATABASE_URL=postgresql+psycopg://taskboard:***@capstone-demo-db:5432/taskboard \
    -p 38001:8000 \
    ghcr.io/amanyadav7015/taskboard-backend:d378da5adccc22d71587a9de87eebff2606a156f
$ curl -s http://localhost:38001/
{"service":"TaskBoard API","version":"1.0.0","docs":"/docs"}

$ docker run -d --name capstone-demo-after \
    -e DATABASE_URL=postgresql+psycopg://taskboard:***@capstone-demo-db:5432/taskboard \
    -p 38002:8000 \
    ghcr.io/amanyadav7015/taskboard-backend:864a1e1b0c9b42fb30ca630f9dd80a6387c899d4
$ curl -s http://localhost:38002/
{"service":"TaskBoard API","version":"1.1.0","docs":"/docs"}

$ curl -s http://localhost:38002/health
{"status":"UP"}
$ curl -s http://localhost:38002/ready
{"status":"READY"}

$ curl -s http://localhost:38002/openapi.json | jq .info
{
  "title": "TaskBoard API",
  "version": "1.1.0"
}

$ docker run --rm --entrypoint id ghcr.io/amanyadav7015/taskboard-backend:864a1e1b0c9b...
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
```

`1.0.0` before, `1.1.0` after, from two images neither of which was built on this machine. Nothing
was copied, mounted or edited between the commit and that response: the source went to GitHub, the
pipeline built it, the registry stored it, and the registry's copy is what answered. `/ready`
returning `READY` means the container also migrated the schema with Alembic and reached PostgreSQL on
startup, so this is a working deployment and not just a process that boots.

That is the complete M10 chain — **commit → pipeline → registry → running deployment**.

## 6. Reproducing it

```bash
gh run view 37641802660 --repo AmanYadav7015/devops-capstone-taskboard --log
gh run view 37641802660 --repo AmanYadav7015/devops-capstone-taskboard --json jobs \
  --jq '.jobs[] | "\(.conclusion) \(.name)"'

docker pull ghcr.io/amanyadav7015/taskboard-backend:864a1e1b0c9b42fb30ca630f9dd80a6387c899d4
docker run --rm --entrypoint id ghcr.io/amanyadav7015/taskboard-backend:864a1e1
```

---

# Part 2 — the git history

## 7. The repository

| | |
| --- | --- |
| URL | <https://github.com/AmanYadav7015/devops-capstone-taskboard> |
| Visibility | **public** — verified with `gh repo view --json visibility` |
| Default branch | `main` |
| Commits on `main` | 17 at the time of this demo |
| Author and committer on every commit | `Aman Yadav <177647392+AmanYadav7015@users.noreply.github.com>` |

```console
$ gh repo view AmanYadav7015/devops-capstone-taskboard --json visibility,isPrivate,defaultBranchRef
{"defaultBranchRef":{"name":"main"},"isPrivate":false,"visibility":"PUBLIC"}

$ git log --format='%an <%ae>' | sort -u
Aman Yadav <177647392+AmanYadav7015@users.noreply.github.com>
$ git log --format='%cn <%ce>' | sort -u
Aman Yadav <177647392+AmanYadav7015@users.noreply.github.com>
```

One identity, author and committer, on every commit. No work email and no second account leaked into
the history.

## 8. The commit log

The rubric asks for at least ten commits with meaningful messages — not `update`, `fix` or `test`.
Here is every one of them, oldest first. Each describes what the commit does and why, and each is a
coherent unit of work rather than a snapshot of whatever happened to be on disk.

| Commit | Message |
| --- | --- |
| `6c8d099` | Ignore build output, Python caches, virtualenvs, local env files and Terraform state |
| `95001c1` | Add FastAPI TaskBoard backend with PostgreSQL models, Alembic migration and pytest suite |
| `4629541` | Add React TaskBoard dashboard served by nginx with an /api reverse proxy |
| `c5a60b6` | Containerise both services with multi-stage builds that run as non-root users |
| `ac4220d` | Add a Docker Compose stack that gates backend and frontend startup on health checks |
| `11c1456` | Add the GitHub Actions pipeline: pytest gate, image build, Trivy scan and GHCR publish |
| `bf6a10b` | Add the Kubernetes namespace and the TaskBoard Helm chart |
| `fcac4f2` | Add the Terraform VPC and EKS modules with LocalStack verification evidence |
| `ebc4f43` | Add Prometheus values, a load generator and the troubleshooting exercises |
| `461f7a3` | Add the project README |
| `a4c43f6` | Correct the Terraform README: state plainly that no real AWS account was used |
| `5893f91` | Add a temporary probe test that asserts the wrong health payload to exercise the pipeline test gate |
| `638f9bb` | Remove the temporary pipeline gate probe test now that the gate has been verified |
| `13fc94b` | Document the container images, the pipeline and the Trivy gate with captured run output |
| `bd016c8` | Extend the ignore rules to Terraform plan files and every tfvars variant |
| `d378da5` | Add the backend verification log and the two browser screenshots of the running board |
| `864a1e1` | Release TaskBoard 1.1.0: bump the API version served by the root banner |

The history has not been rewritten, squashed or force-pushed. `5893f91` and `638f9bb` are the
deliberate red/green pair that proved the test gate, and they are left in place on purpose: deleting
them would have deleted the evidence.

## 9. `.gitignore`, proved rather than asserted

M3 names four things that must be excluded. Rather than claim the file covers them, here is git's own
answer, which also names the rule and line number that matched:

```console
$ git check-ignore -v .env
.gitignore:26:.env	.env
$ git check-ignore -v backend/.env
.gitignore:26:.env	backend/.env
$ git check-ignore -v backend/app/__pycache__/main.cpython-312.pyc
.gitignore:11:__pycache__/	backend/app/__pycache__/main.cpython-312.pyc
$ git check-ignore -v frontend/node_modules/react/index.js
.gitignore:6:node_modules/	frontend/node_modules/react/index.js
$ git check-ignore -v .venv/bin/python
.gitignore:20:.venv/	.venv/bin/python
$ git check-ignore -v backend/.venv/lib/python3.12/site-packages/x
.gitignore:20:.venv/	backend/.venv/lib/python3.12/site-packages/x
```

The rubric's four are covered, and so is everything that could carry a credential into the history:

```console
$ git check-ignore -v terraform/terraform.tfstate
terraform/.gitignore:2:*.tfstate	terraform/terraform.tfstate
$ git check-ignore -v terraform/terraform.tfstate.backup
terraform/.gitignore:3:*.tfstate.*	terraform/terraform.tfstate.backup
$ git check-ignore -v terraform/localstack/terraform.tfstate
terraform/.gitignore:2:*.tfstate	terraform/localstack/terraform.tfstate
$ git check-ignore -v terraform/.terraform/providers/x
terraform/.gitignore:1:.terraform/	terraform/.terraform/providers/x
$ git check-ignore -v terraform/plan.tfplan
terraform/.gitignore:4:*.tfplan	terraform/plan.tfplan
$ git check-ignore -v terraform/terraform.tfvars
terraform/.gitignore:14:*.tfvars	terraform/terraform.tfvars
$ git check-ignore -v infra/prod.tfvars
.gitignore:36:*.tfvars	infra/prod.tfvars
$ git check-ignore -v terraform/secrets.tfvars.json
terraform/.gitignore:15:*.tfvars.json	terraform/secrets.tfvars.json
```

`*.tfvars` is ignored tree-wide, not just under `terraform/`, because a hand-written variables file
is the single most likely place for a real AWS key to end up. The example files are negated so they
still ship:

```console
$ git check-ignore -v terraform/terraform.tfvars.example   # no output, exit 1
$ git check-ignore -v backend/.env.example                 # no output, exit 1
```

And nothing that *is* ignored has been committed by accident:

```console
$ git ls-files | git check-ignore --stdin -v
                                                  (no output — clean)
```

## 10. No secrets in the history

A working-tree scan is not enough: a credential removed in a later commit is still in the history,
and the course policy rejects a submission on that basis. So the scan covers every commit on every
ref.

```console
$ gitleaks version
8.30.1

$ gitleaks git . --redact --log-opts="--all --full-history"

    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

INF 13 commits scanned.
INF scanned ~326160 bytes (326.16 KB) in 83.7ms
INF no leaks found
```

```console
$ gitleaks dir . --redact
INF scanned ~646276 bytes (646.28 KB) in 200ms
INF no leaks found
```

Clean in both directions — the full history and the current working tree, untracked files included.
(gitleaks counts the commits it diffed, which is one fewer than `git rev-list --count` because the
root commit has no parent to diff against; the root commit's content is covered by the directory scan
above.)

The only credentials anywhere in the tree are deliberately worthless:

| Where | Value | Why it is safe |
| --- | --- | --- |
| `docker-compose.yml` | `taskboard` | the local PostgreSQL password, a `${POSTGRES_PASSWORD:-taskboard}` default, overridable by environment variable |
| `helm/taskboard/values.yaml` | `taskboard` | the same, for the in-cluster development database |
| `terraform/localstack/versions.tf` | `test` | the literal placeholder LocalStack documents and ignores |

Real values are supplied through `.env` and `*.tfvars`, both ignored tree-wide. Only `.env.example`
and `terraform.tfvars.example` are committed, and neither contains a value.

GHCR authentication in the pipeline uses the automatically provisioned `GITHUB_TOKEN`, scoped to
`packages: write` on one job only. There is no long-lived registry credential stored anywhere in this
repository.

---

## Part 3 — The chain reaches the cluster

Parts 1 and 2 ended at the registry. This closes the loop: the image the pipeline published is now
the image the Kubernetes cluster is actually serving.

The cluster was running `13fc94b97ac9429277e6050b09e04a08ffd89cb3`, which serves version 1.0.0:

```bash
kubectl exec -n capstone deploy/taskboard-backend -- \
  python -c "import urllib.request,json;print(json.load(urllib.request.urlopen('http://localhost:8000/')))"
```

```text
{'service': 'TaskBoard API', 'version': '1.0.0', 'docs': '/docs'}
```

Roll the release forward to the tag the pipeline built from commit `864a1e1`:

```bash
helm upgrade taskboard helm/taskboard -n capstone --reset-values \
  --set backend.tag=864a1e1b0c9b42fb30ca630f9dd80a6387c899d4 \
  --set frontend.tag=864a1e1b0c9b42fb30ca630f9dd80a6387c899d4
kubectl rollout status deploy/taskboard-backend -n capstone
kubectl rollout status deploy/taskboard-frontend -n capstone
```

```text
REVISION: 10
STATUS: deployed
deployment "taskboard-backend" successfully rolled out
deployment "taskboard-frontend" successfully rolled out
```

The Deployment now references the published image, and the running container reports the new version:

```bash
kubectl get deploy taskboard-backend -n capstone -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl exec -n capstone deploy/taskboard-backend -- \
  python -c "import urllib.request,json;print(json.load(urllib.request.urlopen('http://localhost:8000/')))"
```

```text
ghcr.io/amanyadav7015/taskboard-backend:864a1e1b0c9b42fb30ca630f9dd80a6387c899d4
{'service': 'TaskBoard API', 'version': '1.1.0', 'docs': '/docs'}
```

Served through the Ingress, with the data intact across the rollout:

```bash
minikube ssh -- "curl -s -H 'Host: taskboard.local' http://192.168.49.2/api/tasks/stats"
```

```text
{"total":1813,"todo":1812,"inProgress":1,"done":0}
```

The full chain is therefore: a source commit, a pipeline run that tests and scans it, an image
published to GHCR under that commit's SHA, and a Kubernetes rollout serving that exact image —
with no step asserted rather than shown.

### A note on the upgrade command

The first two attempts used `--set backend.image.tag=...`, but this chart's values are
`backend.image` (repository) and `backend.tag` (tag) as separate keys, so that produced a malformed
reference and the pods failed with `InvalidImageName`:

```text
Failed to apply default image tag "map[tag:864a1e1b...]:13fc94b9...":
couldn't parse image name: invalid reference format
```

The second attempt also used `--reuse-values`, which carried the bad override forward. Rolling back
to the last good revision and upgrading with `--reset-values` fixed it. Worth knowing: `--reuse-values`
preserves mistakes as faithfully as it preserves intent.
