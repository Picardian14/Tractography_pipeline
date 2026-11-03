#!/usr/bin/env python3

import json
import math
import sys


if len(sys.argv) not in (3, 4):
    sys.exit(f"Usage: {sys.argv[0]} DWI_JSON OUTPUT_FILE [REVERSE_B0_JSON]")

json_file, output_file = sys.argv[1:3]

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
if not math.isfinite(total_readout) or total_readout <= 0:
    sys.exit(f"TotalReadoutTime must be finite and positive in {json_file}")

direction = -1 if phase_encoding == "j-" else 1
reverse_direction = direction
reverse_readout = 0.0  # Synb0's reference is synthesized without EPI distortion.
if len(sys.argv) == 4:
    reverse_json = sys.argv[3]
    with open(reverse_json, encoding="utf-8") as f:
        reverse_metadata = json.load(f)
    opposite_phase_encoding = "j" if phase_encoding == "j-" else "j-"
    if reverse_metadata.get("PhaseEncodingDirection") != opposite_phase_encoding:
        sys.exit(f"Reverse B0 PhaseEncodingDirection must be {opposite_phase_encoding!r} in {reverse_json}")
    try:
        reverse_readout = float(reverse_metadata["TotalReadoutTime"])
    except (KeyError, TypeError, ValueError):
        sys.exit(f"TotalReadoutTime must be present and numeric in {reverse_json}")
    if not math.isfinite(reverse_readout) or reverse_readout <= 0:
        sys.exit(f"TotalReadoutTime must be finite and positive in {reverse_json}")
    reverse_direction = -direction

with open(output_file, "w", encoding="utf-8") as f:
    f.write(f"0 {direction} 0 {total_readout:.10g}\n")
    f.write(f"0 {reverse_direction} 0 {reverse_readout:.10g}\n")

print(phase_encoding)
