#!/usr/bin/env python3
"""Create the Airflow runtime secrets without writing any secret to disk."""


from __future__ import annotations

import argparse
import base64
import getpass
import json
import os
import secrets
import subprocess
import sys


def kubectl_secret_value(context: str, namespace: str, secret: str, key: str) -> str:
    result = subprocess.run(
        [
            "kubectl",
            "--context",
            context,
            "-n",
            namespace,
            "get",
            "secret",
            secret,
            "-o",
            f"jsonpath={{.data.{key}}}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    if not result.stdout:
        raise ValueError(f"{secret}/{key} is required.")
    return base64.b64decode(result.stdout).decode("utf-8")


def secret_manifest(namespace: str, name: str, key: str, value: str) -> dict[str, object]:
    return {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": name, "namespace": namespace},
        "stringData": {key: value},
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prompt for the Airflow admin password and apply runtime secrets."
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
    parser.add_argument(
        "--admin-password-stdin",
        action="store_true",
        help="Read the Airflow admin password from standard input instead of prompting",
    )
    arguments = parser.parse_args()

    try:
        db_uri = kubectl_secret_value(
            arguments.context, arguments.namespace, "platform-secrets", "AIRFLOW_DB_URI"
        )
    except (subprocess.CalledProcessError, ValueError, UnicodeDecodeError) as error:
        print(f"Cannot read Airflow metadata connection: {error}", file=sys.stderr)
        return 1

    if arguments.admin_password_stdin:
        admin_password = sys.stdin.readline().rstrip("\r\n")
    else:
        admin_password = getpass.getpass("Choose the Airflow admin password: ")
    if not admin_password:
        print("The Airflow admin password cannot be empty.", file=sys.stderr)
        return 2

    def random_secret() -> str:
        return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii")

    manifests = [
        secret_manifest(arguments.namespace, "airflow-metadata", "connection", db_uri),
        secret_manifest(
            arguments.namespace, "airflow-fernet-key", "fernet-key", random_secret()
        ),
        secret_manifest(
            arguments.namespace, "airflow-api-secret", "api-secret-key", random_secret()
        ),
        secret_manifest(
            arguments.namespace, "airflow-jwt-secret", "jwt-secret", random_secret()
        ),
        secret_manifest(arguments.namespace, "airflow-admin", "password", admin_password),
    ]
    try:
        for manifest in manifests:
            subprocess.run(
                ["kubectl", "--context", arguments.context, "apply", "-f", "-"],
                check=True,
                input=json.dumps(manifest),
                text=True,
            )
    except subprocess.CalledProcessError as error:
        print(f"Failed to apply Airflow secrets: {error}", file=sys.stderr)
        return error.returncode or 1

    print("Airflow secrets configured. They were applied to Kubernetes and not written to disk.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
