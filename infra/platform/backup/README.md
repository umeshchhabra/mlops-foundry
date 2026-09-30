# Platform backups

The core-platform Argo CD application creates platform-backups-pvc and three
daily backup CronJobs plus one retention CronJob in mlops:

- postgres-backup writes compressed pg_dumpall files under /backup/postgres.
- minio-backup mirrors every MinIO bucket under timestamped directories in
  /backup/minio.
- redis-backup writes Redis snapshots under /backup/redis.
- backup-retention removes files and MinIO backup directories older than 14
  days.

All backup jobs retain 14 days of backups and read credentials from platform-secrets;
no credentials or backup contents are stored in Git. Redis online-store
snapshots are written beside the PostgreSQL and MinIO backups; online features
can also be rebuilt from each project's offline feature data.

The PVC is an operational staging area, not an off-host disaster-recovery copy.
Periodically copy it to independent storage for real recovery protection.

Inspect jobs and copy a backup out with:

~~~bash
kubectl -n mlops get cronjobs,jobs
kubectl -n mlops cp <backup-pod>:/backup ./backups
~~~

Restore PostgreSQL by piping a selected sql.gz file to psql with the
platform-secrets database credentials. Restore MinIO by copying the selected
bucket directory back with mc mirror; test restores on an isolated cluster
before replacing live data.

The included restore-test.sh performs a safe dry-run path check by default:

~~~bash
./infra/platform/backup/restore-test.sh --postgres-backup ./backups/postgres/example.sql.gz
~~~

Use --apply only for a deliberate restore into the local PostgreSQL service.
