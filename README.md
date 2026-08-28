# MLOps Foundry

GitOps source of truth for the local Kind-based MLOps platform.

Argo CD bootstraps from `infra/bootstrap/root-application.yaml` and reconciles
the applications in `infra/argocd/apps`. Credentials are created directly in
Kubernetes and are deliberately excluded from this repository.
