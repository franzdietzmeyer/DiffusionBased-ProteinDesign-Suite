#!/bin/bash
#
# Monitor job completion status for all design configs
# Checks for top20/ or results/ folders to determine if a job finished successfully
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "=========================================================================="
echo "Job Completion Monitor"
echo "=========================================================================="
echo ""

# Header
printf "%-40s %-15s %-10s\n" "Config" "Status" "Folder"
printf "%-40s %-15s %-10s\n" "------" "------" "------"

completed=0
running=0
failed=0

# Iterate through all YAML config files
for config_file in "$CONFIG_DIR"/*.yaml; do
    [[ -f "$config_file" ]] || continue

    config_name=$(basename "$config_file" .yaml)

    # Extract work_directory and subdirectory using Python
    read -r work_dir subdir < <(python3 << PYEOF
import sys
import yaml
import os
from pathlib import Path

try:
    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f)

    work_dir = config.get('output', {}).get('work_directory', '')
    config_subdir = config.get('output', {}).get('subdirectory', '')

    # If no subdirectory specified, use JSON filename
    if not config_subdir or config_subdir == 'design_run':
        rfd3_settings = config.get('rfd3', {}).get('settings_json', '')
        json_name = os.path.splitext(os.path.basename(rfd3_settings))[0]
        subdir = json_name if json_name else 'design_run'
    else:
        subdir = config_subdir

    print(f"{work_dir} {subdir}")
except Exception as e:
    print(f"ERROR {config_name}", file=sys.stderr)
PYEOF
    )

    if [[ -z "$work_dir" ]]; then
        printf "%-40s %-15s %-10s\n" "$config_name" "ERROR" "-"
        ((failed++))
        continue
    fi

    # Construct design directory path
    design_dir="$work_dir/design_generation/$subdir"

    # Check for completion markers
    if [[ -d "$design_dir/top20" ]]; then
        status="✓ COMPLETE"
        folder="top20"
        ((completed++))
    elif [[ -d "$design_dir/results" ]]; then
        status="✓ COMPLETE"
        folder="results"
        ((completed++))
    elif [[ -d "$design_dir/output" ]]; then
        status="⏳ RUNNING"
        folder="output"
        ((running++))
    elif [[ -d "$design_dir" ]]; then
        status="⏳ RUNNING"
        folder="exists"
        ((running++))
    else
        status="✗ NOT FOUND"
        folder="-"
        ((failed++))
    fi

    printf "%-40s %-15s %-10s\n" "$config_name" "$status" "$folder"
done

echo ""
echo "=========================================================================="
echo "Summary:"
echo "  ✓ Completed: $completed"
echo "  ⏳ Running:   $running"
echo "  ✗ Failed:    $failed"
echo "=========================================================================="
