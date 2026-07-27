#!/usr/bin/env bash

# Build diffusion.def with a persistent log and retain the failed build bundle
# when supported by the installed SingularityCE/Apptainer version.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFINITION_FILE="${DEFINITION_FILE:-${SCRIPT_DIR}/diffusion.def}"
OUTPUT_IMAGE="${1:-${SCRIPT_DIR}/diffusion.sif}"
LOG_DIR="${BUILD_LOG_DIR:-${SCRIPT_DIR}/build-logs}"
BUILD_TMPDIR="${BUILD_TMPDIR:-${SINGULARITY_TMPDIR:-${APPTAINER_TMPDIR:-/tmp}}}"
BUILD_CACHEDIR="${BUILD_CACHEDIR:-${SINGULARITY_CACHEDIR:-${APPTAINER_CACHEDIR:-${TMPDIR:-/tmp}/${USER:-user}-singularity-cache}}}"

if command -v singularity >/dev/null 2>&1; then
    RUNTIME=singularity
elif command -v apptainer >/dev/null 2>&1; then
    RUNTIME=apptainer
else
    echo "ERROR: neither singularity nor apptainer is available on PATH" >&2
    exit 127
fi

mkdir -p "$LOG_DIR" "$BUILD_TMPDIR" "$BUILD_CACHEDIR"
BUILD_ID="$(date '+%Y%m%d-%H%M%S')"
LOG_FILE="${LOG_DIR}/diffusion-build-${BUILD_ID}.log"

BUILD_ARGS=(build)
if [ "$EUID" -ne 0 ]; then
    BUILD_ARGS+=(--fakeroot)
fi
if "$RUNTIME" build --help 2>&1 | grep -q -- '--no-cleanup'; then
    BUILD_ARGS+=(--no-cleanup)
fi
BUILD_ARGS+=("$OUTPUT_IMAGE" "$DEFINITION_FILE")

{
    echo "Build started: $(date --iso-8601=seconds)"
    echo "Runtime: $("$RUNTIME" --version 2>&1)"
    echo "Definition: $DEFINITION_FILE"
    echo "Output: $OUTPUT_IMAGE"
    echo "Temporary directory: $BUILD_TMPDIR"
    echo "Cache directory: $BUILD_CACHEDIR"
    printf 'Command:'
    printf ' %q' "$RUNTIME" "${BUILD_ARGS[@]}"
    printf '\n\n'
} | tee "$LOG_FILE"

set +e
if [ "$RUNTIME" = singularity ]; then
    SINGULARITY_TMPDIR="$BUILD_TMPDIR" \
    SINGULARITY_CACHEDIR="$BUILD_CACHEDIR" \
    SINGULARITY_NOCLEANUP=true \
        "$RUNTIME" "${BUILD_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    BUILD_STATUS=${PIPESTATUS[0]}
else
    APPTAINER_TMPDIR="$BUILD_TMPDIR" \
    APPTAINER_CACHEDIR="$BUILD_CACHEDIR" \
    APPTAINER_NOCLEANUP=true \
        "$RUNTIME" "${BUILD_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    BUILD_STATUS=${PIPESTATUS[0]}
fi
set -e

{
    printf '\nBuild finished: %s\n' "$(date --iso-8601=seconds)"
    echo "Exit status: $BUILD_STATUS"
    echo "Complete log: $LOG_FILE"
    if [ "$BUILD_STATUS" -ne 0 ]; then
        echo "The runtime was instructed not to clean up its failed build bundle."
        echo "Search the log for 'bundle', 'tmp', or 'build-temp' to locate it."
        echo "The retained bundle is useful for inspection, but is not a supported automatic restart checkpoint."
    fi
} | tee -a "$LOG_FILE"

exit "$BUILD_STATUS"
