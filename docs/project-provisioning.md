# Project provisioning

This document describes the handoff between a model-training team and the
platform team. The platform runs shared services once; it does not deploy a
project's training pod, Feast server, or KServe model service.

## Request from a training team

Give the platform team a stable project ID and the services required. Project
IDs use lowercase letters, numbers, and underscores. Examples of supported
services are `artifacts`, `mlflow`, `airflow`, `kserve`, and `feast`.

```text
Project: <project_id>
Display name: <human-readable name>
Services: artifacts, mlflow, airflow, kserve, feast
Airflow slots: 1
```

## What the platform team provisions

| Requested service | Platform resource created |
| --- | --- |
| `artifacts` | A dedicated MinIO bucket and an access policy limited to that bucket. |
| `mlflow` | A named MLflow experiment whose artifacts are stored under that bucket. |
| `airflow` | An Airflow pool named for the project, limiting concurrent work. |
| `kserve` | A catalog entry confirming the shared KServe controller is available; no model is deployed. |
| `feast` | Registry and offline-data locations in the bucket plus the shared Redis endpoint. |

Every request is recorded in a non-sensitive ConfigMap in the `mlops` namespace.
Storage credentials are held in a project-specific Kubernetes Secret in the
same namespace. The platform team shares those credentials through an approved
private channel; they are never committed to Git.

No Kubernetes namespace, Deployment, Service, Airflow DAG, training Job, Feast
server, or KServe `InferenceService` is created by this provisioning process.
Those are development-project workloads and remain owned by the development
repository.

## Provisioning commands

Windows PowerShell:

```powershell
pwsh ./scripts/provision-project-resources.ps1 `
  -Project <project_id> `
  -DisplayName '<project display name>' `
  -Services artifacts,mlflow,airflow,kserve,feast `
  -AirflowSlots 1
```

Linux:

```bash
./scripts/provision-project-resources.sh \
  --project <project_id> \
  --display-name '<project display name>' \
  --services artifacts,mlflow,airflow,kserve,feast \
  --airflow-slots 1
```

Both scripts are idempotent. Re-running one retains the existing project MinIO
access key and secret, refreshes the bucket policy, and updates the catalog
record. The scripts require `kubectl`; the Linux version also requires `curl`,
`openssl`, and `sha256sum`.

## What the development team receives

The platform team supplies the project bucket name, MinIO credentials, MLflow
tracking URI and experiment name, Airflow pool name, and—when Feast is
requested—the registry path, offline prefix, Redis host, and Redis password.
The development repository then uses those values in its own pipeline and
deployment configuration.
