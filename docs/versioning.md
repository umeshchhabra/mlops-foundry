# Local MLOps versioning conventions

- DVC tracks datasets under `feature-store/data/` and `dev/data/`; commit the
  `.dvc` pointer, never the generated dataset or credentials.
- Use a short dataset version such as `iris-v1` and record it as an MLflow
  parameter or tag (`dataset_version`).
- Store trained artifacts under a stable MinIO prefix:
  `s3://models/<model-name>/<version>/`.
- Use semantic model versions (`1.0.0`, `1.1.0`) for deliberate releases; use
  the MLflow run ID for traceability.
- A KServe manifest should reference an immutable model prefix, not `latest`.
