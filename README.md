# CloudCost Helm Chart

Helm chart for installing the CloudCost platform on Kubernetes.

> ⚠️ **SMTP configuration is mandatory.** If `backend.secrets.smtpUser` and
> `backend.secrets.smtpPassword` in `values.yaml` are not set to real, working
> SMTP credentials, **users cannot log in to the application at all.** The app
> sends OTP / verification emails as part of login, so a missing or invalid
> SMTP configuration blocks login entirely, not just email delivery. Set these
> values before installing — see
> [Inline backend secret format](#inline-backend-secret-format) below.

| Component | Workload | Internal Service port | Purpose |
|---|---|---:|---|
| FastAPI backend | Deployment or StatefulSet | 8000 | API and background workers |
| React/nginx frontend | Deployment | 8080 | Web interface; nginx listens on container port 80 |
| PostgreSQL | StatefulSet | 5432 | Bundled database when enabled |

All chart settings are in the top-level `values.yaml`. The files under
`charts/*/values.yaml` are subchart defaults and normally do not need editing.

## Prerequisites

- Kubernetes 1.23 or newer
- Helm 3.8 or newer
- An ingress controller, such as ingress-nginx, when public access is required
- A default StorageClass, or an explicitly configured StorageClass, when the
  bundled PostgreSQL PVC is enabled
- Container images that the cluster can pull

The chart creates application Ingress resources, but it does not install an
ingress controller or create DNS records and TLS certificates.

## Configure and install

Review `values.yaml`, especially the namespace, image references, application
secrets, database mode, storage, and ingress settings.

```sh
helm lint . --strict
helm template cloudcost .
helm upgrade --install cloudcost .
```

`global.namespace.name` controls the namespace of the application resources,
and the chart creates that namespace. The command above stores the Helm release
metadata in the current Helm namespace (`default` unless another namespace is
selected). Keep using the same Helm namespace for every upgrade of that release.

To override a non-secret value without editing `values.yaml`:

```sh
helm upgrade --install cloudcost . \
  --set backend.image.tag=1.2.3 \
  --set frontend.image.tag=1.2.3
```

**Do not add `--wait` to `helm install`/`helm upgrade` for this chart.** The
backend pod has a `wait-for-migrations` init container that blocks it from
becoming Ready until the migration Job (a post-install/post-upgrade hook) has
finished. `--wait` makes Helm wait for the backend to become Ready before it
runs post-install/post-upgrade hooks — each side ends up waiting on the
other, so the command hangs indefinitely instead of completing. The commands
documented in this README never use `--wait`, for exactly this reason. If you
need a script/CI step to confirm the deploy is actually healthy, run
`helm upgrade --install` without `--wait`, then separately run
`kubectl rollout status deployment/cloudcost-backend -n cloudcost-test` —
that achieves the same goal without triggering this deadlock.

## Database configuration

The chart supports two database modes through `global.database`.

### Bundled PostgreSQL

This is the default mode:

```yaml
global:
  database:
    existingDatabase: false
```

In this mode, the chart deploys PostgreSQL and creates a Secret named
`<release>-postgres-auth`. For release `cloudcost`, the name is
`cloudcost-postgres-auth`. The Secret is rendered with Kubernetes `data:`
fields, so the manifest contains Base64 values for the database username,
password, and database name.

- `POSTGRES_USER` is `cloudcost`.
- `POSTGRES_DB` is `cloudcost_db`.
- `POSTGRES_PASSWORD` is randomly generated with 32 alphanumeric characters on
  the first installation.
- A normal `helm upgrade` reuses the password already stored in the Secret. It
  does not rotate the password.
- The backend reads the credentials directly from this Secret. The database
  username and password are not configured in `values.yaml`.

View the generated password in PowerShell:

```powershell
$encoded = kubectl -n cloudcost-test get secret cloudcost-postgres-auth -o jsonpath="{.data.POSTGRES_PASSWORD}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
```

On Linux or macOS:

```sh
kubectl -n cloudcost-test get secret cloudcost-postgres-auth \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode
echo
```

This Secret is marked `helm.sh/resource-policy: keep`, so `helm uninstall`
never deletes it — only the application resources (backend, frontend, the
Postgres StatefulSet) are removed. `helm uninstall` prints a message
confirming this:

```text
These resources were kept due to the resource policy:
[Secret] cloudcost-postgres-auth
```

This is intentional: it guarantees the saved password always matches
whatever the bundled Postgres data actually expects, even across mode
switches (`existingDatabase: true` back to `false`) or an uninstall/reinstall
cycle. Do not delete this Secret manually while its matching PVC still has
data on it — that reintroduces the exact password mismatch this policy
prevents.

To fully wipe a test environment — removing the saved password along with
everything else, with nothing left over — delete it explicitly after
uninstalling:

```sh
helm uninstall cloudcost -n default
kubectl delete secret cloudcost-postgres-auth -n cloudcost-test
```

(The PVC does not need a separate delete command here: with the default
chart configuration the application namespace itself is deleted by
`helm uninstall`, and deleting a namespace removes everything inside it,
PVCs included — the Secret is the only thing that survives that cascade,
because of its `keep` policy.)

### Existing PostgreSQL database

To use a database that already exists, the backend needs a complete SQLAlchemy
connection URL.

For development or testing, it can be supplied directly in `values.yaml`:

```yaml
global:
  database:
    existingDatabase: true
    urlEncoding: plain
    url: "postgresql+asyncpg://cloudcost:encoded-password@postgres.example.internal:5432/cloudcost_db"
```

URL-encode special characters in the username and password. For example, `@`
becomes `%40`, `#` becomes `%23`, `$` becomes `%24`, and `&` becomes `%26`.
Set `urlEncoding: base64` only when the `url` value is already Base64-encoded.
The rendered Kubernetes Secret always uses `data.DATABASE_URL`, so the final
manifest contains Base64 either way.

For production, do not commit the real connection URL to Git. Supply it from a
secure Helm values source, CI/CD secret variable, or another protected release
process. This chart currently renders the backend Secret itself; it does not
currently support pointing `backend.secrets.existingSecret` at a pre-created
Secret.

When `existingDatabase: true`, the bundled PostgreSQL Secret, Service,
StatefulSet, and PVC are not created.

`url` is validated before anything is created — a missing or malformed value
fails `helm install`/`helm upgrade` immediately, with nothing deployed:

- **Missing entirely** — whether left as `url: ""` or fully commented out
  (`#url: ...`), both are caught the same way: `global.database.url must be
  set when global.database.existingDatabase is true`.
- **Present but malformed** (`urlEncoding: plain` only — a Base64 value can't
  be shape-checked before decoding) — each required piece of
  `postgresql+asyncpg://user:password@host:port/dbname` is checked
  individually, so the error names the exact missing piece, for example:
  `global.database.url is missing the password — expected user:password
  before the @ symbol`, or `global.database.url has an invalid port "abcd" —
  must be numeric`.

This only checks the URL's *shape*. It cannot verify the host is reachable,
the password is correct, or the database actually exists — those are only
discovered when the migration Job attempts to connect.

### Inline backend secret format

Choose how backend secret values are supplied. Plain-text mode accepts normal
values and Helm encodes them for Kubernetes:

```yaml
backend:
  secrets:
    encoding: plain
    secretKey: "replace-with-a-long-random-value"
    smtpUser: "sender@example.com"
    smtpPassword: "application-password"
```

Base64 mode accepts values that are already Base64-encoded and validates them
before rendering the Secret:

```yaml
backend:
  secrets:
    encoding: base64
    secretKey: "<base64-encoded-value>"
    smtpUser: "<base64-encoded-value>"
    smtpPassword: "<base64-encoded-value>"
```

Use exactly `plain` or `base64`; the chart does not guess the format. Empty
optional values are allowed. Base64 is encoding, not encryption: use a protected
values source or CI/CD secret process when values must not be stored in readable
form in Git.

When Helm manages the backend Secret, changes to inline secret values trigger a
backend pod rollout automatically through a pod-template checksum annotation.

#### `secretKey` — auto-generated if left empty

`secretKey` signs every login session token (JWT). Unlike `smtpUser`/
`smtpPassword`, it has no hard `fail` check if left empty — leaving it empty
is the recommended default, not an error condition:

```yaml
backend:
  secrets:
    secretKey: ""   # recommended: leave empty
```

When empty, the chart generates a random 64-character key on first install
and persists it across every future upgrade — the same `lookup`-based
pattern already used for the bundled Postgres password
([Bundled PostgreSQL](#bundled-postgresql) above). This matches the pattern
used by Bitnami, GitLab, and OpenObserve for this same class of value, and
avoids shipping a guessable static default (a real risk: `secretKey` is a
signing key — anyone who knows its value can forge a valid login token for
any user, without a password, while the application otherwise looks and
behaves completely normally).

View the generated value the same way as the Postgres password:

```powershell
$encoded = kubectl get secret cloudcost-backend-secret -n cloudcost-test -o jsonpath="{.data.SECRET_KEY}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
```

Only set `secretKey` explicitly if you need a specific value — for example,
sharing one signing key across multiple separate deployments so tokens
issued by one are accepted by another.

Current limitation: Google OAuth values are rendered as empty values by the
chart:

```text
GOOGLE_CLIENT_ID=""
GOOGLE_CLIENT_SECRET=""
REDIRECT_URI=""
```

Because of this, Google login is not configurable from Helm values in the
current chart.

## Database migrations

The chart always runs a post-install and post-upgrade Helm hook Job. This is
required because the backend cannot run correctly without its database schema.
The Job first ensures required PostgreSQL extensions exist, then applies:

```text
alembic upgrade heads
```

The migration Job currently ensures these PostgreSQL extensions:

```text
uuid-ossp
pgcrypto
```

It runs `CREATE EXTENSION IF NOT EXISTS`, so the operation is idempotent:
if an extension already exists, PostgreSQL keeps it; if it is missing, PostgreSQL
creates it.

For bundled PostgreSQL (`existingDatabase: false`), the chart deploys the
database and the migration Job creates the extensions before running Alembic.

For an existing PostgreSQL database (`existingDatabase: true`), the chart cannot
know in advance whether the database already has these extensions. The database
user in `DATABASE_URL` must either have permission to create them, or a database
administrator must create them before installing/upgrading CloudCost. If the
extensions are missing and the user does not have permission to create them, the
migration Job fails and the backend schema is not upgraded.

### Migration Job reliability

```yaml
backend:
  migrations:
    waitForDb: true
    backoffLimit: 2
    activeDeadlineSeconds: 3600
    gateBackendOnSchema: true
    schemaWaitAttempts: 100
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits: { cpu: 500m, memory: 512Mi }
```

- `backoffLimit` — how many times the migration Job retries after a failure.
  A bad `DATABASE_URL`, wrong credentials, or a missing extension is a config
  error that a retry cannot fix; this only exists to absorb rare transient
  infra issues. `0` disables retries entirely.
- `activeDeadlineSeconds` — hard wall-clock cap on the whole Job, independent
  of `backoffLimit`. Without this, a database that never becomes reachable
  makes the Job hang indefinitely instead of failing with a clear error.
- `gateBackendOnSchema` — adds a `wait-for-migrations` init container to the
  backend pod. It blocks the real backend container from starting until the
  database schema is confirmed at the migration Job's target revision. This
  prevents a race between this Job and the backend's own startup code (which
  also creates any tables it doesn't find) — without it, both can try to
  create the same table at nearly the same time and collide. Applies on
  every deploy, including the first install.
- `schemaWaitAttempts` — how many times `wait-for-migrations` polls (5
  seconds apart) before giving up and failing the backend pod's startup with
  a clear error, instead of waiting forever.
- `resources` — CPU/memory requests and limits for the migration Job's
  containers. Without this the Job runs as BestEffort QoS, the first
  candidate for eviction if the node comes under memory pressure for any
  unrelated reason.

## Storage

`global.database.persistence.type` and `backend.persistence.type` select the
volume source.

| Type | Storage | Guidance |
|---|---|---|
| `pvc` | Dynamically provisioned PVC | Default and recommended for the bundled database |
| `azureDisk` | Azure Managed Disk CSI | Suitable for a single PostgreSQL pod; ReadWriteOnce |
| `azureFile` | Azure Files CSI | Supports ReadWriteMany; generally avoid for PostgreSQL data |
| `azureBlob` | Azure Blob CSI/blobfuse | Object-backed filesystem; avoid for PostgreSQL data |
| `local` | Node `hostPath` | Development or fixed single-node use only |
| `emptyDir` | Ephemeral pod storage | Testing only; data is lost with the pod |

For production PostgreSQL, use durable storage, backups, and a tested restore
procedure. A managed PostgreSQL service is preferable when database high
availability, automated backups, and maintenance are required.

## Networking and public access

The backend and frontend Services are `ClusterIP`; their ports are reachable
inside the cluster only:

```text
Internet
   |
public IP :80 or :443
   |
Ingress controller LoadBalancer
   |-- /api/... -> backend Service :8000 -> backend container :8000
   `-- /        -> frontend Service :8080 -> nginx container :80
```

Changing the frontend Service from port `8080` to port `80` does not create a
new public IP and is not required for public access. The Ingress sends traffic
to the configured internal Service port automatically.

Both backend and frontend Services support optional Kubernetes Service
annotations:

```yaml
backend:
  service:
    annotations: {}

frontend:
  service:
    annotations: {}
```

The default `{}` adds nothing. Use these only when a Kubernetes platform,
cloud-provider integration, monitoring system, or automation tool requires
Service metadata.

### Access without a domain name

With the default hostless Ingress rules, get the ingress controller public IP:

```sh
kubectl -n ingress-nginx get service
```

If the public IP is `20.10.30.40`, the routes are:

```text
http://20.10.30.40/       frontend
http://20.10.30.40/api/   backend API
```

Only one application can own the same public IP, port, hostname, and path
combination. Another application on the same ingress controller must use a
different path, such as `/grafana`, or later use a different DNS hostname. If
two Ingress resources both claim the hostless `/` path, routing is ambiguous
and controller-specific.

### Access with DNS and TLS

Many applications can share one public IP and ports `80` and `443`. DNS names
distinguish them; the DNS record itself does not contain an application Service
port.

```text
cloudcost.example.com -> 20.10.30.40 -> CloudCost Ingress rule
grafana.example.com   -> 20.10.30.40 -> Grafana Ingress rule
```

Set the relevant `host` fields under `backend.ingress.hosts` and
`frontend.ingress.hosts`, then configure `tls` with the Kubernetes TLS Secret.
Both Ingress resources must use the ingress class handled by the intended
controller, currently:

```yaml
className: nginx
```

If the cluster has multiple ingress controllers, assign each one a distinct
IngressClass and set `className` accordingly. Each controller can use its own
LoadBalancer and public IP, or several applications can safely share one
controller using different hostnames or non-conflicting paths.

## Frontend runtime API URL

The frontend image can be reused across environments. When
`frontend.runtimeConfig.enabled` is `true`, an init container rewrites the
frontend bundle at pod startup:

```yaml
frontend:
  runtimeConfig:
    enabled: true
    apiBaseUrl: "/"
    replaceFrom: "http://127.0.0.1:8000"
```

With the default `apiBaseUrl: "/"`, the browser calls the same public host that
served the frontend, and the Ingress routes `/api/...` to the backend.

## Backend workload and scaling

`backend.workload.kind` accepts `Deployment` or `StatefulSet`.

The backend currently runs scheduled workers inside the application process.
Keep it at one replica, with its PodDisruptionBudget and autoscaling disabled,
unless the API and scheduled-worker responsibilities are separated. Otherwise,
multiple replicas can run the same scheduled jobs more than once.

The frontend is stateless and can be scaled horizontally.

Autoscaling is optional for both backend and frontend. The chart supports CPU
and memory utilization targets:

```yaml
autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

Keep backend autoscaling disabled while background workers run inside the
backend process. Frontend autoscaling is safer because the frontend is stateless.

## Production checklist

- Replace `backend.secrets.secretKey` with a long random value encoded according
  to `backend.secrets.encoding`.
- Use immutable backend and frontend image tags or digests instead of `latest`.
- Configure DNS, TLS, and an ingress controller appropriate for the cluster.
- Use durable database storage and establish backup and restore procedures, or
  use managed PostgreSQL.
- Verify CPU and memory requests and limits against measured usage.
- Keep the backend at one replica until background workers are separated.
- Restrict network access with appropriate firewall rules and Kubernetes
  NetworkPolicies.
- Test `helm lint`, rendered manifests, installation, upgrade, rollback, and
  database restore in a non-production environment.

## Verification and troubleshooting

```sh
helm status cloudcost
kubectl -n cloudcost-test get pods,services,ingresses,pvc
kubectl -n cloudcost-test get jobs
```

If the Ingress has no public address, check the ingress controller Service, not
the application Services:

```sh
kubectl -n ingress-nginx get service
kubectl get ingressclass
```

If the application cannot connect to PostgreSQL, confirm the selected database
mode and inspect the relevant Secret without printing its values:

```sh
kubectl -n cloudcost-test get secret cloudcost-postgres-auth
kubectl -n cloudcost-test describe pod <backend-pod-name>
```
