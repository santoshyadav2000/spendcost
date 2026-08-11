# CloudCost Helm Chart

Helm chart for installing the CloudCost platform on Kubernetes.

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

Back up this Secret together with the database. If the release is uninstalled
but its PVC is retained, a later fresh installation can generate a different
password while the retained database still expects the old one.

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
