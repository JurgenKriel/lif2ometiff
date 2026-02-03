# LIF/CZI to OME-TIFF Conversion Pipeline

This repository contains Slurm batch scripts for converting microscopy images (specifically .lif and .czi formats) into OME-TIFF format using the `bioformats2raw` and `raw2ometiff` pipeline.

## Features

- **omeconvert.sh**: A standard conversion script suitable for simple file formats like .czi.
- **omeconvert_lif.sh**: A specialized script for .lif files that:
    - Automatically detects stitched/merged tile scans (large images).
    - Filters out individual tiles to prevent massive, unnecessary exports.
    - Exports each merged series as a separate OME-TIFF file.
    - Uses a custom on-the-fly compiled Java helper to parse LIF metadata efficiently.

## Environment Setup

To run these scripts from scratch, you need to set up a Conda/Mamba environment with the required tools.

### 1. Install Conda or Mamba
If you don't have Conda installed, we recommend [Miniforge](https://github.com/conda-forge/miniforge) (which includes Mamba).

### 2. Create the Environment
Run the following command to create a new environment (e.g., `spatialdata_env`) with the necessary packages:

```bash
mamba create -n conversion_env -c ome -c conda-forge bioformats2raw raw2ometiff openjdk
```

*Note: `openjdk` is required for the LIF script to compile the Java helper tool.*

### 3. Activate the Environment
```bash
conda activate conversion_env
```

## Usage

### Configuration
Before running the scripts, you **must** edit them to set your specific paths:

Open the script (e.g., `omeconvert_lif.sh`) and modify the following variables:

```bash
# Set the directory containing the input files
INPUT_DIR="/path/to/your/input/files/"

# Set the temporary directory for raw intermediate files (needs high capacity)
RAW_OUTPUT_DIR='/path/to/your/scratch/directory/raw/'

# Set the final output directory for OME-TIFFs
OMETIFF_OUTPUT_DIR='/path/to/your/output/directory/ome/'
```

Also, verify that the `conda activate` command in the script points to your created environment name or path.

### Running the Job
Submit the job to Slurm:

**For LIF files (smart series detection):**
```bash
sbatch omeconvert_lif.sh
```

**For CZI files (standard conversion):**
```bash
sbatch omeconvert.sh
```

## Troubleshooting

- **Memory Issues**: If the job fails with memory errors, try increasing the `#SBATCH --mem` value in the script.
- **Java Errors**: If the LIF script fails to compile the helper, ensure `javac` is in your path (`conda install openjdk`).
- **Path Errors**: Ensure your `INPUT_DIR`, `RAW_OUTPUT_DIR`, and `OMETIFF_OUTPUT_DIR` exist or can be created. The `RAW_OUTPUT_DIR` should be on fast scratch storage if possible.
