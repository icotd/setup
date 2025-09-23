# pip install pyrosm pandas numpy
from pyrosm import OSM
import pandas as pd
import numpy as np
import re

PBF = "addis-ababa.osm.pbf"   # your file
osm = OSM(PBF)

# Driving network; returns edges as GeoDataFrame.
edges = osm.get_network(network_type="driving")  # columns include 'id','highway','maxspeed','surface','junction', etc.

def parse_maxspeed(mx):
    """
    Robust parser for maxspeed variants:
    - "50", "50 km/h", "30 mph", ["50","60"]
    - Returns km/h float or np.nan
    """
    if mx is None or (isinstance(mx, float) and np.isnan(mx)):
        return np.nan
    # If list-like, take the first parsable entry
    if isinstance(mx, (list, tuple)):
        for v in mx:
            val = parse_maxspeed(v)
            if not np.isnan(val):
                return val
        return np.nan
    s = str(mx).lower().strip()
    # common tokens like "signals", "none" -> ignore
    if s in {"signals", "none", "walk"}:
        return np.nan
    # mph handling
    mph = "mph" in s
    # extract first number
    m = re.search(r"(\d+(\.\d+)?)", s)
    if not m:
        return np.nan
    val = float(m.group(1))
    if mph:
        val *= 1.60934
    return val

def norm_highway(hw):
    # handle list-like highway tags
    if isinstance(hw, (list, tuple)):
        return hw[0] if hw else ""
    return hw or ""

def base_speed_kmh(row):
    hw = norm_highway(row.get("highway"))
    mx = parse_maxspeed(row.get("maxspeed"))

    if not np.isnan(mx):
        s = mx
    else:
        # conservative urban defaults for Addis
        table = {
            "motorway": 80, "trunk": 60, "primary": 50,
            "secondary": 45, "tertiary": 40,
            "residential": 30, "unclassified": 25, "service": 20,
            "living_street": 15
        }
        s = table.get(hw, 30)

    surface = row.get("surface")
    if isinstance(surface, (list, tuple)):
        surface = surface[0] if surface else None
    if surface in {"gravel", "unpaved", "ground", "dirt"}:
        s *= 0.8

    if row.get("junction") == "roundabout":
        s = min(s, 30)

    # Keep within sane city bounds
    return float(max(10.0, min(s, 110.0)))

# Compute per-edge base speed
edges["speed_kmh"] = edges.apply(base_speed_kmh, axis=1)

# Collapse to one row per OSM way id for the CSV (OSRM expects per-way)
# Use median if the same way appears multiple times (split geometries).
df = (
    edges[["id", "speed_kmh"]]
    .rename(columns={"id": "osmid"})
    .dropna(subset=["osmid"])
    .groupby("osmid", as_index=False)["speed_kmh"].median()
)

# Write the external speed file
df.to_csv("addis_speeds.csv", index=False)
print("Wrote addis_speeds.csv with", len(df), "rows")
