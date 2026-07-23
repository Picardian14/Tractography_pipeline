
#!/bin/bash
output=/network/iss/cohen/data/Ivan/Tractography/outputs
recon_all_job=/network/iss/cohen/data/Ivan/Tractography/scripts/parcellation/recon_all_job.sh
#data_folder=/network/iss/cohen/data/Ivan/Tractography/
data_folder=/network/iss/cohen/data/Ivan/DiffusionControl/workbench
cd $data_folder


scanner_folder="workbench_siemens"
cd "$scanner_folder"
for patient_folder in */; do
	if [ -d "$patient_folder" ]; then
        echo "Doing $patient_folder"
		cd "$patient_folder"   
        sbatch --job-name="recon_all-$patient_folder" --output="$output/$(basename $patient_folder)recon_all-%j.out.txt" --error="$output/$(basename $patient_folder)recon_all-%j.err.txt" --mem=64G --time=24:00:00 $recon_all_job $patient_folder $scanner_folder $data_folder
		cd ..
	fi
done

cd ..
scanner_folder="workbench_GE"
cd "$scanner_folder"
for patient_folder in */; do
	if [ -d "$patient_folder" ]; then
		echo "Doing $patient_folder"
		cd "$patient_folder"   
		sbatch --job-name="recon_all-$patient_folder" --output="$output/$(basename $patient_folder)recon_all-%j.out.txt" --error="$output/$(basename $patient_folder)recon_all-%j.err.txt" --mem=64G --time=24:00:00 $recon_all_job $patient_folder $scanner_folder $data_folder
		cd ..
	fi
done