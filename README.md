# CloudCost Helm Chart

Umbrella Helm chart that installs the full CloudCost platform:

| Component | Subchart | Workload | Port |
|---|---|---|---|
| FastAPI backend (+ background workers) | `charts/backend` | Deployment (switchable to StatefulSet) | 8000 |
| React UI (nginx) | `charts/frontend` | Deployment | 80 |
| PostgreSQL | `charts/database` | StatefulSet | 5432 |

Everything is configured from a **single file: `values.yaml`**. The same file
works in any environment — you just set the values to match where you install.
It is offline / air-gap friendly (no registry pulls needed when images are
loaded locally).

```
helm/
├── Chart.yaml            # umbrella chart definition
├── values.yaml           # << THE ONLY FILE YOU EDIT (all settings live here)
├── templates/            # namespace + shared helpers
└── charts/               # internal component defaults (you don't edit these)
    ├── database/         # PostgreSQL StatefulSet
    ├── backend/          # FastAPI (workload kind is dynamic)
    └── frontend/         # React + nginx (runtime API-URL injection)
```

> You only ever edit the top-level `values.yaml`. The `values.yaml` files inside
> `charts/` are internal defaults that `values.yaml` overrides.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- Container images available to the cluster:
  - `cloudcost-backend`  (built from `../costmanagement/Dockerfile`)
  - `cloudcost-ui`       (built from `../costmanagement_ui/Dockerfile`)
  - `postgres:16-alpine` (or an internal mirror)

### Build the images

```sh
# Backend
docker build -t cloudcost-backend:latest ../costmanagement

# Frontend  (the API URL is a placeholder; it is rewritten at runtime by Helm)
docker build -t cloudcost-ui:latest \
  --build-arg VITE_API_BASE_URL=http://127.0.0.1:8000 \
  ../costmanagement_ui
```

## Install

1. Open `values.yaml` and set the values for your environment (namespace,
   database password, image names, ingress hosts, secrets, storage).
2. Validate, then install:

```sh
helm lint .
helm template cloudcost . | less        # preview the generated Kubernetes YAML
helm upgrade --install cloudcost .
```

Secrets can be passed at install time instead of writing them into the file:

```sh
helm upgrade --install cloudcost . \
  --set backend.secrets.secretKey=$SECRET_KEY \
  --set backend.secrets.googleClientSecret=$GSECRET \
  --set database.auth.password=$DBPASS
```

## Using your own (external) database

By default the chart deploys PostgreSQL for you. To use an existing database:

1. In `values.yaml`, set `database.enabled: false`.
2. Set the full connection string in `backend.database.url` (URL-encode special
   characters in the password):

```yaml
database:
  enabled: false

backend:
  database:
    url: "postgresql+asyncpg://cloudcost:Infra%40%23%24%267777@10.0.0.5:5432/cloudcost_db"
```

## Dynamic storage backends

Set `persistence.type` (database and backend) to choose the volume source:

| `type` | Backing | Notes |
|---|---|---|
| `pvc` | dynamic PVC via `storageClass` | default; `""` uses the cluster default class |
| `azureDisk` | Azure Managed Disk CSI | `storageClass: managed-csi`, RWO (best for the DB) |
| `azureFile` | Azure Files CSI (SMB) | `storageClass: azurefile-csi`, supports RWX |
| `azureBlob` | Azure Blob CSI (blobfuse) | `storageClass: azureblob-fuse-premium` |
| `local` | node `hostPath` | dev / single-node only |
| `emptyDir` | ephemeral | data lost on restart — not for real data |

The database uses `volumeClaimTemplates` for dynamic types. The backend can
optionally persist the billing CSV assets directory (`backend.persistence`).

## Backend workload kind (dynamic)

`backend.workload.kind` accepts `Deployment` (default) or `StatefulSet`.

> The backend starts background workers **in-process**. Running more than one
> replica duplicates scheduled jobs, so `replicaCount` stays at `1`.

## Database migrations

A Helm post-install/post-upgrade hook Job runs `alembic upgrade head`. It waits
for the database TCP port first and injects the connection URL from the backend
Secret. Toggle with `backend.migrations.enabled`.

## Networking

The frontend and backend use **separate Ingress hosts**. The frontend's API URL
is injected at pod startup via `frontend.runtimeConfig.apiBaseUrl`, so the image
does not need rebuilding to point at a different backend.

> **CORS note:** the backend allows a fixed set of browser origins (defined in
> `costmanagement/src/middleware.py`). The frontend host you expose must be one
> of those origins, otherwise the browser will block API calls. Update that list
> in the backend if you add a new frontend host.

## Security notes

- All sensitive values (DB password, JWT secret, Google OAuth, SMTP) render into
  a Kubernetes `Secret`, never a ConfigMap.
- For production, prefer `existingSecret` (backend + database) over inline values
  so credentials never live in `values.yaml`.
