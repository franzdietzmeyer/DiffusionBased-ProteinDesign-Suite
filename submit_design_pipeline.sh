#!/bin/bash
#
# Main job submission script for multi-stage design pipeline
# Submits Stage 1 and Stage 2 with proper SLURM dependencies
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
LOGS_DIR="$SCRIPT_DIR/logs"

usage() {
    echo "Usage: $0 --config <config.yaml> [options]"
    echo ""
    echo "Required:"
    echo "  --config FILE              Config file (YAML format)"
    echo ""
    echo "Optional:"
    echo "  --stage1-only              Submit only Stage 1 (RFD3 + MPNN)"
    echo "  --stage2-only              Submit only Stage 2 (folding + analysis)"
    echo "  --dry-run                  Print job submissions without executing"
    echo "  --force-rerun STAGE        Force rerun of specific stage"
    echo "  --partition PARTITION      SLURM partition (overrides config)"
    echo "  --cpus CPUS                CPUs per task (overrides config)"
    echo "  --mem MEM                  Memory per task (overrides config)"
    echo "  --gpus GPUS                GPUs per task (overrides config)"
    echo "  --time TIME                Time limit (overrides config)"
    echo ""
    echo "Partition options (set in config hardware.partition):"
    echo "  paula                      8x Nvidia Tesla A30 (10,752 CUDA, 336 Tensor, 24GB HBM2)"
    echo "  clara                      4x Nvidia Tesla V100 (5,120 CUDA, 640 Tensor, 32GB HBM2)"
    echo ""
    echo "  -h, --help                 Show this help message"
}

# Default values
CONFIG_FILE=""
STAGE1_ONLY=false
STAGE2_ONLY=false
DRY_RUN=false
FORCE_RERUN=""
PARTITION=""
CPUS=""
MEM=""
GPUS=""
TIME=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift ;;
        --stage1-only) STAGE1_ONLY=true ;;
        --stage2-only) STAGE2_ONLY=true ;;
        --dry-run) DRY_RUN=true ;;
        --force-rerun) FORCE_RERUN="$2"; shift ;;
        --partition) PARTITION="$2"; shift ;;
        --cpus) CPUS="$2"; shift ;;
        --mem) MEM="$2"; shift ;;
        --gpus) GPUS="$2"; shift ;;
        --time) TIME="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
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

