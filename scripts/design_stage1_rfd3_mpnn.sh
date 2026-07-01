#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=========================================================================="
echo "STAGE 1: Backbone Generation (RFDiffusion) + Sequence Design (MPNN)"
echo "=========================================================================="
echo ""

# Parse arguments
CONFIG_FILE=""
FORCE_RERUN=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift ;;
        --force-rerun) FORCE_RERUN="$2"; shift ;;
        -h|--help)
            echo "Usage: $0 --config <config.yaml> [--force-rerun stage]"
            echo "Stages: rfd3, mpnn"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$CONFIG_FILE" ]]; then
    echo "ERROR: --config is required"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Load and validate config
python3 "$SCRIPT_DIR/config_utils.py" "$CONFIG_FILE" || exit 1

# Extract config values using Python
CONFIG_DATA=$(python3 << PYEOF
import sys
sys.path.insert(0, '/work2/fd55fani-genie3/pipeline_scaffolding/scripts')
from config_utils import load_config
import json

config = load_config('$CONFIG_FILE').to_dict()

import os

rfd3_settings = config.get('rfd3', {}).get('settings_json', '')
config_subdir = config.get('output', {}).get('subdirectory', '')

# Use JSON filename as subdirectory if config subdirectory is empty
if not config_subdir or config_subdir == 'design_run':
    json_name = os.path.splitext(os.path.basename(rfd3_settings))[0]
    subdir = json_name if json_name else 'design_run'
else:
    subdir = config_subdir

print(json.dumps({
    'rfd3_settings': rfd3_settings,
    'rfd3_checkpoint': config.get('rfd3', {}).get('checkpoint', ''),
    'rfd3_batch_size': config.get('rfd3', {}).get('batch_size', 4),
    'rfd3_n_batches': config.get('rfd3', {}).get('n_batches', 5),
    'rfd3_foundry': config.get('rfd3', {}).get('foundry_path', ''),
    'rfd3_step_scale': config.get('rfd3', {}).get('inference_sampler_step_scale', 1.5),
    'mpnn_model': config.get('sequence_design', {}).get('model_type', 'ligand'),
    'mpnn_temperature': config.get('sequence_design', {}).get('temperature', 0.1),
    'mpnn_seqs': config.get('sequence_design', {}).get('seqs_per_backbone', 15),
    'mpnn_conda': config.get('sequence_design', {}).get('conda_env', ''),
    'mpnn_path': config.get('sequence_design', {}).get('ligandmpnn_path', ''),
    'work_dir': config.get('output', {}).get('work_directory', ''),
    'subdir': subdir,
    'smiles': config.get('ligands', {}).get('smiles_list', []),
    'template_dir': config.get('fixed_residues', {}).get('template_pdb_dir', ''),
}))
PYEOF
)

# Parse JSON config into variables
RFD3_SETTINGS=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['rfd3_settings'])")
RFD3_CHECKPOINT=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['rfd3_checkpoint'])")
RFD3_BATCH_SIZE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['rfd3_batch_size'])")
RFD3_N_BATCHES=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['rfd3_n_batches'])")
RFD3_FOUNDRY=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['rfd3_foundry'])")
RFD3_STEP_SCALE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['rfd3_step_scale'])")
MPNN_MODEL=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_model'])")
MPNN_TEMPERATURE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_temperature'])")
MPNN_SEQS=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_seqs'])")
MPNN_CONDA=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_conda'])")
MPNN_PATH=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_path'])")
WORK_DIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['work_dir'])")
SUBDIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['subdir'])")
TEMPLATE_DIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['template_dir'])")

DESIGN_DIR="$WORK_DIR/design_generation/$SUBDIR"
RFD3_OUTPUT="$DESIGN_DIR/output/rfd3_output"
RFD3_BACKBONES="$DESIGN_DIR/output/backbones"
MPNN_OUTPUT="$DESIGN_DIR/output/mpnn_output"

# Setup checkpoints
CHECKPOINT_DIR="$DESIGN_DIR/.checkpoints"
mkdir -p "$CHECKPOINT_DIR"

echo "Configuration loaded:"
echo "  Work directory: $WORK_DIR"
echo "  RFD3 checkpoint: $RFD3_CHECKPOINT"
echo "  MPNN model: $MPNN_MODEL"
echo ""

# ============================================================================
# STAGE 1A: RFDiffusion (RFD3)
# ============================================================================

if [[ "$FORCE_RERUN" == "rfd3" ]] && [[ -f "$CHECKPOINT_DIR/rfd3.checkpoint" ]]; then
    echo "Forcing RFD3 rerun (--force-rerun rfd3)..."
    rm "$CHECKPOINT_DIR/rfd3.checkpoint"
fi

if [[ -f "$CHECKPOINT_DIR/rfd3.checkpoint" ]]; then
    echo "✓ RFD3 already completed (checkpoint exists)"
