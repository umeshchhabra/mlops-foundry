# Local training pipeline

`airflow/dags/train_model.py` is a deliberately small training workflow. It
uses the Airflow image's existing scikit-learn package, trains an Iris
classifier, and logs the run, parameters, and metric through MLflow's REST API.
This keeps the demo runnable when cluster egress to PyPI is disabled.

Copy the DAG into the Airflow DAG PVC (the current deployment intentionally has
Git sync disabled), trigger `home_train_and_log` from the Airflow UI, and
confirm the run in MLflow. A minimal promotion helper validates a finished run
and generates a KServe manifest after the model artifact has been uploaded to
MinIO:

```powershell
pwsh ./scripts/promote-mlflow-run.ps1 -RunId <run-id> `
  -ModelUri s3://models/my-model
kubectl apply -f infra/platform/kserve/models/promoted-inferenceservice.yaml
```

This first version uses a built-in dataset so the infrastructure path can be
verified without committing data or credentials. DVC input and feature-store
lookup can be added to the task once the basic loop is working.
