#!/usr/bin/env python3
"""Create the platform runtime secrets directly in Kubernetes."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create local runtime-only secrets for the shared platform."
    )
    parser.add_argument(
        "--context",
        default=os.environ.get("KUBE_CONTEXT", "kind-mlops"),
        help="Kubernetes context",
    )
    parser.add_argument(
        "--namespace",
        default=os.environ.get("MLOPS_NAMESPACE", "mlops"),
        help="Platform namespace",
    )
    arguments = parser.parse_args()

    postgres_password = secrets.token_hex(16)
    airflow_password = secrets.token_hex(16)
    minio_password = secrets.token_hex(16)
    redis_password = secrets.token_hex(16)
    grafana_password = secrets.token_hex(16)
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": "platform-secrets", "namespace": arguments.namespace},
        "stringData": {
            "POSTGRES_USER": "mlflow",
            "POSTGRES_PASSWORD": postgres_password,
            "AIRFLOW_DB_PASSWORD": airflow_password,
            "AIRFLOW_DB_URI": (
                f"postgresql+psycopg2://airflow:{airflow_password}@postgres:5432/airflow"
            ),
            "MLFLOW_DB_URI": (
                f"postgresql+psycopg2://mlflow:{postgres_password}@postgres:5432/mlflow"
            ),
            "MINIO_ROOT_USER": "mlops-admin",
            "MINIO_ROOT_PASSWORD": minio_password,
            "AWS_ACCESS_KEY_ID": "mlops-admin",
            "AWS_SECRET_ACCESS_KEY": minio_password,
            "REDIS_PASSWORD": redis_password,
            "GRAFANA_ADMIN_USER": "admin",
            "GRAFANA_ADMIN_PASSWORD": grafana_password,
        },
    }
    try:
        subprocess.run(
            ["kubectl", "--context", arguments.context, "apply", "-f", "-"],
            check=True,
            input=json.dumps(secret),
            text=True,
        )
    except subprocess.CalledProcessError as error:
        print(f"Failed to create platform secrets: {error}", file=sys.stderr)
        return error.returncode or 1

    print("Runtime-only platform secrets created.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
