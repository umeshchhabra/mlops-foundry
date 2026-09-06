# Network policies

The platform applies default-deny ingress and egress in `mlops`, then allows
only the paths required by this local stack: same-namespace traffic, cluster
DNS, monitoring scrapes, and local NodePort ingress. Development repositories
own policies for their workload namespaces and any explicitly approved access
to platform services.

These policies require a CNI that enforces NetworkPolicy. Kind’s default
networking does not enforce all policy rules; verify behavior on the target
Linux CNI before relying on them as a security boundary.
