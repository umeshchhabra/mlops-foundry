# Multi-project feature-store infrastructure

The platform supplies shared Redis and MinIO services, while each development
repository owns its Feast definitions, server, and Airflow materialization DAG.
No developer project name is hardcoded in this infrastructure repository.

## Add a project

Choose a Feast project name containing lowercase letters, numbers, and
underscores. Run the matching helper once from the infrastructure repository:

```powershell
pwsh ./scripts/configure-feast-project.ps1 -Project <project_name>
```

```bash
./scripts/configure-feast-project.sh <project_name>
```

For an input such as `<project_name>`, the helper creates:

- Kubernetes namespace `feast-<project-name>` with the feature-client label;
- MinIO bucket `feast-<project-name>` (S3 names use hyphens, not underscores);
- ConfigMap `feast-platform` containing the Feast project, registry path,
  offline-data prefix, and shared service endpoints;
- Secret `feast-platform-access` containing runtime-only MinIO and Redis access.

The generated registry is `s3://feast-<project-name>/registry.pb`, and offline
feature files belong below `s3://feast-<project-name>/offline/`. A separate
bucket prevents one project's registry or data lifecycle from colliding with
another project's. The shared Redis online store uses Feast's `project` value
as its logical namespace.

The helper is idempotent. Re-running it refreshes the namespace configuration,
secret, and bucket without deleting project data.

## Development-repository contract

Each development repository should deploy its Feast server into the generated
namespace and read `feast-platform` plus `feast-platform-access` as environment
configuration. It owns:

- a unique Feast `project` value;
- feature definitions and transformations;
- `feature_store.yaml` generation;
- the Feast server Deployment and ClusterIP Service on port `6566`;
- an Airflow DAG that serializes `feast apply` and
  `feast materialize-incremental` for that project.

Use `redis.mlops.svc.cluster.local:6379` as the online store and
`http://minio.mlops.svc.cluster.local:9000` as the S3 endpoint. Do not commit
the values from `feast-platform-access` into the development repository.

For local access to a project's Feast server, use a port-forward rather than a
fixed NodePort so multiple projects do not compete for the same host port:

```bash
kubectl -n feast-<project-name> port-forward service/feast-server 6566:6566
```

This local-lab implementation gives projects separate namespaces and buckets,
but they currently share MinIO and Redis credentials. That is organizational
isolation, not a security boundary. Per-project MinIO users and Redis instances
can be introduced later if mutually untrusted teams use the cluster.
