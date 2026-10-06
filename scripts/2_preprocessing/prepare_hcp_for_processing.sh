#!/usr/bin/env bash
# Prepare HCP Recommended products without repeating their preprocessing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v mrconvert >/dev/null 2>&1; then
    type module >/dev/null 2>&1 && module load MRtrix
fi
python3 "$SCRIPT_DIR/prepare_hcp_for_processing.py" "$@"
