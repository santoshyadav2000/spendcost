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

See [charts/cloudcost/README.md](charts/cloudcost/README.md) for full configuration details, database modes, secrets, ingress setup, and troubleshooting.
