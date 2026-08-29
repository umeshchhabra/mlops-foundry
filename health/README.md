# Stack health check

Run before and after platform changes:

```powershell
pwsh ./health/check-stack.ps1
```

It checks node readiness, Argo CD application state, workload pod readiness,
and the MLflow, MinIO, Prometheus, and Grafana health endpoints.