else
    echo ""
    echo "Running RFD3 Backbone Generation..."
    echo "--------"

    mkdir -p "$RFD3_OUTPUT"

    # Create temporary settings file to avoid naming conflicts (use absolute path)
    TEMP_SETTINGS="$CHECKPOINT_DIR/$SUBDIR.json"
    cp "$RFD3_SETTINGS" "$TEMP_SETTINGS"

    # Activate RFD3 environment and run
    module load Anaconda3; source /software/all/Anaconda3/2024.02-1/etc/profile.d/conda.sh; source "$RFD3_FOUNDRY/bin/activate"

    rfd3 design \
        out_dir="$RFD3_OUTPUT" \
        inputs="$TEMP_SETTINGS" \
        ckpt_path="$RFD3_CHECKPOINT" \
        diffusion_batch_size="$RFD3_BATCH_SIZE" \
        n_batches="$RFD3_N_BATCHES" \
        inference_sampler.step_scale="$RFD3_STEP_SCALE"

    RFD3_EXIT_CODE=$?
    rm -f "$TEMP_SETTINGS"
    deactivate

    if [[ $RFD3_EXIT_CODE -ne 0 ]]; then
        echo "✗ RFD3 failed with exit code $RFD3_EXIT_CODE"
        exit $RFD3_EXIT_CODE
    fi

    echo "✓ RFD3 completed successfully"
    echo "$(date)" > "$CHECKPOINT_DIR/rfd3.checkpoint"
fi

# ============================================================================
# Extract .cif.gz files to .pdb
# ============================================================================

echo ""
echo "Converting RFD3 output structures (.cif.gz -> .pdb)..."
echo "--------"

mkdir -p "$RFD3_BACKBONES"
python3 "$SCRIPT_DIR/convert_cif_gz.py" "$RFD3_OUTPUT" --format pdb
mv "$RFD3_OUTPUT"/*.pdb "$RFD3_BACKBONES/" 2>/dev/null || true

PDB_COUNT=$(ls "$RFD3_BACKBONES"/*.pdb 2>/dev/null | wc -l)
echo "✓ Converted $PDB_COUNT structures"

if [[ $PDB_COUNT -eq 0 ]]; then
    echo "✗ No PDB files generated from RFD3 output"
    exit 1
fi

# ============================================================================
# STAGE 1B: Sequence Design (MPNN)
# ============================================================================

if [[ "$FORCE_RERUN" == "mpnn" ]] && [[ -f "$CHECKPOINT_DIR/mpnn.checkpoint" ]]; then
    echo "Forcing MPNN rerun (--force-rerun mpnn)..."
    rm "$CHECKPOINT_DIR/mpnn.checkpoint"
fi

if [[ -f "$CHECKPOINT_DIR/mpnn.checkpoint" ]]; then
    echo "✓ MPNN already completed (checkpoint exists)"
else
    echo ""
    echo "Running MPNN Sequence Design..."
    echo "--------"

    mkdir -p "$MPNN_OUTPUT"

    # Prepare MPNN input JSON files
    MPNN_PDB_JSON="$RFD3_BACKBONES/mpnn_pdb_paths.json"
    MPNN_FIXED_JSON="$RFD3_BACKBONES/mpnn_fixed_residues.json"

    echo "{" > "$MPNN_PDB_JSON"
    echo "{" > "$MPNN_FIXED_JSON"
    first_entry=true

    for pdb in "$RFD3_BACKBONES"/*.pdb; do
        struct=$(basename "$pdb" .pdb)
        json_file="$RFD3_OUTPUT/${struct}.json"

        fixed_residues=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    mp = data.get('diffused_index_map', {})
    fixed_str = ' '.join(mp.values())
    print(fixed_str)
except Exception:
    print('')
" "$json_file")

        if [ "$first_entry" = true ]; then
            first_entry=false
        else
            sed -i '$ s/$/,/' "$MPNN_PDB_JSON"
            sed -i '$ s/$/,/' "$MPNN_FIXED_JSON"
        fi

        echo "\"$pdb\":\"\"" >> "$MPNN_PDB_JSON"
        fixed_residues_escaped=$(echo "$fixed_residues" | sed 's/"/\\"/g')
        echo "\"$pdb\":\"$fixed_residues_escaped\"" >> "$MPNN_FIXED_JSON"
    done

    echo "}" >> "$MPNN_PDB_JSON"
    echo "}" >> "$MPNN_FIXED_JSON"

    # Run MPNN
    if [[ "$MPNN_MODEL" == "ligand" ]]; then
        CHECKPOINT="${MPNN_PATH}/model_params/ligandmpnn_v_32_030_25.pt"
    else
        CHECKPOINT="${MPNN_PATH}/model_params/${MPNN_MODEL}mpnn_v_48_030.pt"
    fi

    "$MPNN_CONDA/bin/python" "$MPNN_PATH/run.py" \
        --pdb_path_multi "$MPNN_PDB_JSON" \
        --chains_to_design "A" \
        --fixed_residues_multi "$MPNN_FIXED_JSON" \
        --out_folder "$MPNN_OUTPUT" \
        --temperature "$MPNN_TEMPERATURE" \
        --model_type "${MPNN_MODEL}_mpnn" \
        --checkpoint_${MPNN_MODEL}_mpnn "$CHECKPOINT" \
        --number_of_batches "$MPNN_SEQS" \
        --batch_size 1

    MPNN_EXIT_CODE=$?
    if [[ $MPNN_EXIT_CODE -ne 0 ]]; then
        echo "✗ MPNN failed with exit code $MPNN_EXIT_CODE"
        exit $MPNN_EXIT_CODE
    fi

    echo "✓ MPNN completed successfully"
    echo "$(date)" > "$CHECKPOINT_DIR/mpnn.checkpoint"
fi

echo ""
echo "=========================================================================="
echo "STAGE 1 COMPLETE: Backbone generation and sequence design finished"
echo "Output directory: $DESIGN_DIR"
echo "Next: Submit Stage 2 job for structure prediction"
echo "=========================================================================="
