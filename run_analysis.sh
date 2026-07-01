#!/bin/bash
#
# Convenience script to run multi-run analysis after 4 parallel jobs complete
# This script reads the config to determine which analysis type to use
#
# Usage: ./run_analysis.sh --config config/sialinbinder_with_ligand.yaml
#        ./run_analysis.sh --config config/rfd3_contig_3epi_rasa_partial.yaml
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

usage() {
    echo "Usage: $0 --config <config.yaml>"
    echo ""
    echo "Runs multi-run analysis after 4 parallel jobs complete."
    echo "Automatically detects run directories and analysis type from config."
    echo ""
    echo "Example:"
    echo "  $0 --config config/sialinbinder_with_ligand.yaml"
}

CONFIG_FILE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "ERROR: --config is required"
    usage
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Extract config values using Python
CONFIG_DATA=$(python3 << PYEOF
import sys
import yaml
import os
from pathlib import Path

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)

    # Get analysis type
    analysis_config = config.get('analysis', {})
    analysis_type = analysis_config.get('type', 'ligand')
    analysis_enabled = analysis_config.get('enabled', True)

    # Get work directory and subdirectory
    work_dir = config.get('output', {}).get('work_directory', '')
    rfd3_settings = config.get('rfd3', {}).get('settings_json', '')
    config_subdir = config.get('output', {}).get('subdirectory', '')

    # Determine subdirectory name
    if not config_subdir or config_subdir == 'design_run':
        json_name = os.path.splitext(os.path.basename(rfd3_settings))[0]
        subdir = json_name if json_name else 'design_run'
    else:
        subdir = config_subdir

    print(f"analysis_type={analysis_type}")
    print(f"analysis_enabled={str(analysis_enabled).lower()}")
    print(f"work_dir={work_dir}")
    print(f"subdir={subdir}")

except Exception as e:
    print(f"error=Failed to parse config: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to parse config file"
    exit 1
fi

eval "$CONFIG_DATA"

if [[ "$analysis_enabled" != "true" ]]; then
    echo "Analysis is disabled in config (analysis.enabled: false)"
    exit 0
fi

# Construct run directories
RUN_1="$work_dir/design_generation/$subdir"
RUN_2="${work_dir}_2/design_generation/$subdir"
RUN_3="${work_dir}_3/design_generation/$subdir"
RUN_4="${work_dir}_4/design_generation/$subdir"
RUN_5="${work_dir}_5/design_generation/$subdir"

echo "=========================================================================="
echo "Multi-Run Analysis"
echo "=========================================================================="
echo "Config file: $CONFIG_FILE"
echo "Analysis type: $analysis_type"
echo "Approach: $subdir"
echo "Work directory: $work_dir"
echo ""

# Check if runs exist

echo "Looking for run directories..."
for run in "$RUN_1" "$RUN_2" "$RUN_3" "$RUN_4" "$RUN_5"; do
    if [[ ! -d "$run" ]]; then
        echo "ERROR: Run directory not found: $run"
        echo ""
        echo "Make sure all 5 runs have completed:"
        echo "  1. $RUN_1"
        echo "  2. $RUN_2"
        echo "  3. $RUN_3"
        echo "  4. $RUN_4"
        echo "  5. $RUN_5"
        exit 1
    fi
    echo "  ✓ Found: $(basename $run)"
done

# Create analysis output directory (use first run as base)
ANALYSIS_OUTPUT="$RUN_1/analysis"
mkdir -p "$ANALYSIS_OUTPUT"

echo ""
echo "Starting analysis..."
echo "Analysis output: $ANALYSIS_OUTPUT"
echo ""

# Run analysis
"$SCRIPT_DIR/scripts/analyze_reruns.sh" \
    --type "$analysis_type" \
    --runs "$RUN_1" "$RUN_2" "$RUN_3" "$RUN_4" "$RUN_5" \
    --output "$ANALYSIS_OUTPUT" \
    --name "$subdir"

echo ""
echo "=========================================================================="
echo "✓ Analysis complete!"
echo "Results saved to: $ANALYSIS_OUTPUT"
echo "=========================================================================="
echo ""
echo "Generated files:"
ls -lh "$ANALYSIS_OUTPUT"

# Copy top 20 designs from each run to a global collection folder
echo ""
echo "=========================================================================="
echo "Collecting top 20 from each run..."
echo "=========================================================================="

TOP20_GLOBAL="$RUN_1/top20_global_all_runs"
mkdir -p "$TOP20_GLOBAL"

python3 << PYEOF
import json
from pathlib import Path
import shutil
import glob

print(f"Organizing top designs from all 5 runs...")
print(f"Output: $TOP20_GLOBAL\n")

# Copy top 20 files from each run
runs = [
    ("1", "$RUN_1"),
    ("2", "$RUN_2"),
    ("3", "$RUN_3"),
    ("4", "$RUN_4"),
    ("5", "$RUN_5"),
]

total_copied = 0
for run_id, run_path in runs:
    top20_dir = Path(run_path) / "top20"
    if not top20_dir.exists():
        print(f"  ✗ Run {run_id}: No top20 folder found")
        continue

    # Get all CIF/PDB files in top20
    files = sorted(top20_dir.glob("*.cif")) + sorted(top20_dir.glob("*.pdb"))

    if not files:
        print(f"  ✗ Run {run_id}: No structure files found")
        continue

    # Copy first 20 files (or however many exist)
    for file in files[:20]:
        dest = Path("$TOP20_GLOBAL") / f"run{run_id}_{file.name}"
        shutil.copy(file, dest)
        total_copied += 1

    print(f"  ✓ Run {run_id}: Copied {min(len(files), 20)} structures")

print(f"\n✓ Total: {total_copied} structures organized in top20_global_all_runs")
PYEOF

echo ""
