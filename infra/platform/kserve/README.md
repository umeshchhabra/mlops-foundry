# KServe model-serving workflow

KServe runs in Standard mode. This avoids the Knative/Istio serverless stack
while retaining KServe `InferenceService` resources and built-in serving
runtimes. Model artifacts should be placed in MinIO and referenced by an
`InferenceService` using an `s3://` storage URI.

The GitOps application creates a dedicated `models` namespace and a minimal
`kserve-model` service account. Configure its MinIO credentials locally after
the application is healthy:

```powershell
pwsh ./scripts/configure-kserve-storage.ps1
```

The script reads credentials from the existing `platform-secrets` Kubernetes
Secret and creates `kserve-minio-storage` only in the cluster; it never writes
credentials to the repository or disk.

An opt-in sklearn example is at
`infra/platform/kserve/examples/sklearn-iris-inferenceservice.yaml`. Upload a
compatible `model.joblib` to `s3://models/sklearn-iris/` first, then apply the
example and wait for `Ready=True`:

```powershell
kubectl apply -f ./infra/platform/kserve/examples/sklearn-iris-inferenceservice.yaml
kubectl -n models wait --for=condition=Ready inferenceservice/sklearn-iris --timeout=5m
kubectl -n models port-forward service/sklearn-iris-predictor 8081:80
```

Until an ingress/gateway is deliberately introduced, port-forward is the
intended local access method. The example is not part of the Argo CD
application, so an absent model artifact cannot make the platform unhealthy.