# Load hardware settings from config if not provided via command-line
HARDWARE_CONFIG=$(python3 << PYEOF
import sys
import yaml

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = yaml.safe_load(f)

    hardware = config.get('hardware', {})
    print(f"partition={hardware.get('partition', 'paula')}")
    print(f"cpus={hardware.get('cpus_per_task', 4)}")
    print(f"mem={hardware.get('memory_per_task', '40G')}")
    print(f"gpus={hardware.get('gpus_per_task', 1)}")
    print(f"time={hardware.get('time_limit', '24:00:00')}")
except Exception as e:
    print(f"error=Failed to load hardware config: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to parse hardware configuration from YAML"
    exit 1
fi

# Apply config values (command-line args override config file)
eval "$HARDWARE_CONFIG"
if [[ -z "$PARTITION" ]]; then PARTITION="$partition"; fi
if [[ -z "$CPUS" ]]; then CPUS="$cpus"; fi
if [[ -z "$MEM" ]]; then MEM="$mem"; fi
if [[ -z "$GPUS" ]]; then GPUS="$gpus"; fi
if [[ -z "$TIME" ]]; then TIME="$time"; fi

mkdir -p "$LOGS_DIR"

echo "=========================================================================="
echo "Design Pipeline Job Submission"
echo "=========================================================================="
echo ""
echo "Configuration: $CONFIG_FILE"
echo "Logs directory: $LOGS_DIR"
echo "Partition: $PARTITION | CPUs: $CPUS | Memory: $MEM | GPUs: $GPUS | Time: $TIME"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "*** DRY RUN MODE - No jobs will be submitted ***"
    echo ""
fi

# ============================================================================
# STAGE 1: RFDiffusion + MPNN
# ============================================================================

if [[ "$STAGE2_ONLY" != true ]]; then
    echo "Submitting Stage 1 (RFDiffusion + MPNN)..."

    STAGE1_SCRIPT=$(cat << 'STAGE1_EOF'
#!/bin/bash
#SBATCH --job-name=design_stage1
#SBATCH --partition=PARTITION_PLACEHOLDER
#SBATCH --cpus-per-task=CPUS_PLACEHOLDER
#SBATCH --mem=MEM_PLACEHOLDER
#SBATCH --gres=gpu:GPUS_PLACEHOLDER
#SBATCH --time=TIME_PLACEHOLDER
#SBATCH --output=LOGS_PLACEHOLDER/stage1_%J.log
#SBATCH --error=LOGS_PLACEHOLDER/stage1_%J.err

set -e
cd REPO_ROOT_PLACEHOLDER

SCRIPTS_DIR/design_stage1_rfd3_mpnn.sh \
    --config CONFIG_FILE_PLACEHOLDER \
    FORCE_RERUN_PLACEHOLDER

echo "✓ Stage 1 completed"
STAGE1_EOF
)

    # Replace placeholders
    STAGE1_SCRIPT="${STAGE1_SCRIPT//PARTITION_PLACEHOLDER/$PARTITION}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//CPUS_PLACEHOLDER/$CPUS}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//MEM_PLACEHOLDER/$MEM}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//GPUS_PLACEHOLDER/$GPUS}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//TIME_PLACEHOLDER/$TIME}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//LOGS_PLACEHOLDER/$LOGS_DIR}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//REPO_ROOT_PLACEHOLDER/$REPO_ROOT}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//SCRIPTS_DIR/$SCRIPTS_DIR}"
    STAGE1_SCRIPT="${STAGE1_SCRIPT//CONFIG_FILE_PLACEHOLDER/$CONFIG_FILE}"

    if [[ -n "$FORCE_RERUN" ]]; then
        STAGE1_SCRIPT="${STAGE1_SCRIPT//FORCE_RERUN_PLACEHOLDER/--force-rerun $FORCE_RERUN}"
    else
        STAGE1_SCRIPT="${STAGE1_SCRIPT//FORCE_RERUN_PLACEHOLDER/}"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "Stage 1 job script:"
        echo "$STAGE1_SCRIPT"
        echo ""
        STAGE1_JOB_ID="12345"
    else
        STAGE1_JOB_ID=$(echo "$STAGE1_SCRIPT" | sbatch --parsable)
        echo "✓ Stage 1 submitted with job ID: $STAGE1_JOB_ID"
    fi
fi

# ============================================================================
# STAGE 2: Structure Prediction + Analysis
# ============================================================================

if [[ "$STAGE1_ONLY" != true ]]; then
    echo ""
    echo "Submitting Stage 2 (Structure Prediction + Analysis)..."

    STAGE2_SCRIPT=$(cat << 'STAGE2_EOF'
#!/bin/bash
#SBATCH --job-name=design_stage2
#SBATCH --partition=PARTITION_PLACEHOLDER
#SBATCH --cpus-per-task=CPUS_PLACEHOLDER
#SBATCH --mem=MEM_PLACEHOLDER
#SBATCH --gres=gpu:GPUS_PLACEHOLDER
#SBATCH --time=TIME_PLACEHOLDER
#SBATCH --output=LOGS_PLACEHOLDER/stage2_%J.log
#SBATCH --error=LOGS_PLACEHOLDER/stage2_%J.err
DEPENDENCY_PLACEHOLDER

set -e
cd REPO_ROOT_PLACEHOLDER

SCRIPTS_DIR/design_stage2_folding.sh \
    --config CONFIG_FILE_PLACEHOLDER \
    FORCE_RERUN_PLACEHOLDER

echo "✓ Stage 2 completed"
STAGE2_EOF
)

    # Add dependency if Stage 1 was submitted
    if [[ "$STAGE2_ONLY" != true ]] && [[ -n "$STAGE1_JOB_ID" ]]; then
        DEPENDENCY="#SBATCH --dependency=afterok:$STAGE1_JOB_ID"
    else
        DEPENDENCY=""
    fi

    # Replace placeholders
    STAGE2_SCRIPT="${STAGE2_SCRIPT//PARTITION_PLACEHOLDER/$PARTITION}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//CPUS_PLACEHOLDER/$CPUS}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//MEM_PLACEHOLDER/$MEM}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//GPUS_PLACEHOLDER/$GPUS}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//TIME_PLACEHOLDER/$TIME}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//LOGS_PLACEHOLDER/$LOGS_DIR}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//REPO_ROOT_PLACEHOLDER/$REPO_ROOT}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//SCRIPTS_DIR/$SCRIPTS_DIR}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//CONFIG_FILE_PLACEHOLDER/$CONFIG_FILE}"
    STAGE2_SCRIPT="${STAGE2_SCRIPT//DEPENDENCY_PLACEHOLDER/$DEPENDENCY}"

    if [[ -n "$FORCE_RERUN" ]]; then
        STAGE2_SCRIPT="${STAGE2_SCRIPT//FORCE_RERUN_PLACEHOLDER/--force-rerun $FORCE_RERUN}"
    else
        STAGE2_SCRIPT="${STAGE2_SCRIPT//FORCE_RERUN_PLACEHOLDER/}"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "Stage 2 job script:"
        echo "$STAGE2_SCRIPT"
        echo ""
        STAGE2_JOB_ID="12346"
    else
        STAGE2_JOB_ID=$(echo "$STAGE2_SCRIPT" | sbatch --parsable)
        echo "✓ Stage 2 submitted with job ID: $STAGE2_JOB_ID"
    fi
fi

echo ""
echo "=========================================================================="
echo "Job Submission Summary"
echo "=========================================================================="

if [[ "$STAGE2_ONLY" != true ]]; then
    echo "Stage 1 Job ID: $STAGE1_JOB_ID"
fi

if [[ "$STAGE1_ONLY" != true ]]; then
    echo "Stage 2 Job ID: $STAGE2_JOB_ID"
    if [[ "$STAGE2_ONLY" != true ]]; then
        echo "  Depends on: Stage 1 ($STAGE1_JOB_ID)"
    fi
fi

echo ""
echo "Monitor progress with: squeue -j <job_id>"
echo "View logs in: $LOGS_DIR"
echo "=========================================================================="
