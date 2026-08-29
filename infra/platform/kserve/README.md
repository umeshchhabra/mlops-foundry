# KServe model-serving workflow

KServe runs in Standard mode. This avoids the Knative/Istio serverless stack
while retaining KServe `InferenceService` resources and built-in serving
runtimes. Model artifacts should be placed in MinIO and referenced by an
`InferenceService` using an `s3://` storage URI.

The first model should be added in a separate feature branch after choosing its
framework and artifact location. Until an ingress/gateway is deliberately
introduced, access a model service with `kubectl -n <namespace> port-forward`.
