# Stack health check

Run before and after platform changes:

```powershell
pwsh ./health/check-stack.ps1
```

During a first installation, wait for Argo CD reconciliation with:

```powershell
pwsh ./health/wait-for-stack.ps1
```

It checks node readiness, Argo CD application state, workload pod readiness,
the KServe controller, Redis, Feast bucket initialization, and the MLflow, MinIO, Prometheus, and Grafana health
endpoints. It also requires a successful kube-state-metrics scrape and node
metrics for every Kubernetes node plus a healthy Redis exporter, so a responsive Prometheus UI alone is not
enough to pass. API server, kubelet, cAdvisor, and KServe controller scrapes must also be up.

KServe controller metrics use a dedicated HTTPS job with the Prometheus service
account token; the generic anonymous job excludes this endpoint. The RBAC proxy
stays enabled. Only this local-lab job skips certificate verification because
the proxy generates a self-signed certificate. Use a trusted serving certificate
before treating this as an untrusted-network or production configuration.

Monitoring pods need API access through the namespace's default-deny policy.
Both bootstrap scripts configure this automatically. For an existing cluster,
or after its API addresses change, run:

```powershell
pwsh ./scripts/configure-monitoring-network.ps1
pwsh ./health/wait-for-stack.ps1
```

The helper discovers API service and endpoint addresses and allows only their
TCP ports for Prometheus and kube-state-metrics. It does not allow internet
egress or hardcode machine-specific addresses.
