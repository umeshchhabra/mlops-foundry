#!/usr/bin/env python3
"""Configure the Argo CD credential for this private infrastructure repository."""


from __future__ import annotations

import argparse
import getpass
import json
import os
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply the read-only repository credential used by Argo CD."
    )
    parser.add_argument(
        "--context",
        default=os.environ.get("KUBE_CONTEXT", "kind-mlops"),
        help="Kubernetes context",
    )
    parser.add_argument(
        "--namespace",
        default=os.environ.get("ARGOCD_NAMESPACE", "argocd"),
        help="Argo CD namespace",
    )
    parser.add_argument(
        "--repository-url",
        default=os.environ.get(
            "MLOPS_REPOSITORY_URL",
            "https://github.com/umeshchhabra/mlops-foundry.git",
        ),
        help="Git repository URL",
    )
    arguments = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN") or getpass.getpass(
        "GitHub fine-grained token (read access to mlops-foundry): "
    )
    if not token:
        print("A non-empty GitHub token is required.", file=sys.stderr)
        return 2

    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": "repo-mlops-foundry",
            "namespace": arguments.namespace,
            "labels": {"argocd.argoproj.io/secret-type": "repository"},
        },
        "stringData": {
            "type": "git",
            "url": arguments.repository_url,
            "username": "x-access-token",
            "password": token,
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
        print(f"Failed to configure the Argo CD repository credential: {error}", file=sys.stderr)
        return error.returncode or 1

    print("Argo CD repository credential configured.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
