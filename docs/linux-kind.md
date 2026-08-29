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

Then build the MLflow image for the host architecture, load it into Kind, install
Argo CD, configure the private-repository credential, and apply the root
Application. Use `pwsh ./health/check-stack.ps1` to validate the result.

The `kind-linux.yaml.tpl` file is rendered at runtime; do not commit a generated
file containing a local data path.
