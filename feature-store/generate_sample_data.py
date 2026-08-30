from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

rows = [
    {"driver_id": 1, "event_timestamp": datetime.now(timezone.utc), "trips_today": 8, "average_speed": 31.5},
    {"driver_id": 2, "event_timestamp": datetime.now(timezone.utc), "trips_today": 4, "average_speed": 27.0},
]
output = Path("data/driver_stats.parquet")
output.parent.mkdir(parents=True, exist_ok=True)
pd.DataFrame(rows).to_parquet(output, index=False)
print(f"Wrote {output}")
