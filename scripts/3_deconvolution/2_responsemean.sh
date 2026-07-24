#!/bin/bash

###############################################################################
# PATH MACRO: edit ../paths_config.sh once, or override variables here.
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../paths_config.sh"
RESPONSE_DATA_DIR="${RESPONSE_DATA_DIR:-${BIDS_ROOT}}"
cd "$RESPONSE_DATA_DIR" || exit 1

tissues=("wm" "gm" "csf")
for tissue in "${tissues[@]}"; do
		files=()
		echo "Gathering ${tissue}.txt files from BIDS subjects..."

		for subject_dir in sub-*/; do
			[ -d "$subject_dir/dwi" ] || continue
			tissue_file="${subject_dir}dwi/${tissue}.txt"
			if [ -f "$tissue_file" ]; then
				files+=("$tissue_file")
				echo "Found ${tissue}.txt in $subject_dir/dwi"
			else
				echo "No ${tissue}.txt in $subject_dir/dwi"
			fi
		done

		if [ "${#files[@]}" -eq 0 ]; then
			echo "No ${tissue} responses found; skipping" >&2
			continue
		fi
		output_file="mean_${tissue}_dhollander.txt"
		echo "Calculating average for ${tissue}.txt files: output -> $output_file"
		responsemean "${files[@]}" "$output_file" -force

		for subject_dir in sub-*/; do
			[ -d "$subject_dir/dwi" ] || continue
			dest_file="${subject_dir}dwi/${output_file}"
			cp "$output_file" "$dest_file"
			echo "Copied $output_file to $subject_dir/dwi"
		done
done
