# Build on the target host so Docker selects the native architecture (ARM64 on
# Raspberry Pi, AMD64 on a conventional Linux server).
FROM ghcr.io/mlflow/mlflow:v3.4.0

USER root
RUN pip install --no-cache-dir psycopg2-binary
