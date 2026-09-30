#!/usr/bin/env python3
"""Allow monitoring workloads to reach only the Kubernetes API endpoints."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import subprocess
import sys
from typing import Any


def kubectl_json(context: str, *arguments: str) -> dict[str, Any]:
    result = subprocess.run(
        ["kubectl", "--context", context, *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Configure monitoring egress for the current Kubernetes API addresses."
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

    try:
        service = kubectl_json(
            arguments.context, "-n", "default", "get", "service", "kubernetes", "-o", "json"
        )
        endpoint_slices = kubectl_json(
            arguments.context,
            "-n",
            "default",
            "get",
            "endpointslices",
            "-l",
            "kubernetes.io/service-name=kubernetes",
            "-o",
            "json",
        )
    except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        print(f"Cannot read Kubernetes API addresses: {detail.strip()}", file=sys.stderr)
        return 1

    addresses = set(service.get("spec", {}).get("clusterIPs") or [])
    ports = {
        port["port"]
        for port in service.get("spec", {}).get("ports") or []
        if port.get("port") is not None
    }
    for endpoint_slice in endpoint_slices.get("items") or []:
        for endpoint in endpoint_slice.get("endpoints") or []:
            addresses.update(endpoint.get("addresses") or [])
        ports.update(
            port["port"]
            for port in endpoint_slice.get("ports") or []
            if port.get("port") is not None
        )

    peers: list[dict[str, dict[str, str]]] = []
    for address in sorted(address for address in addresses if address and address != "None"):
        try:
            parsed = ipaddress.ip_address(address)
        except ValueError:
            print(f"Invalid Kubernetes API address: {address}", file=sys.stderr)
            return 1
        peers.append({"ipBlock": {"cidr": f"{parsed}/{parsed.max_prefixlen}"}})

    if not peers or not ports:
        print("Kubernetes API addresses or ports are missing.", file=sys.stderr)
        return 1

    policy = {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "NetworkPolicy",
        "metadata": {
            "name": "monitoring-allow-kubernetes-api",
            "namespace": arguments.namespace,
        },
        "spec": {
            "podSelector": {
                "matchExpressions": [
                    {
                        "key": "app.kubernetes.io/name",
                        "operator": "In",
                        "values": ["prometheus", "kube-state-metrics"],
                    }
                ]
            },
            "policyTypes": ["Egress"],
            "egress": [
                {
                    "to": peers,
                    "ports": [
                        {"protocol": "TCP", "port": port} for port in sorted(ports)
                    ],
                }
            ],
        },
    }

    try:
        subprocess.run(
            ["kubectl", "--context", arguments.context, "apply", "-f", "-"],
            check=True,
            input=json.dumps(policy),
            text=True,
        )
    except subprocess.CalledProcessError as error:
        print(f"Failed to configure monitoring API egress: {error}", file=sys.stderr)
        return 1

    print("Monitoring API-only egress configured from current cluster addresses.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
