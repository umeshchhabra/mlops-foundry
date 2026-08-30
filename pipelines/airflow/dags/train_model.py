"""Small end-to-end training task for local MLOps practice."""

import os
from datetime import datetime

from airflow import DAG
from airflow.providers.standard.operators.python import PythonVirtualenvOperator


def train_and_log() -> None:
    import mlflow
    import mlflow.sklearn
    from sklearn.datasets import load_iris
    from sklearn.linear_model import LogisticRegression

    mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
    mlflow.set_experiment("home-mlops-training")
    features, labels = load_iris(return_X_y=True)

    with mlflow.start_run() as run:
        model = LogisticRegression(max_iter=1000).fit(features, labels)
        accuracy = float(model.score(features, labels))
        mlflow.log_metric("training_accuracy", accuracy)
        mlflow.log_param("model_type", "logistic_regression")
        mlflow.log_param("training_rows", len(features))
        mlflow.sklearn.log_model(model, "model")
        print(f"MLflow run_id={run.info.run_id} accuracy={accuracy:.4f}")


with DAG(
    dag_id="home_train_and_log",
    start_date=datetime(2025, 1, 1),
    schedule=None,
    catchup=False,
    tags=["training", "mlflow", "local"],
) as dag:
    train = PythonVirtualenvOperator(
        task_id="train_and_log",
        python_callable=train_and_log,
        requirements=[
            "mlflow==3.4.0",
            "scikit-learn==1.5.2",
            "boto3==1.35.54",
        ],
        system_site_packages=False,
        env_vars={
            "MLFLOW_TRACKING_URI": "http://mlflow.mlops.svc.cluster.local:5000",
            "MLFLOW_S3_ENDPOINT_URL": "http://minio.mlops.svc.cluster.local:9000",
        },
    )
