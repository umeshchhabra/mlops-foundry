# Airflow deployment

Airflow is deployed by the `airflow` Argo CD Application using the official
Apache Airflow Helm chart. It uses the existing `postgres` service for metadata,
the `airflow-pvc` claim for DAG files, and the `airflow-logs` MinIO bucket for
remote task logs. The chart does not install PostgreSQL, Redis, or a second
object store.

Before merging/deploying the Application on a local Kind cluster, create the
runtime-only Secrets:

```powershell
pwsh ./scripts/configure-airflow-secrets.ps1
```

The second command prompts for the Airflow `admin` password. It derives the
metadata connection from `platform-secrets`, generates the Fernet/API/JWT keys,
and applies them only to Kubernetes. Nothing sensitive is written to Git or to
the working tree.

Argo CD then runs an idempotent pre-sync Job that creates the `airflow` database
and the `airflow-logs` bucket. The UI is exposed through the existing Kind host
mapping at `http://localhost:8090` (`NodePort` 31080). DAG deployment is
intentionally separate from platform GitOps: copy or synchronize DAG files to
the `airflow-pvc` claim. Enable `dags.gitSync` only after choosing a dedicated,
reviewed DAG repository and its Kubernetes credential.
