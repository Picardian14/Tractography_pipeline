
#!/bin/bash
output=/network/iss/cohen/data/Ivan/Tractography/outputs
dwi2resp=/network/iss/cohen/data/Ivan/Tractography/scripts/deconvolution/dwi2response.sh
# cd /network/iss/cohen/data/Ivan/Tractography/  # doC
data_folder=/network/iss/cohen/data/Ivan/DiffusionControl/workbench
cd $data_folder

scanner_folder="workbench_siemens"


scanner_folder="workbench_GE"
cd "$scanner_folder"
for patient_folder in */; do
	if [ -d "$patient_folder" ]; then
        echo "Doing $patient_folder"
		cd "$patient_folder"   
        sbatch --job-name="dwi2resp-$patient_folder" --output="$output/$(basename $patient_folder)-dwi2resp-%j.out.txt" --error="$output/$(basename $patient_folder)-dwi2resp-%j.err.txt"  $dwi2resp $patient_folder $scanner_folder $data_folder
        
		cd ..
	fi
done