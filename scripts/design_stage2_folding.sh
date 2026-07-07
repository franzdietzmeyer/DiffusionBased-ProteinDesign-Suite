#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=========================================================================="
echo "STAGE 2: Structure Prediction and Validation"
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
            echo "Stages: folding, analysis, optimization"
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
    'engine': config.get('folding_engine', {}).get('engine', 'chai'),
    'chai_env': config.get('folding_engine', {}).get('chai', {}).get('conda_env', ''),
    'chai_recycles': config.get('folding_engine', {}).get('chai', {}).get('recycles', 3),
    'chai_timesteps': config.get('folding_engine', {}).get('chai', {}).get('timesteps', 200),
    'chai_embeddings': config.get('folding_engine', {}).get('chai', {}).get('use_esm_embeddings', True),
    'boltz_env': config.get('folding_engine', {}).get('boltz', {}).get('conda_env', ''),
    'boltz_recycles': config.get('folding_engine', {}).get('boltz', {}).get('num_recycles', 4),
    'min_plddt': config.get('filters', {}).get('min_plddt_final', 0.8),
    'min_motif_plddt': config.get('filters', {}).get('min_motif_plddt', 0.55),
    'min_ptm': config.get('filters', {}).get('min_ptm', 0.8),
    'max_rmsd': config.get('filters', {}).get('max_backbone_rmsd', 3.0),
    'max_motif_rmsd': config.get('filters', {}).get('max_motif_rmsd', 2.0),
    'pae_cutoff': config.get('filters', {}).get('pae_cutoff', 5),
    'dist_cutoff': config.get('filters', {}).get('dist_cutoff', 10),
    'min_ipsae': config.get('filters', {}).get('min_ipsae', None),
    'fixed_res_json': config.get('filters', {}).get('fixed_residues_json', ''),
    'cofactor': config.get('ligands', {}).get('cofactor_name', 'VO4'),
    'min_sasa': config.get('ligands', {}).get('min_cofactor_sasa'),
    'smiles': config.get('ligands', {}).get('smiles_list', []),
    'work_dir': config.get('output', {}).get('work_directory', ''),
    'subdir': subdir,
    'seq_opt_enabled': config.get('sequence_optimization', {}).get('enabled', False),
    'seq_opt_temp': config.get('sequence_optimization', {}).get('temperature', 0.2),
    'seq_opt_seqs': config.get('sequence_optimization', {}).get('seqs_per_backbone', 3),
    'template_dir': config.get('fixed_residues', {}).get('template_pdb_dir', ''),
    'mpnn_path': config.get('sequence_design', {}).get('ligandmpnn_path', ''),
    'mpnn_conda': config.get('sequence_design', {}).get('conda_env', ''),
    'mpnn_model': config.get('sequence_design', {}).get('model_type', 'ligand'),
}))
PYEOF
)

# Parse JSON config into variables
FOLDING_ENGINE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['engine'])")
CHAI_ENV=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['chai_env'])")
CHAI_RECYCLES=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['chai_recycles'])")
CHAI_TIMESTEPS=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['chai_timesteps'])")
BOLTZ_ENV=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['boltz_env'])")
BOLTZ_RECYCLES=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['boltz_recycles'])")
MIN_PLDDT=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['min_plddt'])")
MIN_MOTIF_PLDDT=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['min_motif_plddt'])")
MIN_PTM=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['min_ptm'])")
MAX_RMSD=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['max_rmsd'])")
MAX_MOTIF_RMSD=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['max_motif_rmsd'])")
PAE_CUTOFF=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['pae_cutoff'])")
DIST_CUTOFF=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['dist_cutoff'])")
MIN_IPSAE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; v=json.load(sys.stdin)['min_ipsae']; print(v if v is not None else '')")
FIXED_RES_JSON=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['fixed_res_json'])")
COFACTOR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['cofactor'])")
MIN_SASA=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['min_sasa'])")
WORK_DIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['work_dir'])")
SUBDIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['subdir'])")
SEQ_OPT_ENABLED=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['seq_opt_enabled'])")
TEMPLATE_DIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['template_dir'])")
MPNN_PATH=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_path'])")
MPNN_CONDA=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_conda'])")
MPNN_MODEL=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['mpnn_model'])")

# Extract and format SMILES for Chai/folding engines as bash array
# Use readarray to properly parse the Python output into a bash array
mapfile -t SMILES_ARRAY < <(echo "$CONFIG_DATA" | python3 -c "import sys, json; smiles_list = json.load(sys.stdin)['smiles']; [print('--smiles') or print(s) for s in smiles_list]")

