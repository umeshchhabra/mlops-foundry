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
the KServe controller, and the MLflow, MinIO, Prometheus, and Grafana health
endpoints.
