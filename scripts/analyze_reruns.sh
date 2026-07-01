#!/bin/bash
#
# Analyze multiple runs with automatic selection of appropriate metrics
# Usage: ./analyze_reruns.sh --type ligand --runs run1 run2 run3 run4 --output output_dir --name approach_name
#        ./analyze_reruns.sh --type scaffold --runs run1 run2 run3 run4 --output output_dir --name approach_name
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 --type <ligand|scaffold> --runs <run1> <run2> ... --output <output_dir> --name <approach_name>"
    echo ""
    echo "Required arguments:"
    echo "  --type TYPE            Analysis type: 'ligand' (with protein-ligand metrics) or 'scaffold' (without ligand)"
    echo "  --runs DIRS            Space-separated list of run directories (at least 4 runs)"
    echo "  --output DIR           Output directory for analysis results"
    echo "  --name NAME            Approach name for labeling (e.g., 'sialinbinder' or 'rfd3_contig_3epi')"
    echo ""
    echo "Examples:"
    echo "  # Analyze ligand-binding approach (4 runs)"
    echo "  $0 --type ligand \\"
    echo "      --runs /path/sialinbinder_with_ligand /path/sialinbinder_with_ligand_2 /path/sialinbinder_with_ligand_3 /path/sialinbinder_with_ligand_4 \\"
    echo "      --output /path/analysis \\"
    echo "      --name sialinbinder_ligand"
    echo ""
    echo "  # Analyze scaffold design approach (4 runs)"
    echo "  $0 --type scaffold \\"
    echo "      --runs /path/rfd3_contig_3epi /path/rfd3_contig_3epi_2 /path/rfd3_contig_3epi_3 /path/rfd3_contig_3epi_4 \\"
    echo "      --output /path/analysis \\"
    echo "      --name rfd3_contig_3epi"
}

# Parse arguments
TYPE=""
RUNS=()
OUTPUT_DIR=""
APPROACH_NAME=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --type)
            TYPE="$2"
            shift 2
            ;;
        --runs)
            shift
            while [[ "$#" -gt 0 ]] && [[ "$1" != --* ]]; do
                RUNS+=("$1")
                shift
            done
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --name)
            APPROACH_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$TYPE" ]]; then
    echo "ERROR: --type is required (ligand or scaffold)"
    usage
    exit 1
fi

if [[ "${#RUNS[@]}" -eq 0 ]]; then
    echo "ERROR: --runs is required (specify at least 4 run directories)"
    usage
    exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "ERROR: --output is required"
    usage
    exit 1
fi

if [[ -z "$APPROACH_NAME" ]]; then
    echo "ERROR: --name is required"
    usage
    exit 1
fi

# Validate type
if [[ "$TYPE" != "ligand" && "$TYPE" != "scaffold" ]]; then
    echo "ERROR: --type must be 'ligand' or 'scaffold'"
    usage
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=========================================================================="
echo "Multi-Run Analysis"
echo "=========================================================================="
echo "Type: $TYPE"
echo "Approach: $APPROACH_NAME"
echo "Number of runs: ${#RUNS[@]}"
echo "Runs:"
for run in "${RUNS[@]}"; do
    echo "  - $run"
done
echo "Output directory: $OUTPUT_DIR"
echo ""

# Run appropriate analysis script
if [[ "$TYPE" == "ligand" ]]; then
    echo "Running LIGAND analysis (prioritizing ipTM)..."
    python3 "$SCRIPT_DIR/analyze_runs_with_ligand.py" \
        --runs "${RUNS[@]}" \
        --output "$OUTPUT_DIR" \
        --name "$APPROACH_NAME"

elif [[ "$TYPE" == "scaffold" ]]; then
    echo "Running SCAFFOLD analysis (prioritizing pTM)..."
    python3 "$SCRIPT_DIR/analyze_runs_no_ligand.py" \
        --runs "${RUNS[@]}" \
        --output "$OUTPUT_DIR" \
        --name "$APPROACH_NAME"
fi

echo ""
echo "=========================================================================="
echo "✓ Analysis complete!"
echo "Results saved to: $OUTPUT_DIR"
echo "=========================================================================="