DESIGN_DIR="$WORK_DIR/design_generation/$SUBDIR"
MPNN_OUTPUT="$DESIGN_DIR/output/mpnn_output"
MPNN_BACKBONES="$MPNN_OUTPUT/backbones"
RFD3_BACKBONES="$DESIGN_DIR/output/backbones"
RFD3_OUTPUT="$DESIGN_DIR/output/rfd3_output"
FOLDING_OUTPUT="$DESIGN_DIR/output/folding_output"
ANALYSIS_OUTPUT="$DESIGN_DIR/results"
PASSED_OUTPUT="$DESIGN_DIR/passed_designs"

# Setup checkpoints
CHECKPOINT_DIR="$DESIGN_DIR/.checkpoints"
mkdir -p "$CHECKPOINT_DIR"

echo "Configuration loaded:"
echo "  Folding engine: $FOLDING_ENGINE"
echo "  Work directory: $WORK_DIR"
echo ""

# Check if Stage 1 is complete
if [[ ! -f "$CHECKPOINT_DIR/mpnn.checkpoint" ]]; then
    echo "ERROR: Stage 1 (RFD3 + MPNN) not yet complete"
    echo "Please run Stage 1 first: ./design_stage1_rfd3_mpnn.sh --config $CONFIG_FILE"
    exit 1
fi

# ============================================================================
# STAGE 2A: Structure Prediction (Folding Engine)
# ============================================================================

if [[ "$FORCE_RERUN" == "folding" ]] && [[ -f "$CHECKPOINT_DIR/folding.checkpoint" ]]; then
    echo "Forcing folding rerun (--force-rerun folding)..."
    rm "$CHECKPOINT_DIR/folding.checkpoint"
fi

if [[ -f "$CHECKPOINT_DIR/folding.checkpoint" ]]; then
    echo "✓ Folding already completed (checkpoint exists)"
else
    echo ""
    echo "Running Structure Prediction ($FOLDING_ENGINE)..."
    echo "--------"

    mkdir -p "$FOLDING_OUTPUT"

    if [[ "$FOLDING_ENGINE" == "chai" ]]; then
        "$CHAI_ENV/bin/python" "$SCRIPT_DIR/design_refolding.py" \
            --input_dir "$MPNN_BACKBONES" \
            --output_dir "$FOLDING_OUTPUT" \
            --engine chai \
            --recycles "$CHAI_RECYCLES" \
            --timesteps "$CHAI_TIMESTEPS" \
            "${SMILES_ARRAY[@]}"

        FOLDING_EXIT_CODE=$?

        if [[ $FOLDING_EXIT_CODE -ne 0 ]]; then
            echo "✗ Folding failed with exit code $FOLDING_EXIT_CODE"
            exit $FOLDING_EXIT_CODE
        fi

    elif [[ "$FOLDING_ENGINE" == "alphafold" ]]; then
        # Extract AlphaFold configuration
        AF_HPC_MODULE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alphafold_hpc_module', 'AlphaFold'))")
        AF_DATA_DIR=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alphafold_data_dir', ''))")
        AF_MODEL_PRESET=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alphafold_model_preset', 'multimer'))")
        AF_MAX_TEMPLATE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alphafold_max_template_date', '2022-01-01'))")

        # Load AlphaFold module
        module load "$AF_HPC_MODULE"

        # Export AlphaFold database directory if specified
        if [[ -n "$AF_DATA_DIR" ]]; then
            export ALPHAFOLD_DATA_DIR="$AF_DATA_DIR"
        fi

        # Build AlphaFold arguments
        AF_ARGS="--model_preset $AF_MODEL_PRESET --max_template_date $AF_MAX_TEMPLATE"

        python3 "$SCRIPT_DIR/design_refolding.py" \
            --input_dir "$MPNN_BACKBONES" \
            --output_dir "$FOLDING_OUTPUT" \
            --engine alphafold \
            $AF_ARGS \
            "${SMILES_ARRAY[@]}"

        FOLDING_EXIT_CODE=$?

        # Clean up module
        module unload "$AF_HPC_MODULE"

        if [[ $FOLDING_EXIT_CODE -ne 0 ]]; then
            echo "✗ AlphaFold failed with exit code $FOLDING_EXIT_CODE"
            exit $FOLDING_EXIT_CODE
        fi

    elif [[ "$FOLDING_ENGINE" == "boltz" ]]; then
        # Activate Boltz environment and run
        module load Anaconda3; source /software/all/Anaconda3/2024.02-1/etc/profile.d/conda.sh
        conda activate boltz

        python3 "$SCRIPT_DIR/design_refolding.py" \
            --input_dir "$MPNN_BACKBONES" \
            --output_dir "$FOLDING_OUTPUT" \
            --engine boltz \
            --recycles "$BOLTZ_RECYCLES" \
            "${SMILES_ARRAY[@]}"

        FOLDING_EXIT_CODE=$?
        conda deactivate

        if [[ $FOLDING_EXIT_CODE -ne 0 ]]; then
            echo "✗ Boltz folding failed with exit code $FOLDING_EXIT_CODE"
            exit $FOLDING_EXIT_CODE
        fi

    else
        echo "ERROR: Unknown folding engine: $FOLDING_ENGINE"
        exit 1
    fi

    echo "✓ Folding completed successfully"
    echo "$(date)" > "$CHECKPOINT_DIR/folding.checkpoint"
