# TaskBoard on Kubernetes — Helm chart walkthrough

This directory holds the Helm chart that deploys the TaskBoard stack (React/Nginx frontend, FastAPI
backend, PostgreSQL) into a Kubernetes cluster. Everything below was executed against a live
minikube cluster and the output is pasted verbatim.

There is no screen-capture tooling in this environment, so every "screenshot" the rubric asks for is
substituted with the captured terminal output of the exact command. No output in this document was
written by hand.

## Environment this was run against

| Component | Version / value |
|---|---|
| Cluster | minikube, Kubernetes v1.37.0, single node |
| Node architecture | `arm64` (Apple Silicon) |
| Container runtime | containerd 2.3.4 |
| Helm | v4.3.0 |
| Addons | `ingress` (ingress-nginx), `metrics-server`, `storage-provisioner` |
| Namespace | `capstone` |
| Ingress host | `taskboard.local` |
| Node IP | `192.168.49.2` |

## Layout

```text
k8s/
  namespace.yaml              Namespace capstone, applied with kubectl before Helm runs
helm/
  README.md                   this walkthrough
  taskboard/
    Chart.yaml                chart metadata, version 1.1.0, appVersion 1.0.0
    values.yaml               defaults, pinned image tags
    values-dev.yaml           single replica, ephemeral database, no autoscaling
    values-prod.yaml          three replicas, larger requests, autoscaling 3..10
    templates/
      _helpers.tpl            name/fullname/label helpers, database URL builder
      backend-deployment.yaml backend Deployment plus wait-for-postgres init container
      backend-service.yaml    backend ClusterIP Service plus the `backend` alias Service
      frontend-deployment.yaml
      frontend-service.yaml   frontend ClusterIP Service
      postgres.yaml           Secret, Service, PVC and Deployment for PostgreSQL
      ingress.yaml            single host, `/api` to backend and `/` to frontend
      hpa.yaml                HorizontalPodAutoscaler for the backend
      servicemonitor.yaml     Prometheus ServiceMonitor, rendered only if the CRD exists
```

## Quick start

```bash
kubectl apply -f k8s/namespace.yaml
helm upgrade --install taskboard helm/taskboard -n capstone --wait
kubectl get pods -n capstone
```

To reach the application, add `192.168.49.2 taskboard.local` to `/etc/hosts`, or use the
port-forward method described under "Reaching the Ingress" below.

---

## Which image tag is pinned, and why

The CI pipeline publishes both images to GHCR tagged by commit SHA, with no `latest` tag. The
available tags were listed from the registry rather than guessed:

```console
$ curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/amanyadav7015/taskboard-backend/tags/list
{
    "name": "amanyadav7015/taskboard-backend",
    "tags": [
        "461f7a3bf7b9c04b6d28c8f78efbf4f3dddb3bc0",
        "461f7a3",
        "a4c43f6dd12dbdaf0bca2620ac08866beb0cde2f",
        "a4c43f6",
        "638f9bb66d774f308330aa6837e93f0c37b502f6",
        "638f9bb",
        "13fc94b97ac9429277e6050b09e04a08ffd89cb3",
        "13fc94b"
    ]
}
```

The frontend repository carries the same eight tags. Reading each image's config blob gave the build
timestamps, which identified the newest pair:

```text
taskboard-backend:13fc94b  arch= amd64 os= linux created= 2026-10-07T14:37:45Z
taskboard-frontend:13fc94b arch= amd64 os= linux created= 2026-10-07T14:37:52Z
```

`values.yaml` is therefore pinned to the full 40-character SHA
`13fc94b97ac9429277e6050b09e04a08ffd89cb3` for both images. The full SHA is used rather than the
short form so the tag is unambiguous.

### The architecture mismatch, and why no fallback was needed

Every published image is `linux/amd64`, because the GitHub Actions runners are amd64. The minikube
node is `arm64`. That combination normally produces `exec format error`, and the plan was to fall
back to `minikube image load` of locally built arm64 images.

That fallback turned out to be unnecessary. The images pulled and ran straight from GHCR:

```console
$ kubectl exec -n capstone taskboard-backend-86967c6645-cv5f4 -- uname -m
x86_64

$ kubectl get node minikube -o jsonpath='{.status.nodeInfo.architecture}'
arm64

$ minikube ssh -- "ls /proc/sys/fs/binfmt_misc/"
arm
i386
mips64
...
rosetta
rosetta-wrapper
s390x
x86_64
```

The minikube container inherits Docker Desktop's `binfmt_misc` handlers, including `rosetta`, so
amd64 binaries execute transparently on the arm64 node. The chart pins the real GHCR tag and pulls
it; no locally built image is involved. The honest caveat is that the backend runs under emulation
here, which costs some CPU — on a matching amd64 node, or once the pipeline publishes a multi-arch
manifest, the same tag runs natively.

