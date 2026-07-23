#!/bin/bash

# Define tissues and scanners
tissues=("wm" "gm" "csf")
#scanners=("siemens" "GE")
scanners=("GE")

# Process each scanner type
for scanner in "${scanners[@]}"; do
	# Determine the folder name based on scanner
	if [ "$scanner" == "siemens" ]; then
		base_folder="workbench_siemens"
	else
		base_folder="workbench_GE"
	fi

	# Process each tissue
	for tissue in "${tissues[@]}"; do
		files=()
		echo "Gathering ${tissue}.txt files from $base_folder..."

		# Loop over each patient folder
		for patient_folder in "$base_folder"/*/; do
			tissue_file="${patient_folder}${tissue}.txt"
			if [ -f "$tissue_file" ]; then
				files+=("$tissue_file")
				echo "Found ${tissue}.txt in $patient_folder"
			else
				echo "No ${tissue}.txt in $patient_folder"
			fi
		done

		# Calculate average
		output_file="mean_${tissue}_dhollander_${scanner}.txt"
		echo "Calculating average for ${tissue}.txt files: output -> $output_file"
		responsemean "${files[@]}" "$output_file" -force

		# Distribute the mean file to individual folders
		for patient_folder in "$base_folder"/*/; do
			dest_file="${patient_folder}${output_file}"
			cp "$output_file" "$dest_file"
			echo "Copied $output_file to $patient_folder"
			
		done
	done
done
