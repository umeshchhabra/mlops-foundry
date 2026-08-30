# Network policies

The platform applies default-deny ingress and egress in `mlops` and `models`,
then allows only the paths required by this local stack: same-namespace
traffic, cluster DNS, model-to-MinIO access, and local NodePort ingress.

These policies require a CNI that enforces NetworkPolicy. Kind’s default
networking does not enforce all policy rules; verify behavior on the target
Linux CNI before relying on them as a security boundary.
