#!/usr/bin/env python3

import json
import sys


if len(sys.argv) != 3:
    sys.exit(f"Usage: {sys.argv[0]} DWI_JSON OUTPUT_FILE")

json_file, output_file = sys.argv[1:]

with open(json_file, encoding="utf-8") as f:
    metadata = json.load(f)

phase_encoding = metadata.get("PhaseEncodingDirection")
if phase_encoding not in ("j-", "j"):
    sys.exit(
        'PhaseEncodingDirection must be present and equal to "j-" or "j" '
        f"in {json_file}"
    )

if "TotalReadoutTime" not in metadata:
    sys.exit(f"TotalReadoutTime is missing from {json_file}")

try:
    total_readout = float(metadata["TotalReadoutTime"])
except (TypeError, ValueError):
    sys.exit(f"TotalReadoutTime must be numeric in {json_file}")

direction = -1 if phase_encoding == "j-" else 1
with open(output_file, "w", encoding="utf-8") as f:
    f.write(f"0 {direction} 0 {total_readout:.10g}\n")
    f.write(f"0 {direction} 0 0.000\n")

print(phase_encoding)