---

## What was broken in the starter chart, and how each was fixed

The starter chart passed `helm lint` cleanly and `helm template` rendered without error, which is
worth stating plainly: **neither command found any of the eight defects below.** All of them are
semantic, and all of them would have produced a broken or non-starting deployment. They were found
by reading the rendered manifest and by deploying it.

```console
$ helm lint helm/taskboard
==> Linting helm/taskboard
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

### 1. The Ingress pointed at a service that did not exist, on a port nothing listened on

The single most serious defect. Rendering the starter chart gave:

```yaml
- {path: /api, pathType: Prefix, backend: {service: {name: taskboard-backend, port: {number: 8080}}}}
```

while the backend Service actually rendered as:

```yaml
kind: Service
metadata:
  name: taskboard-taskboard-backend
  ports:
    - port: 8000
```

Both the name and the port were wrong, so every `/api` request would have returned 503 from
ingress-nginx. Fixed by templating the Ingress backend from the same helper that names the Service,
and by taking the port from `.Values.backend.port` instead of a hard-coded literal, so the two can
no longer drift apart.

### 2. The fullname helper doubled the chart name

`{{ .Release.Name }}-taskboard` produced `taskboard-taskboard-backend` for release `taskboard`.
Replaced with the standard Helm fullname helper, which collapses the repetition when the release
name already contains the chart name. Services are now `taskboard-backend` and `taskboard-frontend`.

### 3. The frontend could not have started at all

`frontend/nginx.conf` (owned by the application, not by this chart) contains:

```nginx
location /api/ {
  proxy_pass http://backend:8000;
}
```

Nginx resolves an upstream hostname written this way at configuration-load time and refuses to start
if it does not resolve. There was no Service named `backend` in the chart, so every frontend pod
would have crash-looped. This was confirmed by running the exact frontend image in a namespace where
nothing named `backend` resolves:

```console
$ kubectl run m8-nginx-probe -n default --restart=Never --image=ghcr.io/amanyadav7015/taskboard-frontend:13fc94b97ac9429277e6050b09e04a08ffd89cb3
pod/m8-nginx-probe created

$ kubectl get pod m8-nginx-probe -n default
NAME             READY   STATUS   RESTARTS   AGE
m8-nginx-probe   0/1     Error    0          20s

