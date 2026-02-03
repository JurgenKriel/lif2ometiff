#!/bin/bash

#SBATCH --job-name=omeconvert
#SBATCH --partition=regular
#SBATCH --cpus-per-task=32
#SBATCH --time 2:00:00
#SBATCH --mem=124G
#SBATCH --output /vast/projects/BCRL_Multi_Omics/slurm_logs/ome_convert_output_%j.out
#SBATCH --error /vast/projects/BCRL_Multi_Omics/slurm_logs/ome_convert_output_%j.err

#====
# ENVIRONMENT SETUP
#====

echo "===="
echo "Alright, here we go again"
echo "Conversion started on $(hostname) at $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "====" 

source /stornext/System/data/apps/anaconda3/anaconda3-latest/etc/profile.d/conda.sh
conda activate /vast/projects/BCRL_Multi_Omics/spatialdata_env_2
echo "Conda environment activated: $CONDA_DEFAULT_ENV"

echo "Looking for files..."

# Set the directory containing the files
INPUT_DIR="/stornext/Img/data/prkfs1/m/Microscopy/Jurgen_Kriel/Venture/PT6/"
RAW_OUTPUT_DIR='/vast/scratch/users/kriel.j/venture_pt6/raw/'
OMETIFF_OUTPUT_DIR='/vast/projects/BCRL_Multi_Omics/venture_pt6/ome/'

# Create the output directories if they don't exist
mkdir -p "$RAW_OUTPUT_DIR"
mkdir -p "$OMETIFF_OUTPUT_DIR"

# Step 1: Run bioformats2raw on all files
echo "✅ Found it!"
echo "Running bioformats2raw...this might take a while"
# Updated to target .czi files as requested
for file in "$INPUT_DIR"/*.czi; do
    # Check if file exists (in case glob matches nothing)
    [ -e "$file" ] || continue
    
    base_name=$(basename "$file")
    raw_output_path="$RAW_OUTPUT_DIR/${base_name}_raw"
    
    echo "Converting $file..."
    bioformats2raw "$file" "$raw_output_path"
done

echo "✅ Made it RAW"
# Step 2: Run raw2ometiff on all raw output folders
echo "Running raw2ometiff...we're almost there"
for dir in "$RAW_OUTPUT_DIR"/*_raw/; do
    # Check if dir exists
    [ -d "$dir" ] || continue

    base_name=$(basename "$dir" _raw)
    echo "Converting $base_name to OME-TIFF..."
    raw2ometiff "$dir" "$OMETIFF_OUTPUT_DIR/$base_name.ome.tif"
done

echo "✅ Conversion complete, Yay!"
