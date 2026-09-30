# Linux and Raspberry Pi compatibility test

This is a test path for running the same GitOps repository on a Linux host or
ARM64 Raspberry Pi, not a production migration.

Requirements: 64-bit Linux, Docker, Kind, kubectl, Helm, Git, Python 3, and at
least 8 GB RAM. Use an SSD and set MLOPS_DATA_DIR to its mount point.

~~~bash
git clone https://github.com/umeshchhabra/mlops-foundry.git
cd mlops-foundry
MLOPS_DATA_DIR=/mnt/mlops-data ./scripts/bootstrap-kind.sh
~~~

The bootstrap automatically builds images/mlflow/Dockerfile on the host and
loads the native image into Kind. The official Airflow image is pulled by
Kubernetes. Install Argo CD, configure the private-repository credential, and
apply the root Application next. Use the health checker to validate the result:

~~~bash
python3 ./health/check-stack.py
~~~

Before testing, confirm the MLflow base image supports the Pi CPU architecture:

~~~bash
docker buildx imagetools inspect ghcr.io/mlflow/mlflow:v3.4.0
~~~

The kind.yaml.tpl file is rendered at runtime; do not commit a generated file
containing a local data path.
