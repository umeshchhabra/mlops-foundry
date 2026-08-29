# Linux and Raspberry Pi compatibility test

This is a test path for running the same GitOps repository on a Linux host or
ARM64 Raspberry Pi, not a production migration.

Requirements: 64-bit Linux, Docker, Kind, kubectl, Helm, Git, OpenSSL, and at
least 8 GB RAM. Use an SSD; set `MLOPS_DATA_DIR` to its mount point.

```bash
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR=/mnt/mlops-data ./scripts/bootstrap-kind-linux.sh
```

The bootstrap automatically builds `images/mlflow/Dockerfile` on the host and
loads the native image into Kind. Install Argo CD, configure the private-
repository credential, and apply the root Application next. Use
`pwsh ./health/check-stack.ps1` to validate the result.

Before testing, confirm the MLflow base image supports the Pi's CPU architecture:

```bash
docker buildx imagetools inspect ghcr.io/mlflow/mlflow:v3.4.0
```

The `kind-linux.yaml.tpl` file is rendered at runtime; do not commit a generated
file containing a local data path.