fi

# ============================================================================
# STAGE 2B: Analysis and Filtering
# ============================================================================

if [[ "$FORCE_RERUN" == "analysis" ]] && [[ -f "$CHECKPOINT_DIR/analysis.checkpoint" ]]; then
    echo "Forcing analysis rerun (--force-rerun analysis)..."
    rm "$CHECKPOINT_DIR/analysis.checkpoint"
fi

if [[ -f "$CHECKPOINT_DIR/analysis.checkpoint" ]]; then
    echo "✓ Analysis already completed (checkpoint exists)"
else
    echo ""
    echo "Analyzing and Filtering Results..."
    echo "--------"

    mkdir -p "$ANALYSIS_OUTPUT"
    mkdir -p "$PASSED_OUTPUT"

    # Build filter arguments
    FILTER_ARGS="--min_plddt $MIN_PLDDT --min_motif_plddt $MIN_MOTIF_PLDDT --min_ptm $MIN_PTM --max_rmsd $MAX_RMSD --max_motif_rmsd $MAX_MOTIF_RMSD --pae_cutoff $PAE_CUTOFF --dist_cutoff $DIST_CUTOFF"
    [[ -n "$FIXED_RES_JSON" ]] && FILTER_ARGS="$FILTER_ARGS --fixed_res_json $FIXED_RES_JSON"
    [[ -n "$COFACTOR" ]] && FILTER_ARGS="$FILTER_ARGS --cofactor $COFACTOR"
    [[ -n "$MIN_SASA" && "$MIN_SASA" != "None" ]] && FILTER_ARGS="$FILTER_ARGS --min_cofactor_sasa $MIN_SASA"
    [[ -n "$MIN_IPSAE" ]] && FILTER_ARGS="$FILTER_ARGS --min_ipsae $MIN_IPSAE"

    "$CHAI_ENV/bin/python" "$SCRIPT_DIR/design_helper_script.py" \
        --input "$FOLDING_OUTPUT" \
        --output_dir "$ANALYSIS_OUTPUT" \
        --passed_output_dir "$PASSED_OUTPUT" \
        --template_pdbs "$RFD3_BACKBONES" \
        $FILTER_ARGS

    ANALYSIS_EXIT_CODE=$?

    if [[ $ANALYSIS_EXIT_CODE -ne 0 ]]; then
        echo "✗ Analysis failed with exit code $ANALYSIS_EXIT_CODE"
        exit $ANALYSIS_EXIT_CODE
    fi

    echo "✓ Analysis completed successfully"
    echo "$(date)" > "$CHECKPOINT_DIR/analysis.checkpoint"
fi

# ============================================================================
# STAGE 2C: Optional Sequence Optimization
# ============================================================================

