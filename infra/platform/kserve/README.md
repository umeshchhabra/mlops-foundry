# KServe platform service

KServe runs in Standard mode. This avoids the Knative/Istio serverless stack
while retaining the KServe controller, `InferenceService` APIs, and built-in
serving-runtime support.

Model-serving workloads are intentionally not stored here. The development
repository owns its model namespace, service account, storage credential,
`ServingRuntime`, and `InferenceService` definitions. Those workloads can place
artifacts in this platform's MinIO service and reference them with `s3://` URIs.

Until an ingress or gateway is deliberately introduced, development workloads
can expose generated predictor services locally with `kubectl port-forward`.
