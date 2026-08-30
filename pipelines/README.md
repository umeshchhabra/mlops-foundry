# Local training pipeline

`airflow/dags/train_model.py` is a deliberately small training workflow. It
uses Airflow's `PythonVirtualenvOperator` to install pinned task dependencies,
trains an Iris classifier, and logs the model, parameters, and metric to the
existing MLflow and MinIO services.

Copy the DAG into the Airflow DAG PVC (the current deployment intentionally has
Git sync disabled), trigger `home_train_and_log` from the Airflow UI, and
confirm the run in MLflow. Model promotion to KServe is a separate next step.

This first version uses a built-in dataset so the infrastructure path can be
verified without committing data or credentials. DVC input and feature-store
lookup can be added to the task once the basic loop is working.
