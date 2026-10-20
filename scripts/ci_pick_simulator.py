#!/usr/bin/env python3
"""Prints `SIM_UDID=<udid>` for an available iPhone simulator on the newest iOS runtime.

CI appends the output to $GITHUB_ENV, so the workflow never hardcodes a device
the runner image might not have.
"""
import json
import subprocess
import sys

devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]

best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    for d in items:
        if d["name"].startswith("iPhone") and d.get("isAvailable", True):
            if best is None or runtime >= best[0]:
                best = (runtime, d["udid"])

if best is None:
    print("::error::No available iPhone simulator", file=sys.stderr)
    sys.exit(1)
print(f"SIM_UDID={best[1]}")
