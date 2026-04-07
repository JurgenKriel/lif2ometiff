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

# Set the directory containing the input files
INPUT_DIR="/stornext/Img/data/prkfs1/m/Microscopy/Jurgen_Kriel/Venture/PT6/"
RAW_OUTPUT_DIR='/vast/scratch/users/kriel.j/venture_pt6/raw/'
OMETIFF_OUTPUT_DIR='/vast/projects/BCRL_Multi_Omics/venture_pt6'

# Create the output directories if they don't exist
mkdir -p "$RAW_OUTPUT_DIR"
mkdir -p "$OMETIFF_OUTPUT_DIR"

# Helper Tool Setup
BIOFORMATS_HOME=$(find /vast/projects/BCRL_Multi_Omics/spatialdata_env_2/share -maxdepth 1 -name "bioformats2raw-*" -type d | head -n 1)
CP="$BIOFORMATS_HOME/lib/*"
JAVA_TOOL_SRC="$RAW_OUTPUT_DIR/GetLIFSeries.java"

# Create Java helper using OME metadata store for accurate image names + Z info
cat <<JEOF > "$JAVA_TOOL_SRC"
import loci.formats.ImageReader;
import loci.formats.IFormatReader;
import loci.formats.MetadataTools;
import loci.formats.meta.IMetadata;
import loci.common.DebugTools;

public class GetLIFSeries {
    public static void main(String[] args) {
        try {
            DebugTools.enableLogging("OFF");
            if (args.length < 1) return;
            String file = args[0];
            IMetadata omeMeta = MetadataTools.createOMEXMLMetadata();
            IFormatReader reader = new ImageReader();
            reader.setMetadataStore(omeMeta);
            reader.setId(file);
            int count = reader.getSeriesCount();
            for (int i = 0; i < count; i++) {
                reader.setSeries(i);
                int sx = reader.getSizeX();
                int sy = reader.getSizeY();
                int sz = reader.getSizeZ();
                // Get the proper OME image name
                String name = "Series" + i;
                try {
                    String omeName = omeMeta.getImageName(i);
                    if (omeName != null && !omeName.trim().isEmpty()) {
                        name = omeName.trim();
                    }
                } catch (Exception e) {}
                // Sanitize: replace non-alphanumeric (except . - _) with _
                String cleanName = name.replaceAll("[^a-zA-Z0-9._-]", "_");
                // Output: Index SizeX SizeY SizeZ SanitizedName
                System.out.println(i + " " + sx + " " + sy + " " + sz + " " + cleanName);
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
for file in "$INPUT_DIR"/*Venture6_tile_scan_20260407.lif; do
    [ -e "$file" ] || continue
    base_name=$(basename "$file")

    if [[ "$file" == *.lif ]]; then
        echo "Detected LIF file: $base_name"
        echo "Identifying series to export..."

        # Get all series: Index SizeX SizeY SizeZ SanitizedOMEName
        ALL_SERIES=$(java -cp "$RAW_OUTPUT_DIR:$CP" GetLIFSeries "$file" 2>/dev/null)

        echo "All series found:"
        echo "$ALL_SERIES"
        echo "---"

        # Filter 1: Stitched tile scans — "Merged" in the OME image name
        MERGED_SERIES=$(echo "$ALL_SERIES" | grep -i "_Merged")

        # Filter 2: Z-stacks — SizeZ > 1, but NOT sub-tiles of a tile scan
        # (tile positions typically have "TileScan", "Position", or "Tile_" in their name)
        ZSTACK_SERIES=$(echo "$ALL_SERIES" | awk '$4 > 1 && $5 !~ /TileScan/ && $5 !~ /Position/ && $5 !~ /Tile_/')

        # Combine both, remove duplicates and blank lines
        SERIES_DATA=$(printf '%s\n%s\n' "$MERGED_SERIES" "$ZSTACK_SERIES" | sort -u | grep -v '^[[:space:]]*$')

        # Fallback: if nothing matched, try very large series (>10000px)
        if [ -z "$SERIES_DATA" ]; then
            echo "No Merged/Z-stack series found, falling back to large series (>10000px)..."
            SERIES_DATA=$(echo "$ALL_SERIES" | awk '$2 > 10000 || $3 > 10000')
        fi

        # Last resort: single largest image
        if [ -z "$SERIES_DATA" ]; then
            echo "No large series found either, converting the single largest series..."
            SERIES_DATA=$(echo "$ALL_SERIES" | awk 'BEGIN{max=0; line=""} {p=$2*$3; if(p>max){max=p; line=$0}} END{print line}')
        fi

        if [ ! -z "$SERIES_DATA" ]; then
            echo "Series selected for export:"
            echo "$SERIES_DATA"
            echo "Processing each series individually..."

            echo "$SERIES_DATA" | while read -r idx sx sy sz name; do
                echo "------------------------------------------------"
                echo "Processing Series $idx ($name) - Size: ${sx}x${sy}, Z: ${sz}"

                series_raw_path="$RAW_OUTPUT_DIR/${base_name}_s${idx}_raw"
                # Always include series index to avoid filename collisions
                output_ome_path="$OMETIFF_OUTPUT_DIR/${base_name%.*}_${name}_s${idx}.ome.tif"

                echo "Running bioformats2raw..."
                bioformats2raw --overwrite --log-level=OFF --series "$idx" "$file" "$series_raw_path"

                echo "Running raw2ometiff -> $output_ome_path"
                raw2ometiff --debug=OFF "$series_raw_path" "$output_ome_path"

                echo "Cleaning up temp raw files..."
                rm -rf "$series_raw_path"
                echo "✅ Done with Series $idx ($name)"
            done
        else
            echo "Could not identify any series — converting entire file as one."
            raw_output_path="$RAW_OUTPUT_DIR/${base_name}_raw"
            bioformats2raw --overwrite --log-level=OFF "$file" "$raw_output_path"
            raw2ometiff --debug=OFF "$raw_output_path" "$OMETIFF_OUTPUT_DIR/${base_name}.ome.tif"
        fi
    fi
done

echo "✅ Conversion complete, Yay!"
