#!/usr/bin/env python3
"""Validate the shared MLOps platform without requiring third-party Python packages."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.parse
from typing import Any, Optional


class ClusterCheck:
    def __init__(self, context: str, namespace: str, argocd_namespace: str, kserve_namespace: str):
        self.context = context
        self.namespace = namespace
        self.argocd_namespace = argocd_namespace
        self.kserve_namespace = kserve_namespace
        self.failures: list[str] = []

    def kubectl(
        self, *arguments: str, timeout: Optional[int] = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["kubectl", "--context", self.context, *arguments],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    def json(self, *arguments: str) -> dict[str, Any] | None:
        result = self.kubectl(*arguments)
        if result.returncode:
            detail = result.stderr.strip() or result.stdout.strip() or "unknown kubectl error"
            self.failures.append(f"Cannot read {' '.join(arguments)}: {detail}")
            return None
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as error:
            self.failures.append(f"Cannot parse {' '.join(arguments)}: {error}")
            return None

    def require_endpoint(self, endpoint: str) -> None:
        result = self.kubectl("get", "--raw", endpoint)
        if result.returncode:
            self.failures.append(f"Endpoint failed: {endpoint}")

    @staticmethod
    def pod_ready(pod: dict[str, Any]) -> bool:
        status = pod.get("status") or {}
        if status.get("phase") != "Running":
            return False
        return all(
            container.get("ready", False)
            for container in status.get("containerStatuses") or []
        )

    def check_nodes(self) -> int:
        nodes = self.json("get", "nodes", "-o", "json")
        if nodes is None:
            return 0
        items = nodes.get("items") or []
        for node in items:
            conditions = (node.get("status") or {}).get("conditions") or []
            ready = any(
                condition.get("type") == "Ready" and condition.get("status") == "True"
                for condition in conditions
            )
            if not ready:
                self.failures.append(f"Node not Ready: {node.get('metadata', {}).get('name', '<unknown>')}")
        return len(items)

    def check_applications(self) -> None:
        applications = self.json(
            "get", "applications", "-n", self.argocd_namespace, "-o", "json"
        )
        if applications is None:
            return
        for application in applications.get("items") or []:
            status = application.get("status") or {}
            sync = (status.get("sync") or {}).get("status")
            health = (status.get("health") or {}).get("status")
            if sync != "Synced" or health != "Healthy":
                name = application.get("metadata", {}).get("name", "<unknown>")
                self.failures.append(f"Argo application unhealthy: {name} ({sync}/{health})")

    def check_pods(self, namespace: str, description: str) -> None:
        pods = self.json("get", "pods", "-n", namespace, "-o", "json")
        if pods is None:
            return
        for pod in pods.get("items") or []:
            phase = (pod.get("status") or {}).get("phase")
            if phase in {"Succeeded", "Completed", "Failed"}:
                continue
            if not self.pod_ready(pod):
                name = pod.get("metadata", {}).get("name", "<unknown>")
                self.failures.append(f"{description} pod unhealthy: {name} ({phase})")

    def check_redis(self) -> None:
        redis = self.json("get", "deployment", "redis", "-n", self.namespace, "-o", "json")
        if redis is None:
            return
        replicas = (redis.get("status") or {}).get("availableReplicas") or 0
        if replicas < 1:
            self.failures.append("Redis deployment has no available replica.")

    def check_prometheus(self, node_count: int) -> None:
        checks = [
            (
                'up{service="prometheus-kube-state-metrics"} == 1',
                1,
                "kube-state-metrics scrape",
            ),
            (
                "count(count by (node) (kube_node_info))",
                node_count,
                "Kubernetes node metrics",
            ),
            (
                'count(up{job="kubernetes-apiservers"} == 1)',
                1,
                "API server scrape",
            ),
            ("up{job=\"kserve-controller\"} == 1", 1, "KServe controller scrape"),
            ("redis_up == 1", 1, "Redis exporter scrape"),
            (
                'count(up{job="kubernetes-nodes"} == 1)',
                node_count,
                "Kubelet scrapes",
            ),
            (
                'count(up{job="kubernetes-nodes-cadvisor"} == 1)',
                node_count,
                "cAdvisor scrapes",
            ),
        ]
        for query, minimum, name in checks:
            endpoint = (
                f"/api/v1/namespaces/{self.namespace}/services/"
                f"http:prometheus-server:80/proxy/api/v1/query?query="
                f"{urllib.parse.quote(query, safe='')}"
            )
            result = self.kubectl("--request-timeout=15s", "get", "--raw", endpoint)
            try:
                response = json.loads(result.stdout)
                samples = response["data"]["result"]
                value = float(samples[0]["value"][1])
                if result.returncode or response.get("status") != "success" or value < minimum:
                    raise ValueError(f"expected a value of at least {minimum}")
            except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as error:
                self.failures.append(f"Monitoring check failed: {name}: {error}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Check the shared MLOps platform.")
    parser.add_argument(
        "--context", default=os.environ.get("KUBE_CONTEXT", "kind-mlops"), help="Kubernetes context"
    )
    parser.add_argument(
        "--namespace", default=os.environ.get("MLOPS_NAMESPACE", "mlops"), help="Platform namespace"
    )
    parser.add_argument(
        "--argocd-namespace",
        default=os.environ.get("ARGOCD_NAMESPACE", "argocd"),
        help="Argo CD namespace",
    )
    parser.add_argument(
        "--kserve-namespace",
        default=os.environ.get("KSERVE_NAMESPACE", "kserve"),
        help="KServe namespace",
    )
    arguments = parser.parse_args()

    if shutil.which("kubectl") is None:
        print("Missing required command: kubectl", file=sys.stderr)
        return 1

    check = ClusterCheck(
        arguments.context,
        arguments.namespace,
        arguments.argocd_namespace,
        arguments.kserve_namespace,
    )
    node_count = check.check_nodes()
    check.check_applications()
    check.check_pods(arguments.namespace, "Workload")
    check.check_pods(arguments.kserve_namespace, "KServe")
    for endpoint in (
        f"/api/v1/namespaces/{arguments.namespace}/services/http:mlflow:5000/proxy/health",
        f"/api/v1/namespaces/{arguments.namespace}/services/http:minio:9000/proxy/minio/health/live",
        f"/api/v1/namespaces/{arguments.namespace}/services/http:prometheus-server:80/proxy/-/ready",
        f"/api/v1/namespaces/{arguments.namespace}/services/http:grafana:80/proxy/api/health",
    ):
        check.require_endpoint(endpoint)
    check.check_redis()
    check.check_prometheus(node_count)

    if check.failures:
        for failure in check.failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    print("Stack health check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
