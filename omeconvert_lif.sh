#!/bin/bash

#SBATCH --job-name=omeconvert_lif
#SBATCH --partition=regular
#SBATCH --cpus-per-task=32
#SBATCH --time 2:00:00
#SBATCH --mem=124G
#SBATCH --output /vast/projects/BCRL_Multi_Omics/slurm_logs/ome_convert_lif_output_%j.out
#SBATCH --error /vast/projects/BCRL_Multi_Omics/slurm_logs/ome_convert_lif_output_%j.err

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

echo "Looking for this mf file..."

# Set the directory containing the .ome.tiff files
INPUT_DIR="/path/to/input"
RAW_OUTPUT_DIR='/path/to/raw_output'
OMETIFF_OUTPUT_DIR='/path/to/ome/output'

# Create the output directories if they don't exist
mkdir -p "$RAW_OUTPUT_DIR"
mkdir -p "$OMETIFF_OUTPUT_DIR"

# Helper Tool Setup
# Find Bio-Formats jars to compile the helper tool
BIOFORMATS_HOME=$(find /vast/projects/BCRL_Multi_Omics/spatialdata_env_2/share -maxdepth 1 -name "bioformats2raw-*" -type d | head -n 1)
CP="$BIOFORMATS_HOME/lib/*"
JAVA_TOOL_SRC="$RAW_OUTPUT_DIR/GetLIFSeries.java"

# Create Java helper to list series with names
cat <<JEOF > "$JAVA_TOOL_SRC"
import loci.formats.ImageReader;
import loci.formats.IFormatReader;
import loci.common.DebugTools;
import java.util.Hashtable;

public class GetLIFSeries {
    public static void main(String[] args) {
        try {
            DebugTools.enableLogging("ERROR");
            if (args.length < 1) return;
            String file = args[0];
            IFormatReader reader = new ImageReader();
            reader.setId(file);
            int count = reader.getSeriesCount();
            for (int i = 0; i < count; i++) {
                reader.setSeries(i);
                int sx = reader.getSizeX();
                int sy = reader.getSizeY();
                
                String name = "Series" + i;
                Hashtable<String, Object> meta = reader.getSeriesMetadata();
                if (meta.containsKey("Name")) {
                    name = meta.get("Name").toString();
                } else if (meta.containsKey("Image name")) {
                    name = meta.get("Image name").toString();
                } else if (meta.containsKey("TileScan Name")) {
                     name = meta.get("TileScan Name").toString();
                }
                
                // Sanitize name: replace non-alphanumeric (except . - _) with _
                String cleanName = name.replaceAll("[^a-zA-Z0-9._-]", "_");
                
                // Output: Index SizeX SizeY SanitizedName
                System.out.println(i + " " + sx + " " + sy + " " + cleanName);
            }
            reader.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
JEOF

echo "Compiling helper tool..."
javac -cp "$CP" -d "$RAW_OUTPUT_DIR" "$JAVA_TOOL_SRC"

# Main processing loop
echo "✅ Found it!"
echo "Running conversion...this might take a while"
for file in "$INPUT_DIR"/*20260122_venture6_40231.lif; do
    base_name=$(basename "$file")
    
    if [[ "$file" == *.lif ]]; then
        echo "Detected LIF file $base_name"
        echo "Identifying merged series..."
        
        # Get list of all series: Index SizeX SizeY Name
        # Filter for series with width or height > 2000
        SERIES_DATA=$(java -cp "$RAW_OUTPUT_DIR:$CP" GetLIFSeries "$file" | awk '$2 > 2000 || $3 > 2000')
        
        if [ ! -z "$SERIES_DATA" ]; then
            echo "Found large series, processing them individually..."
            
            # Read line by line
            # Format: Index SizeX SizeY Name
            echo "$SERIES_DATA" | while read -r idx sx sy name; do
                echo "------------------------------------------------"
                echo "Processing Series $idx ($name) - Size: ${sx}x${sy}"
                
                # Create a unique raw directory for this series
                series_raw_path="$RAW_OUTPUT_DIR/${base_name}_s${idx}_raw"
                output_ome_path="$OMETIFF_OUTPUT_DIR/${base_name%.*}_${name}.ome.tif"
                
                # Step 1: Run bioformats2raw for single series
                echo "Running bioformats2raw..."
                bioformats2raw --overwrite --series "$idx" "$file" "$series_raw_path"
                
                # Step 2: Run raw2ometiff
                echo "Running raw2ometiff -> $output_ome_path"
                raw2ometiff "$series_raw_path" "$output_ome_path"
                
                # Cleanup raw directory to save space
                echo "Cleaning up temp raw files..."
                rm -rf "$series_raw_path"
                echo "Done with Series $idx"
            done
            
        else
            echo "No large series found. Converting entire file as one..."
            raw_output_path="$RAW_OUTPUT_DIR/${base_name}_raw"
            bioformats2raw --overwrite "$file" "$raw_output_path"
            raw2ometiff "$raw_output_path" "$OMETIFF_OUTPUT_DIR/$base_name.ome.tif"
        fi
    fi
done

echo "✅ Conversion complete, Yay!"
