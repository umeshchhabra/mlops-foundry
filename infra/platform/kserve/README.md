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

The default `kserve-models` application seeds a small Iris sklearn demo model
into MinIO one time and deploys it as `models/sklearn-iris`. It is intended as
a platform verification workload, not as a production model. After the
bootstrap Job and service are ready, access it locally:

```powershell
kubectl -n models wait --for=condition=Ready inferenceservice/sklearn-iris --timeout=5m
kubectl -n models port-forward service/sklearn-iris-predictor 8081:80
```

Then send a KServe v2 prediction request to `http://localhost:8081/v2/models/sklearn-iris/infer`:

```powershell
$body = '{"inputs":[{"name":"predict","shape":[1,4],"datatype":"FP32","data":[[5.1,3.5,1.4,0.2]]}]}'
Invoke-RestMethod http://localhost:8081/v2/models/sklearn-iris/infer -Method Post -ContentType 'application/json' -Body $body
```

Until an ingress/gateway is deliberately introduced, port-forward is the
intended local access method. The bootstrap Job is part of the Argo CD
application and must complete before the model service is created.
