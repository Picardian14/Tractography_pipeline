#!/bin/bash
#SBATCH --partition=compute
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=01:00:00

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "Usage: $0 /absolute/path/to/bids" >&2
    exit 2
fi

BIDS_ROOT="$(readlink -f "$1")"

# responsemean is provided by MRtrix. Keep direct/interactive execution working
# in environments where MRtrix is already available without the module system.
if ! command -v responsemean >/dev/null 2>&1; then
	type module >/dev/null 2>&1 && module load MRtrix
fi
if ! command -v responsemean >/dev/null 2>&1; then
	echo "responsemean is unavailable; load MRtrix before running this job." >&2
	exit 1
fi

cd "$BIDS_ROOT" || exit 1

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
