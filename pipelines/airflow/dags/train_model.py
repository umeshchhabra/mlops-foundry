"""Small end-to-end training task for local MLOps practice."""

import os
from datetime import datetime

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator


def train_and_log() -> None:
    import json
    import time
    from urllib.request import Request, urlopen
    from sklearn.datasets import load_iris
    from sklearn.linear_model import LogisticRegression
    import boto3
    import joblib
    import tempfile

    features, labels = load_iris(return_X_y=True)
    model = LogisticRegression(max_iter=1000).fit(features, labels)
    accuracy = float(model.score(features, labels))
    base = os.environ.get(
        "MLFLOW_TRACKING_URI", "http://mlflow.mlops.svc.cluster.local:5000"
    ).rstrip("/")

    def post(path: str, payload: dict) -> dict:
        request = Request(
            f"{base}/api/2.0/mlflow/{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=30) as response:
            return json.loads(response.read())

    try:
        experiment_id = post("experiments/create", {"name": "mlops-platform"})[
            "experiment_id"
        ]
    except Exception:
        request = Request(
            f"{base}/api/2.0/mlflow/experiments/get-by-name?experiment_name=mlops-platform"
        )
        with urlopen(request, timeout=30) as response:
            experiment_id = json.loads(response.read())["experiment"]["experiment_id"]

    run = post(
        "runs/create",
        {
            "experiment_id": experiment_id,
            "start_time": int(time.time() * 1000),
            "tags": [{"key": "source", "value": "airflow"}],
        },
    )
    run_id = run["run"]["info"]["run_id"]
    bucket = os.environ.get("MLFLOW_ARTIFACT_BUCKET", "mlflow-artifacts")
    endpoint = os.environ.get(
        "MLFLOW_S3_ENDPOINT_URL", "http://minio.mlops.svc.cluster.local:9000"
    )
    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name="us-east-1",
    )
    try:
        s3.head_bucket(Bucket=bucket)
    except Exception:
        s3.create_bucket(Bucket=bucket)
    with tempfile.NamedTemporaryFile(suffix=".joblib") as artifact:
        joblib.dump(model, artifact.name)
        s3.upload_file(
            artifact.name, bucket, f"{experiment_id}/{run_id}/artifacts/model/model.joblib"
        )
    artifact_uri = f"s3://{bucket}/{experiment_id}/{run_id}/artifacts/model"
    post("runs/log-parameter", {"run_id": run_id, "key": "artifact_uri", "value": artifact_uri})
    post("runs/log-metric", {"run_id": run_id, "key": "training_accuracy", "value": accuracy, "timestamp": int(time.time() * 1000), "step": 0})
    for key, value in {"model_type": "logistic_regression", "training_rows": str(len(features))}.items():
        post("runs/log-parameter", {"run_id": run_id, "key": key, "value": value})
    post("runs/update", {"run_id": run_id, "status": "FINISHED", "end_time": int(time.time() * 1000)})
    print(f"MLflow run_id={run_id} accuracy={accuracy:.4f}")


with DAG(
    dag_id="home_train_and_log",
    start_date=datetime(2025, 1, 1),
    schedule=None,
    catchup=False,
    tags=["training", "mlflow", "local"],
) as dag:
    train = PythonOperator(
        task_id="train_and_log",
        python_callable=train_and_log,
    )
