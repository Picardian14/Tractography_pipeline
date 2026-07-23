
#!/bin/bash
output=/network/iss/cohen/data/Ivan/Tractography/outputs
tissue_job=/network/iss/cohen/data/Ivan/Tractography/scripts/segment5tt/tissue_job.sh
#data_folder=/network/iss/cohen/data/Ivan/Tractography/
data_folder=/network/iss/cohen/data/Ivan/DiffusionControl/workbench
cd $data_folder
folder_siemens="workbench_siemens"
cd "$folder_siemens"
for patient_folder in */; do
	if [ -d "$patient_folder" ]; then
        echo "Doing $patient_folder"
		cd "$patient_folder"   
        sbatch --job-name="5tt-$patient_folder" --output="$output/$(basename $patient_folder)5tt-%j.out.txt" --error="$output/$(basename $patient_folder)5tt-%j.err.txt" --mem=16G --time=48:00:00 $tissue_job $patient_folder $folder_siemens $data_folder  
		cd ..
	fi
done
cd ..
folder_GE="workbench_GE"
cd "$folder_GE"
for patient_folder in */; do
	if [ -d "$patient_folder" ]; then
		echo "Doing $patient_folder"
		cd "$patient_folder"   		
		sbatch --job-name="5tt-$patient_folder" --output="$output/$(basename $patient_folder)5tt-%j.out.txt" --error="$output/$(basename $patient_folder)5tt-%j.err.txt" --mem=16G --time=48:00:00 $tissue_job $patient_folder $folder_GE $data_folder	        
		cd ..
	fi
done