$ kubectl logs m8-nginx-probe -n default
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/10/07 15:17:04 [emerg] 1#1: host not found in upstream "backend" in /etc/nginx/conf.d/default.conf:13
nginx: [emerg] host not found in upstream "backend" in /etc/nginx/conf.d/default.conf:13
```

Fixed inside the chart, without touching the application, by adding a second ClusterIP Service named
`backend` that selects the same backend pods. It is a deliberate alias and is controlled by
`backend.compatibilityServiceName`. This is why `kubectl get svc` shows four services: the
release-scoped `taskboard-backend` that the Ingress and the ServiceMonitor use, and the fixed-name
`backend` that satisfies the frontend's compiled-in proxy target.

That alias is load-bearing — it is what makes this work:

```console
$ curl -s -H 'Host: taskboard.local' http://192.168.49.2/health
{"status":"UP"}
```

`/health` is served by the frontend's nginx proxying through to the backend, so a 200 here proves
in-cluster name resolution of `backend` is working.

### 4. The ServiceMonitor would have aborted the install

`monitoring.serviceMonitor.enabled` defaulted to `true`, but no Prometheus Operator CRDs are
installed in this cluster:

```console
$ kubectl get crd | grep -i monitoring
(no output)
```

Applying a `monitoring.coreos.com/v1` object with no CRD fails the whole release. Fixed by guarding
the template on capability as well as on the value:

```yaml
{{- if and .Values.monitoring.serviceMonitor.enabled (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1") }}
```

The value stays `true`, so the ServiceMonitor appears automatically once the monitoring stack is
installed, and is silently skipped until then.

### 5. The namespace did not match

`k8s/namespace.yaml` declared namespace `taskboard`; the capstone uses `capstone`. Changed, and
standard labels added. The unused `namespace` key was removed from `values.yaml` — it was never
referenced by any template, and a value that looks like it controls something but does not is worse
than no value at all. The namespace comes from `-n` / `.Release.Namespace`.

### 6. The backend raced PostgreSQL on startup

The backend image's entrypoint is `alembic upgrade head && uvicorn ...`. On a cold namespace the
backend pods start alongside PostgreSQL, so Alembic can reach the database only once PostgreSQL has
finished initialising. If it cannot, the container exits non-zero and the pod enters CrashLoopBackOff
with a growing backoff delay — it recovers eventually, but a first install looks broken while it
does.

This one was pre-empted rather than observed: the init container was added before the first deploy,
so the race never had the chance to fire. The mitigation is a `wait-for-postgres` init container that
blocks on `pg_isready` and reuses the `postgres:16-alpine` image already being pulled, so no extra
image is needed. It does run and gate the backend on every pod start:

```console
$ kubectl logs -n capstone taskboard-backend-86967c6645-8q4tr -c wait-for-postgres
taskboard-postgres:5432 - accepting connections
```

A `startupProbe` was also added so that a slow first start — migrations, under emulation — does not
trip the liveness probe and restart a container that is merely still booting.

### 7. The database password was interpolated into a plain env var

The starter built `DATABASE_URL` inline in the Deployment, so the password appeared in plaintext in
`kubectl get deploy -o yaml` and in `helm get manifest`. The full connection string is now assembled
once in `_helpers.tpl`, stored in the Secret as `database-url`, and injected with `secretKeyRef`.
PostgreSQL's own `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` all read from the same
Secret, so the credentials are defined in exactly one place.

A `checksum/secret` pod annotation was added to the backend so that changing the credentials rolls
the pods instead of leaving them on a stale connection string.

### 8. Smaller correctness fixes

- **PostgreSQL data directory.** `PGDATA` is set to a `pgdata` subdirectory of the mount rather than
  the mount root, which avoids initdb refusing to start on a non-empty volume.
- **Recreate strategy for PostgreSQL.** The PVC is `ReadWriteOnce`; a default rolling update would
  try to schedule a second pod holding the same volume and stall.
- **PVC retention.** `helm.sh/resource-policy: keep` so `helm uninstall` does not silently delete the
  database.
- **One replica knob per component.** `replicaCount` is the shared default; `backend.replicas` and
  `frontend.replicas` override it independently.
- **Named container ports.** Services and probes target `http` by name instead of repeating port
  numbers.
- **Resources split per component.** The starter applied one `resources` block to the backend only,
  with the frontend's values hard-coded in the template.
- **Security contexts.** The backend runs as UID 10001 with `allowPrivilegeEscalation: false` and all
  capabilities dropped. The frontend only sets `runAsNonRoot` and UID 101 — deliberately not
  `allowPrivilegeEscalation: false`, because its image uses a file capability
  (`setcap cap_net_bind_service`) to bind port 80 as a non-root user, and `NoNewPrivs` would strip
  that capability and stop nginx from binding.
- **Standard labels.** Every object carries the `app.kubernetes.io/*` label set; the original
  `app:` selector labels are preserved so existing selectors keep matching.

---

## Deploying

```console
$ kubectl apply -f k8s/namespace.yaml
namespace/capstone created

$ helm upgrade --install taskboard helm/taskboard -n capstone --wait --timeout 4m
Release "taskboard" does not exist. Installing it now.
NAME: taskboard
LAST DEPLOYED: Wed Oct  7 20:35:26 2026
NAMESPACE: capstone
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
```

### Current state

The capture below is a single consistent snapshot taken at release revision 6, after the upgrade
sequence described further down. Both the Deployments and the Services are shown as they stand now.

```console
$ kubectl get pods -n capstone -o wide
NAME                                  READY   STATUS    RESTARTS   AGE     IP            NODE       NOMINATED NODE   READINESS GATES
taskboard-backend-86967c6645-8q4tr    1/1     Running   0          5m8s    10.244.0.36   minikube   <none>           <none>
taskboard-backend-86967c6645-llqld    1/1     Running   0          5m19s   10.244.0.35   minikube   <none>           <none>
taskboard-backend-86967c6645-svxrd    1/1     Running   0          33s     10.244.0.42   minikube   <none>           <none>
taskboard-backend-86967c6645-vd76n    1/1     Running   0          33s     10.244.0.41   minikube   <none>           <none>
taskboard-frontend-654b777547-5f4ph   1/1     Running   0          12m     10.244.0.16   minikube   <none>           <none>
taskboard-frontend-654b777547-gv65b   1/1     Running   0          12m     10.244.0.14   minikube   <none>           <none>
taskboard-postgres-65d8f5b766-tnk4r   1/1     Running   0          12m     10.244.0.17   minikube   <none>           <none>
```

Every pod is `1/1 Running` with zero restarts. The chart asks for two backend replicas and two
frontend replicas; four backend pods are present because the autoscaler scaled up on its own — see
below.

### ClusterIP Services

```console
$ kubectl get svc -n capstone
NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
backend              ClusterIP   10.102.57.105    <none>        8000/TCP   12m
taskboard-backend    ClusterIP   10.97.88.62      <none>        8000/TCP   12m
taskboard-frontend   ClusterIP   10.98.100.3      <none>        80/TCP     12m
taskboard-postgres   ClusterIP   10.104.187.241   <none>        5432/TCP   12m
```

All four are `ClusterIP`. `taskboard-backend` and `taskboard-frontend` are the two the Ingress
targets; `backend` is the alias described in fix 3; `taskboard-postgres` is internal to the database.

### Ingress, Deployments, autoscaler and volume

```console
$ kubectl get ingress -n capstone
NAME        CLASS   HOSTS             ADDRESS        PORTS   AGE
taskboard   nginx   taskboard.local   192.168.49.2   80      12m

$ kubectl get deploy,hpa,pvc -n capstone
NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/taskboard-backend    4/4     4            4           12m
deployment.apps/taskboard-frontend   2/2     2            2           12m
deployment.apps/taskboard-postgres   1/1     1            1           12m

NAME                                                    REFERENCE                      TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/taskboard-backend   Deployment/taskboard-backend   cpu: 113%/60%   2         6         4          12m

NAME                                            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/taskboard-postgres-data   Bound    pvc-fc3ef34f-41c6-4900-ab64-253185a09bef   2Gi        RWO            standard       <unset>                 12m
```

### The autoscaler fired for real

That `4/4` was not configured. Sustained traffic against `/api` pushed backend CPU to 113% of its
request, and the HPA scaled from 2 to 4 replicas on its own:

```console
$ kubectl describe hpa taskboard-backend -n capstone
Events:
  Type     Reason                        Age                  From                       Message
  ----     ------                        ----                 ----                       -------
  Warning  FailedComputeMetricsReplicas  11m (x2 over 12m)    horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
  Warning  FailedGetResourceMetric       11m (x10 over 14m)   horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  11m (x10 over 14m)   horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedGetResourceMetric       9m11s (x9 over 12m)  horizontal-pod-autoscaler  failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
  Normal   SuccessfulRescale             2m10s                horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             70s                  horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target

$ kubectl top pods -n capstone
NAME                                  CPU(cores)   MEMORY(bytes)
taskboard-backend-86967c6645-8q4tr    3m           81Mi
taskboard-backend-86967c6645-llqld    223m         84Mi
taskboard-frontend-654b777547-5f4ph   1m           34Mi
taskboard-frontend-654b777547-gv65b   1m           34Mi
taskboard-postgres-65d8f5b766-tnk4r   21m          30Mi
```

Three notes on reading that output honestly.

The scaling is still in progress — the events show a second rescale to 5 after the snapshot above was
taken. **The backend replica count is therefore a moving number while load continues**, which is the
point of an autoscaler, but it does mean a `kubectl get` taken minutes apart will disagree. The floor
is `hpa.minReplicas: 2`, so the two-replica requirement holds whatever the load is doing.

The CPU cost is inflated by the amd64-on-arm64 emulation described earlier, so this scales up sooner
and at lower real throughput than it would on a native amd64 node.

The `FailedGetResourceMetric` and `FailedComputeMetricsReplicas` warnings in the same event list are
metrics-server not yet having scraped freshly created pods. That is why `kubectl get hpa` shows
`cpu: <unknown>/60%` for a minute or two after any rollout. It resolves without intervention and is
not a misconfiguration.

### Release

```console
$ helm list -n capstone
NAME     	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART          	APP VERSION
taskboard	capstone 	6       	2026-10-07 20:42:41.065783 +0530 IST	deployed	taskboard-1.1.0	1.0.0
```

---

## Reaching the Ingress

The minikube node IP is not routable from the macOS host. This is the real result, not a
hypothetical:

```console
$ curl -sS --max-time 8 -H 'Host: taskboard.local' http://192.168.49.2/
curl: (28) Connection timed out after 8002 milliseconds
```

The same request issued from inside the node succeeds:

```console
$ minikube ssh -- "curl -s -o /dev/null -w 'HTTP %{http_code}\n' -H 'Host: taskboard.local' http://192.168.49.2/"
HTTP 200
```

For access from the host, port-forward the ingress controller:

```console
$ kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8081:80 &
$ curl -s -o /dev/null -w 'HTTP %{http_code}  %{content_type}\n' -H 'Host: taskboard.local' http://localhost:8081/
HTTP 200  text/html
$ curl -s -o /dev/null -w 'HTTP %{http_code}  %{content_type}\n' -H 'Host: taskboard.local' http://localhost:8081/api/tasks
HTTP 200  application/json
```

A browser pointed at `http://localhost:8081` with `taskboard.local` mapped in `/etc/hosts` loads the
application through the same Ingress.

---

## Ingress routing proof

One host, `taskboard.local`, two path-based backends.

`/` returns the frontend's HTML:

```console
$ minikube ssh -- "curl -s -i -H 'Host: taskboard.local' http://192.168.49.2/"
HTTP/1.1 200 OK
Date: Wed, 07 Oct 2026 15:07:35 GMT
Content-Type: text/html
Content-Length: 461
Connection: keep-alive
Last-Modified: Wed, 07 Oct 2026 14:37:52 GMT
ETag: "6ac65940-1cd"
Accept-Ranges: bytes

<!doctype html><html lang="en"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><meta name="description" content="TaskBoard - DevOps capstone task management dashboard"/><title>TaskBoard | DevOps Capstone</title>  <script type="module" crossorigin src="/assets/index-CU52_SNU.js"></script>
  <link rel="stylesheet" crossorigin href="/assets/index-CaDU8gDp.css">
</head><body><div id="root"></div></body></html>
```

`/api/...` returns JSON from the backend:

```console
$ minikube ssh -- "curl -s -i -H 'Host: taskboard.local' http://192.168.49.2/api/tasks"
HTTP/1.1 200 OK
Date: Wed, 07 Oct 2026 15:07:35 GMT
Content-Type: application/json
Content-Length: 4033
Connection: keep-alive

[{"title":"load-25","description":"generated traffic","priority":"MEDIUM","status":"TODO","assignee":"loadgen","id":25,"created_at":"2026-10-07T15:07:34.212445Z"}, ...]

$ minikube ssh -- "curl -s -H 'Host: taskboard.local' http://192.168.49.2/api/tasks/stats"
{"total":25,"todo":25,"inProgress":0,"done":0}
```

Note the `Content-Type` difference: `text/html` on `/` and `application/json` on `/api`. Same host,
same port, two different pods, selected purely by path prefix.

---

## End-to-end proof: the application really works in the cluster

A write through the Ingress, a read back, and then the row surviving the destruction of every pod
that served it.

### Create

```console
$ minikube ssh -- "curl -s -o /tmp/post.json -w 'HTTP %{http_code}\n' -X POST -H 'Host: taskboard.local' -H 'Content-Type: application/json' -d '{\"title\":\"m8-persistence-probe\",...}' http://192.168.49.2/api/tasks; cat /tmp/post.json"
HTTP 201
{"title":"m8-persistence-probe","description":"created through the ingress","priority":"HIGH","status":"IN_PROGRESS","assignee":"k8s-agent","id":26,"created_at":"2026-10-07T15:07:46.738325Z"}
```

### Read back

```console
$ minikube ssh -- "curl -s -H 'Host: taskboard.local' http://192.168.49.2/api/tasks/26"
{"title":"m8-persistence-probe","description":"created through the ingress","priority":"HIGH","status":"IN_PROGRESS","assignee":"k8s-agent","id":26,"created_at":"2026-10-07T15:07:46.738325Z"}
```

### Destroy every backend pod

```console
$ kubectl delete pod -n capstone -l app=taskboard-backend
pod "taskboard-backend-86967c6645-cv5f4" deleted from capstone namespace
pod "taskboard-backend-86967c6645-jl84l" deleted from capstone namespace

$ kubectl rollout status deploy/taskboard-backend -n capstone
Waiting for deployment "taskboard-backend" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "taskboard-backend" rollout to finish: 1 of 2 updated replicas are available...
deployment "taskboard-backend" successfully rolled out

$ kubectl get pods -n capstone -l app=taskboard-backend
NAME                                 READY   STATUS    RESTARTS   AGE
taskboard-backend-86967c6645-2pfhf   1/1     Running   0          10s
taskboard-backend-86967c6645-bf7m2   1/1     Running   0          10s
```

Both pod names changed — `cv5f4` and `jl84l` are gone, `2pfhf` and `bf7m2` are new — so nothing that
served the original write is still alive. The ReplicaSet hash is unchanged because the pod spec did
not change; only the pods were destroyed and recreated.

### The row survived

```console
$ minikube ssh -- "curl -s -H 'Host: taskboard.local' http://192.168.49.2/api/tasks/26"
{"title":"m8-persistence-probe","description":"created through the ingress","priority":"HIGH","status":"IN_PROGRESS","assignee":"k8s-agent","id":26,"created_at":"2026-10-07T15:07:46.738325Z"}

$ minikube ssh -- "curl -s -H 'Host: taskboard.local' http://192.168.49.2/api/tasks/stats"
{"total":26,"todo":25,"inProgress":1,"done":0}
```

Confirmed directly against PostgreSQL, bypassing the API entirely:

```console
$ kubectl exec -n capstone taskboard-postgres-65d8f5b766-tnk4r -- psql -U taskboard -d taskboard -c "select id,title,status,assignee from tasks where id=26;"
 id |        title         |   status    | assignee
----+----------------------+-------------+-----------
 26 | m8-persistence-probe | IN_PROGRESS | k8s-agent
(1 row)
```

The Alembic migration also ran inside the cluster, from the backend container's entrypoint:

```console
$ kubectl exec -n capstone taskboard-postgres-65d8f5b766-tnk4r -- psql -U taskboard -d taskboard -c "select * from alembic_version;"
    version_num
-------------------
 0001_create_tasks
(1 row)
```

---

## Upgrades, a failure, and a rollback

This section is the real sequence, including the upgrade that failed.

### The upgrade that failed

Applying the production overlay failed outright:

```console
$ helm upgrade --install taskboard helm/taskboard -n capstone -f helm/taskboard/values-prod.yaml --wait --timeout 5m
level=WARN msg="upgrade failed" name=taskboard error="server-side apply failed for object capstone/taskboard-postgres-data /v1, Kind=PersistentVolumeClaim: persistentvolumeclaims \"taskboard-postgres-data\" is forbidden: only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize"
Error: UPGRADE FAILED: server-side apply failed for object capstone/taskboard-postgres-data /v1, Kind=PersistentVolumeClaim: persistentvolumeclaims "taskboard-postgres-data" is forbidden: only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize
```

The production overlay asked for a 10Gi volume where the default was 2Gi. A PVC's storage request
can only be increased if its StorageClass allows expansion, and minikube's does not:

```console
$ kubectl get sc
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate           false                  19d
```

Two things are worth noting. First, the release was left `failed` but the Deployments had already
been applied — Helm 4's server-side apply is not atomic across objects, so the cluster was in a
partially upgraded state. Second, `helm list` alone would not have shown this, because a failed
release is hidden from the default listing:

```console
$ helm list -n capstone --failed
NAME     	NAMESPACE	REVISION	UPDATED                             	STATUS	CHART          	APP VERSION
taskboard	capstone 	2       	2026-10-07 20:38:33.009794 +0530 IST	failed	taskboard-1.1.0	1.0.0
```

The fix was to set `postgres.persistence.size` to `2Gi` in `values-prod.yaml`. A larger volume is
the right production value on a cloud StorageClass that supports expansion, but it cannot be
expressed as a *change* against an existing volume on this cluster.

### Roll back, then upgrade cleanly

```console
$ helm rollback taskboard 1 -n capstone --wait --timeout 5m
Rollback was a success! Happy Helming!

$ kubectl get deploy -n capstone
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
taskboard-backend    2/2     2            2           4m
taskboard-frontend   2/2     2            2           4m
taskboard-postgres   1/1     1            1           4m

$ helm upgrade --install taskboard helm/taskboard -n capstone -f helm/taskboard/values-prod.yaml --wait --timeout 5m
Release "taskboard" has been upgraded. Happy Helming!
NAME: taskboard
NAMESPACE: capstone
STATUS: deployed
REVISION: 4
DESCRIPTION: Upgrade complete
```

### The upgrade did something real

Replica counts went from 2 to 3, the autoscaler floor moved, and the backend's CPU request doubled:

```console
$ kubectl get deploy -n capstone
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
taskboard-backend    3/3     3            3           4m24s
taskboard-frontend   3/3     3            3           4m24s
taskboard-postgres   1/1     1            1           4m24s

$ kubectl get pods -n capstone -o wide
NAME                                  READY   STATUS    RESTARTS   AGE     IP            NODE
taskboard-backend-647895b864-767mm    1/1     Running   0          18s     10.244.0.33   minikube
taskboard-backend-647895b864-sxhhv    1/1     Running   0          12s     10.244.0.34   minikube
taskboard-backend-647895b864-wfm2g    1/1     Running   0          24s     10.244.0.32   minikube
taskboard-frontend-654b777547-5f4ph   1/1     Running   0          4m24s   10.244.0.16   minikube
taskboard-frontend-654b777547-chdm8   1/1     Running   0          24s     10.244.0.31   minikube
taskboard-frontend-654b777547-gv65b   1/1     Running   0          4m24s   10.244.0.14   minikube

$ kubectl get hpa -n capstone
NAME                REFERENCE                      TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
taskboard-backend   Deployment/taskboard-backend   cpu: <unknown>/70%   3         10        3          4m25s

$ kubectl get deploy taskboard-backend -n capstone -o jsonpath='{.spec.template.spec.containers[0].resources}'
{"limits":{"cpu":"1","memory":"768Mi"},"requests":{"cpu":"200m","memory":"384Mi"}}
```

The backend pod hashes changed from `86967c6645` to `647895b864` — the resource change rolled the
pods, rather than only scaling them. The two older frontend pods were kept and one was added,
because only the replica count changed for the frontend. The application stayed up throughout:

```console
$ minikube ssh -- "curl -s -H 'Host: taskboard.local' http://192.168.49.2/api/tasks/stats"
{"total":26,"todo":25,"inProgress":1,"done":0}
```

### A Helm 4 behaviour worth knowing

Running a bare `helm upgrade` afterwards, with no `-f` flag, did **not** return the release to the
chart defaults. The production values were still in effect:

```console
$ helm upgrade --install taskboard helm/taskboard -n capstone --wait
REVISION: 5
DESCRIPTION: Upgrade complete

$ helm get values taskboard -n capstone
USER-SUPPLIED VALUES:
backend:
  replicas: 3
  ...
replicaCount: 3
```

Helm 4 carries previously supplied user values forward across upgrades. `--reset-values` is required
to drop back to the chart defaults:

```console
$ helm upgrade --install taskboard helm/taskboard -n capstone --reset-values --wait
REVISION: 6
DESCRIPTION: Upgrade complete

$ helm get values taskboard -n capstone
USER-SUPPLIED VALUES:
null

$ kubectl get deploy -n capstone
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
taskboard-backend    2/2     2            2           7m40s
taskboard-frontend   2/2     2            2           7m40s
taskboard-postgres   1/1     1            1           7m40s

$ kubectl get hpa -n capstone
NAME                REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
taskboard-backend   Deployment/taskboard-backend   cpu: 3%/60%   2         6         2          7m40s
```

### Full release history

```console
$ helm history taskboard -n capstone
REVISION	UPDATED                 	STATUS    	CHART          	APP VERSION	DESCRIPTION
1       	Wed Oct  7 20:35:26 2026	superseded	taskboard-1.1.0	1.0.0      	Install complete
2       	Wed Oct  7 20:38:33 2026	failed    	taskboard-1.1.0	1.0.0      	Upgrade "taskboard" failed: server-side apply failed for object capstone/taskboard-postgres-data /v1, Kind=PersistentVolumeClaim: persistentvolumeclaims "taskboard-postgres-data" is forbidden: only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize
3       	Wed Oct  7 20:39:03 2026	superseded	taskboard-1.1.0	1.0.0      	Rollback to 1
4       	Wed Oct  7 20:39:26 2026	superseded	taskboard-1.1.0	1.0.0      	Upgrade complete
5       	Wed Oct  7 20:42:08 2026	superseded	taskboard-1.1.0	1.0.0      	Upgrade complete
6       	Wed Oct  7 20:42:41 2026	deployed  	taskboard-1.1.0	1.0.0      	Upgrade complete
```

---

## Other Helm 4 differences encountered

| Helm 3 | Helm 4 as observed here |
|---|---|
| `helm list --all` | Removed. `Error: unknown flag: --all`. Use `--failed`, `--deployed`, `--superseded`, `--pending`. |
| `helm upgrade` resets to chart defaults | Previously supplied values are carried forward; `--reset-values` is needed to drop them. |
| Client-side apply with three-way merge | Server-side apply by default, so field-level conflicts and immutable-field errors surface as hard `UPGRADE FAILED` errors. |
| `--debug` prints plain text | Emits structured `level=DEBUG` / `level=WARN` logging. |

---

## Values reference

### Top level

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Overrides the chart name used in resource names and labels. |
| `fullnameOverride` | `""` | Replaces the generated release-scoped name entirely. |
| `replicaCount` | `2` | Default replica count, used when a component does not set its own. |
| `imagePullSecrets` | `[]` | Pull secrets added to backend and frontend pods. Empty because both GHCR packages are public. |

### `backend`

| Key | Default | Description |
|---|---|---|
| `backend.image` | `ghcr.io/amanyadav7015/taskboard-backend` | Image repository, without the tag. |
| `backend.tag` | `13fc94b97ac9429277e6050b09e04a08ffd89cb3` | Full commit SHA published by the pipeline. Never `latest`. |
| `backend.pullPolicy` | `IfNotPresent` | Safe with immutable SHA tags, and avoids a registry round-trip per pod start. |
| `backend.replicas` | `2` | Overrides `replicaCount` for the backend. |
| `backend.port` | `8000` | Container port, Service port and Ingress backend port, all from this one key. |
| `backend.compatibilityServiceName` | `backend` | Name of the alias Service the frontend's nginx proxies to. Set to `""` to omit it. |
| `backend.resources` | `100m`/`256Mi` requests, `500m`/`512Mi` limits | CPU requests must be set for the HPA to compute utilisation. |
| `backend.securityContext` | non-root UID 10001, no privilege escalation, all capabilities dropped | Matches the non-root user baked into the backend image. |

### `frontend`

| Key | Default | Description |
|---|---|---|
| `frontend.image` | `ghcr.io/amanyadav7015/taskboard-frontend` | Image repository, without the tag. |
| `frontend.tag` | `13fc94b97ac9429277e6050b09e04a08ffd89cb3` | Same commit SHA as the backend. |
| `frontend.pullPolicy` | `IfNotPresent` | As above. |
| `frontend.replicas` | `2` | Overrides `replicaCount` for the frontend. |
| `frontend.port` | `80` | Container, Service and Ingress port. |
| `frontend.resources` | `50m`/`64Mi` requests, `200m`/`128Mi` limits | Nginx serving static assets needs very little. |
| `frontend.securityContext` | non-root UID 101 | Deliberately omits `allowPrivilegeEscalation: false`; see fix 8 above. |

### `postgres`

| Key | Default | Description |
|---|---|---|
| `postgres.enabled` | `true` | Set to `false` to point the backend at an external database instead. |
| `postgres.image` | `postgres:16-alpine` | Also reused by the backend's wait-for-postgres init container. |
| `postgres.pullPolicy` | `IfNotPresent` | Applies to both the database container and the init container. |
| `postgres.port` | `5432` | Service and container port. |
| `postgres.database` | `taskboard` | Database name. |
| `postgres.username` | `taskboard` | Role name. |
| `postgres.password` | `taskboard` | Development default. Supply via `--set` or a sealed Secret for any real deployment. |
| `postgres.persistence.enabled` | `true` | `false` uses an `emptyDir`, which is what `values-dev.yaml` does. |
| `postgres.persistence.size` | `2Gi` | Cannot be increased on a StorageClass without volume expansion; see the failed upgrade above. |
| `postgres.persistence.storageClassName` | `""` | Empty uses the cluster default (`standard` on minikube). |
| `postgres.resources` | `50m`/`128Mi` requests, `500m`/`512Mi` limits | |

### `ingress`

| Key | Default | Description |
|---|---|---|
| `ingress.enabled` | `true` | |
| `ingress.className` | `nginx` | Matches the `nginx` IngressClass from the minikube ingress addon. |
| `ingress.host` | `taskboard.local` | The single host serving both `/` and `/api`. |
| `ingress.annotations` | `proxy-body-size: 2m` | Extra ingress-nginx annotations. |

### `hpa`

| Key | Default | Description |
|---|---|---|
| `hpa.enabled` | `true` | Requires metrics-server. |
| `hpa.minReplicas` | `2` | Keeps the rubric's two-replica floor even when idle. |
| `hpa.maxReplicas` | `6` | |
| `hpa.targetCPUUtilizationPercentage` | `60` | Percentage of the CPU *request*, not the limit. |

### `monitoring`

| Key | Default | Description |
|---|---|---|
| `monitoring.serviceMonitor.enabled` | `true` | Only renders if the `monitoring.coreos.com/v1` CRD is present, so it is safe to leave on. |
| `monitoring.serviceMonitor.interval` | `15s` | Scrape interval for `/metrics`. |
| `monitoring.serviceMonitor.releaseLabel` | `kube-prometheus-stack` | Must match the Prometheus Operator's ServiceMonitor selector. |

## Overlays

| Overlay | Replicas | Database | Autoscaling | ServiceMonitor |
|---|---|---|---|---|
| `values.yaml` | 2 backend, 2 frontend | 2Gi persistent volume | 2 to 6 at 60% CPU | on, if the CRD exists |
| `values-dev.yaml` | 1 backend, 1 frontend | `emptyDir`, wiped on restart | off | off |
| `values-prod.yaml` | 3 backend, 3 frontend | 2Gi persistent volume | 3 to 10 at 70% CPU | on |

```bash
helm upgrade --install taskboard helm/taskboard -n capstone -f helm/taskboard/values-dev.yaml --reset-values
helm upgrade --install taskboard helm/taskboard -n capstone -f helm/taskboard/values-prod.yaml --reset-values
```

## Uninstalling

```bash
helm uninstall taskboard -n capstone
kubectl delete -f k8s/namespace.yaml
```

The PVC carries `helm.sh/resource-policy: keep`, so `helm uninstall` leaves the database volume
behind on purpose. Delete it explicitly if a clean slate is wanted:

```bash
kubectl delete pvc taskboard-postgres-data -n capstone
```
