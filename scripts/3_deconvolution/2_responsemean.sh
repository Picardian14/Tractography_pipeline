#!/bin/bash

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="${1:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
source "${PIPELINE_ROOT}/scripts/paths_config.sh" $1
RESPONSE_DATA_DIR="${RESPONSE_DATA_DIR:-${BIDS_ROOT}}"
cd "$RESPONSE_DATA_DIR" || exit 1

tissues=("wm" "gm" "csf")
for tissue in "${tissues[@]}"; do
		files=()
		echo "Gathering ${tissue}.txt files from BIDS subjects..."

		for subject_dir in sub-*/; do
			[ -d "$subject_dir/dwi" ] || continue
			subject=$(basename "$subject_dir")
			tissue_file="${subject_dir}dwi/${subject}_desc-dhollander_response-${tissue}.txt"
			if [ -f "$tissue_file" ]; then
				files+=("$tissue_file")
				echo "Found $tissue_file"
			else
				echo "No $tissue_file"
			fi
		done

		if [ "${#files[@]}" -eq 0 ]; then
			echo "No ${tissue} responses found; skipping" >&2
			continue
		fi
		output_file="desc-meanDhollander_response-${tissue}.txt"
		echo "Calculating average for ${tissue}.txt files: output -> $output_file"
		responsemean "${files[@]}" "$output_file" -force

		for subject_dir in sub-*/; do
			[ -d "$subject_dir/dwi" ] || continue
			subject=$(basename "$subject_dir")
			dest_file="${subject_dir}dwi/${subject}_${output_file}"
			cp "$output_file" "$dest_file"
			echo "Copied $output_file to $dest_file"
		done
done
