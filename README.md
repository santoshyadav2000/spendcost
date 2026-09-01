# CloudCost Helm Charts

This repository contains the Helm chart for deploying the CloudCost platform.

## Setup

```sh
helm repo add cloudcost https://santoshyadav2000.github.io/spendcost/
helm repo update
```

Then install with:

```sh
helm upgrade --install cloudcost cloudcost/cloudcost -n cloudcost --create-namespace
```

### Customizing values when installing from the repository

Since `helm repo add`/`helm install cloudcost/cloudcost` doesn't give you a
local `values.yaml` to edit, add the repo, then pull and unpack the chart:

```sh
helm repo add cloudcost https://santoshyadav2000.github.io/spendcost/
helm repo update cloudcost
helm pull cloudcost/cloudcost --untar
cd cloudcost
```

Edit `values.yaml` as usual, then install with the local path:

```sh
helm upgrade --install cloudcost . -n cloudcost --create-namespace
```

See [charts/cloudcost/README.md](charts/cloudcost/README.md) for full configuration details, database modes, secrets, ingress setup, and troubleshooting.
