from datetime import timedelta

from feast import Entity, FeatureView, Field, FileSource
from feast.types import Float32, Int64

driver = Entity(
    name="driver_id",
    join_keys=["driver_id"],
    description="Synthetic driver identifier",
)

driver_stats_source = FileSource(
    name="driver_stats_source",
    path="data/driver_stats.parquet",
    timestamp_field="event_timestamp",
)

driver_stats = FeatureView(
    name="driver_stats",
    entities=[driver],
    ttl=timedelta(days=365),
    schema=[
        Field(name="trips_today", dtype=Int64),
        Field(name="average_speed", dtype=Float32),
    ],
    source=driver_stats_source,
)
