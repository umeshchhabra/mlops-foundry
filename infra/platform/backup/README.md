# Platform backups

The `core-platform` Argo CD application creates `platform-backups-pvc` and
two daily backup CronJobs and one retention CronJob in `mlops`:

- `postgres-backup` writes compressed `pg_dumpall` files under
  `/backup/postgres`.
- `minio-backup` mirrors every MinIO bucket under timestamped directories in
  `/backup/minio`.
- `backup-retention` removes files and MinIO backup directories older than 14
  days.

Both jobs retain 14 days of backups and read credentials from
`platform-secrets`; no credentials or backup contents are stored in Git.

The PVC is an operational staging area, not an off-host disaster-recovery
copy. Periodically copy it to independent storage for real recovery protection.

Inspect jobs and copy a backup out with:

```powershell
kubectl -n mlops get cronjobs,jobs
kubectl -n mlops cp <backup-pod>:/backup ./backups
```

Restore PostgreSQL by piping a selected `.sql.gz` file to `psql` with the
`platform-secrets` database credentials. Restore MinIO by copying the selected
bucket directory back with `mc mirror`; test restores on an isolated cluster
before replacing live data.

The included `restore-test.ps1` performs a safe dry-run path check by default.
Use `-Apply` only for a deliberate restore into the local PostgreSQL service.
