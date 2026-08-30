# Local Feast feature store

This is the smallest useful feature-store setup for home MLOps training. It
uses Feast's local provider, a SQLite registry/online store, and a Parquet
offline source. Runtime data and the generated registry are ignored by Git.

From this directory:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python generate_sample_data.py
feast apply
feast materialize-incremental $(Get-Date -Format yyyy-MM-ddTHH:mm:ss)
feast serve
```

Use the feature view in training code with `FeatureStore.get_historical_features`
or `get_online_features`. The local provider is intentionally not shared
between machines; a later branch can move the registry/online store to the
existing platform when that becomes useful.
