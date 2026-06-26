#!/bin/bash
#
# Local GPU Pipeline Runner - Multi-stage protein design on single machine
# Runs Stage 1 (RFD3 + MPNN) and Stage 2 (Folding) sequentially
# Works on local Linux machines with 1+ GPU
#

set -e

# ============================================================================
# COLORS AND FORMATTING
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# ============================================================================
# PATHS
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
LOGS_DIR="$SCRIPT_DIR/logs"
CONFIG_DIR="$SCRIPT_DIR/config"

mkdir -p "$LOGS_DIR"

# ============================================================================
# USAGE
# ============================================================================
usage() {
    cat << EOF
${BOLD}Local GPU Pipeline Runner${NC}
Multi-stage protein design on a single Linux machine with GPU

Usage: bash run_local.sh --config <config.yaml> [options]

${BOLD}Required:${NC}
  --config FILE              Config file (YAML format)

${BOLD}Optional:${NC}
  --stage1-only              Run only Stage 1 (RFD3 + MPNN)
  --stage2-only              Run only Stage 2 (Folding + Analysis)
  --force-rerun STAGE        Force rerun of specific stage (rfd3, mpnn, folding, analysis)
  --gpu GPU_ID               GPU ID to use (default: 0)
  --max-workers N            Max parallel workers (default: 1)
  -h, --help                 Show this help message

${BOLD}Examples:${NC}
  bash run_local.sh --config config/rfd3_compact_3epi.yaml
  bash run_local.sh --config config/rfd3_contig_3epi.yaml --stage1-only
  bash run_local.sh --config config/rfd3_medium_3epi.yaml --gpu 0

${BOLD}Note:${NC}
  - Pipeline runs sequentially (Stage 1 → Stage 2)
  - All outputs saved to: HA_MES_outputs/design_generation/
  - Logs saved to: logs/
  - GPU must be available (check: nvidia-smi)

EOF
}

# ============================================================================
# CONFIGURATION
# ============================================================================
CONFIG_FILE=""
STAGE1_ONLY=false
STAGE2_ONLY=false
FORCE_RERUN=""
GPU_ID=0
MAX_WORKERS=1

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --stage1-only) STAGE1_ONLY=true; shift ;;
        --stage2-only) STAGE2_ONLY=true; shift ;;
        --force-rerun) FORCE_RERUN="$2"; shift 2 ;;
        --gpu) GPU_ID="$2"; shift 2 ;;
        --max-workers) MAX_WORKERS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    log_error "Config file required"
    usage
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config not found: $CONFIG_FILE"
    exit 1
fi

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
check_gpu() {
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. GPU required but not detected."
        exit 1
    fi

    if ! nvidia-smi -i "$GPU_ID" &> /dev/null; then
        log_error "GPU $GPU_ID not found. Available GPUs:"
        nvidia-smi --list-gpus
        exit 1
    fi

    log_success "GPU $GPU_ID ready"
}

check_conda_env() {
    local env_name=$1
    local env_path=$2

    if [[ -d "$env_path" ]]; then
        log_success "Environment found: $env_name"
        return 0
    else
        log_error "Environment not found: $env_name at $env_path"
        log_error "Run: bash install_local.sh --conda-env-dir conda-envs/"
        exit 1
    fi
}

print_header() {
    cat << EOF

${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}
${BOLD}${BLUE}║  Local GPU Pipeline - Multi-Stage Protein Design             ║${NC}
${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Configuration:${NC}
  Config File:       $CONFIG_FILE
  GPU Device:        $GPU_ID
  Max Workers:       $MAX_WORKERS
  Logs Directory:    $LOGS_DIR
  Scripts:           $SCRIPTS_DIR

${BOLD}Stages:${NC}
  Stage 1: $([ "$STAGE2_ONLY" = true ] && echo "⊘ Skipped" || echo "✓ RFD3 + MPNN")
  Stage 2: $([ "$STAGE1_ONLY" = true ] && echo "⊘ Skipped" || echo "✓ Folding + Analysis")

Starting at $(date '+%Y-%m-%d %H:%M:%S')

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    print_header
    check_gpu

    # Export GPU for scripts
    export CUDA_VISIBLE_DEVICES="$GPU_ID"
    export PIPELINE_GPU="$GPU_ID"

    log_info "Loading configuration from: $CONFIG_FILE"

    # Run Stage 1 if not skipped
    if [[ "$STAGE2_ONLY" != true ]]; then
        log_info "════════════════════════════════════════════════════════════"
        log_info "STAGE 1: Backbone Generation & Sequence Design"
        log_info "════════════════════════════════════════════════════════════"

        STAGE1_LOG="$LOGS_DIR/stage1_local_$(date +%s).log"
        log_info "Running Stage 1... (log: $STAGE1_LOG)"

        if bash "$SCRIPTS_DIR/design_stage1_rfd3_mpnn.sh" \
            --config "$CONFIG_FILE" \
            --force-rerun "$FORCE_RERUN" \
            --gpu "$GPU_ID" \
            --max-workers "$MAX_WORKERS" \
            2>&1 | tee "$STAGE1_LOG"; then
            log_success "Stage 1 completed successfully"
        else
            log_error "Stage 1 failed (see log: $STAGE1_LOG)"
            exit 1
        fi
    fi

    # Run Stage 2 if not skipped
    if [[ "$STAGE1_ONLY" != true ]]; then
        log_info ""
        log_info "════════════════════════════════════════════════════════════"
        log_info "STAGE 2: Structure Prediction & Validation"
        log_info "════════════════════════════════════════════════════════════"

        STAGE2_LOG="$LOGS_DIR/stage2_local_$(date +%s).log"
        log_info "Running Stage 2... (log: $STAGE2_LOG)"

        if bash "$SCRIPTS_DIR/design_stage2_folding.sh" \
            --config "$CONFIG_FILE" \
            --force-rerun "$FORCE_RERUN" \
            --gpu "$GPU_ID" \
            2>&1 | tee "$STAGE2_LOG"; then
            log_success "Stage 2 completed successfully"
        else
            log_error "Stage 2 failed (see log: $STAGE2_LOG)"
            exit 1
        fi
    fi

    # Final summary
    cat << EOF

${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}
${BOLD}${GREEN}║  Pipeline Complete! 🎉                                        ║${NC}
${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Results:${NC}
  Output Directory: ./HA_MES_outputs/design_generation/
  Logs Directory:   ./logs/

${BOLD}Next Steps:${NC}
  1. View results: ls -lah HA_MES_outputs/design_generation/
  2. Check analysis: cat HA_MES_outputs/design_generation/*/plots/
  3. Review top designs: ls HA_MES_outputs/design_generation/*/top20/

Completed at $(date '+%Y-%m-%d %H:%M:%S')

EOF
}

main "$@"