if [[ "$SEQ_OPT_ENABLED" == "true" ]]; then
    if [[ "$FORCE_RERUN" == "optimization" ]] && [[ -f "$CHECKPOINT_DIR/optimization.checkpoint" ]]; then
        echo "Forcing optimization rerun (--force-rerun optimization)..."
        rm "$CHECKPOINT_DIR/optimization.checkpoint"
    fi

    if [[ -f "$CHECKPOINT_DIR/optimization.checkpoint" ]]; then
        echo "✓ Optimization already completed (checkpoint exists)"
    else
        echo ""
        echo "Running Sequence Optimization..."
        echo "--------"

        OPT_INPUT="$DESIGN_DIR/SequenceOptimizationInput"
        OPT_MPNN_OUTPUT="$DESIGN_DIR/output/mpnn_optimization"
        OPT_FOLDING_OUTPUT="$DESIGN_DIR/output/optimization_folding"
        OPT_RESULTS="$DESIGN_DIR/optimization_results"

        mkdir -p "$OPT_MPNN_OUTPUT"
        mkdir -p "$OPT_FOLDING_OUTPUT"
        mkdir -p "$OPT_RESULTS"

        # Prepare MPNN JSON files for optimization
        OPT_PDB_JSON="$OPT_INPUT/mpnn_pdb_paths.json"
        OPT_FIXED_JSON="$OPT_INPUT/mpnn_fixed_residues.json"

        echo "{" > "$OPT_PDB_JSON"
        echo "{" > "$OPT_FIXED_JSON"
        opt_first=true

        for opt_pdb in "$PASSED_OUTPUT"/*.pdb; do
            [ -e "$opt_pdb" ] || continue
            opt_struct=$(basename "$opt_pdb" .pdb)

            json_file=""
            for rfd3_json in "$RFD3_OUTPUT"/*.json; do
                json_base=$(basename "$rfd3_json" .json)
                if [[ "$opt_struct" == "$json_base"* ]]; then
                    json_file="$rfd3_json"
                    break
                fi
            done

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

            if [ "$opt_first" = true ]; then
                opt_first=false
            else
                sed -i '$ s/$/,/' "$OPT_PDB_JSON"
                sed -i '$ s/$/,/' "$OPT_FIXED_JSON"
            fi

            echo "  \"$opt_pdb\": \"\"" >> "$OPT_PDB_JSON"
            echo "  \"$opt_pdb\": \"$fixed_residues\"" >> "$OPT_FIXED_JSON"
        done

        echo "}" >> "$OPT_PDB_JSON"
        echo "}" >> "$OPT_FIXED_JSON"

        # Run MPNN optimization
        if [[ "$MPNN_MODEL" == "ligand" ]]; then
            CHECKPOINT="${MPNN_PATH}/model_params/ligandmpnn_v_32_030_25.pt"
        else
            CHECKPOINT="${MPNN_PATH}/model_params/${MPNN_MODEL}mpnn_v_48_030.pt"
        fi

        "$MPNN_CONDA/bin/python" "$MPNN_PATH/run.py" \
            --pdb_path_multi "$OPT_PDB_JSON" \
            --chains_to_design "A" \
            --fixed_residues_multi "$OPT_FIXED_JSON" \
            --out_folder "$OPT_MPNN_OUTPUT" \
            --temperature "$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['seq_opt_temp'])")" \
            --model_type "${MPNN_MODEL}_mpnn" \
            --checkpoint_${MPNN_MODEL}_mpnn "$CHECKPOINT" \
            --number_of_batches "$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['seq_opt_seqs'])")" \
            --batch_size 1

        # Run folding on optimized sequences
        "$CHAI_ENV/bin/python" "$SCRIPT_DIR/design_refolding.py" \
            --input_dir "$OPT_MPNN_OUTPUT/backbones" \
            --output_dir "$OPT_FOLDING_OUTPUT" \
            --engine "$FOLDING_ENGINE" \
            "${SMILES_ARRAY[@]}"

        # Final analysis on optimized designs

        FILTER_ARGS="--min_plddt $MIN_PLDDT --min_motif_plddt $MIN_MOTIF_PLDDT --min_ptm $MIN_PTM --max_rmsd $MAX_RMSD --max_motif_rmsd $MAX_MOTIF_RMSD --pae_cutoff $PAE_CUTOFF --dist_cutoff $DIST_CUTOFF"
        [[ -n "$FIXED_RES_JSON" ]] && FILTER_ARGS="$FILTER_ARGS --fixed_res_json $FIXED_RES_JSON"
        [[ -n "$COFACTOR" ]] && FILTER_ARGS="$FILTER_ARGS --cofactor $COFACTOR"
        [[ -n "$MIN_SASA" ]] && FILTER_ARGS="$FILTER_ARGS --min_cofactor_sasa $MIN_SASA"
        [[ -n "$MIN_IPSAE" ]] && FILTER_ARGS="$FILTER_ARGS --min_ipsae $MIN_IPSAE"

        "$CHAI_ENV/bin/python" "$SCRIPT_DIR/design_helper_script.py" \
            --input "$OPT_FOLDING_OUTPUT" \
            --output_dir "$OPT_RESULTS" \
            --passed_output_dir "$OPT_RESULTS/best_designs" \
            --template_pdbs "$RFD3_BACKBONES" \
            $FILTER_ARGS

        echo "✓ Optimization completed successfully"
        echo "$(date)" > "$CHECKPOINT_DIR/optimization.checkpoint"
    fi
fi

echo ""
echo "=========================================================================="
echo "Generating Analysis Plots..."
echo "=========================================================================="

PLOTS_DIR="$DESIGN_DIR/plots"
mkdir -p "$PLOTS_DIR"

"$CHAI_ENV/bin/python" "$SCRIPT_DIR/plot_analysis.py" \
    --output_dir "$DESIGN_DIR/output" \
    --plot_dir "$PLOTS_DIR"

PLOT_EXIT_CODE=$?

if [[ $PLOT_EXIT_CODE -eq 0 ]]; then
    echo "✓ Plots generated successfully"
else
    echo "⚠ Plotting completed with warnings (non-critical)"
fi

echo ""
echo "=========================================================================="
echo "STAGE 2 COMPLETE: Structure prediction and analysis finished"
echo "Results directory: $ANALYSIS_OUTPUT"
echo "Plots directory: $PLOTS_DIR"
echo "=========================================================================="
