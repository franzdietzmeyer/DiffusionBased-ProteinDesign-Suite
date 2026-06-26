#!/bin/bash
#
# Local Installation Script - GPU Pipeline for Single Linux Machine
# Simpler version of install_all.sh optimized for local machines
#

set -e

# ============================================================================
# COLORS
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
# CONFIG
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV_DIR="${CONDA_ENV_DIR:-$SCRIPT_DIR/conda-envs}"
SKIP_VERIFY=${SKIP_VERIFY:-false}
SKIP_CHECKPOINTS=${SKIP_CHECKPOINTS:-false}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --conda-env-dir) CONDA_ENV_DIR="$2"; shift 2 ;;
        --skip-verify) SKIP_VERIFY=true; shift ;;
        --skip-checkpoints) SKIP_CHECKPOINTS=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

show_help() {
    cat << EOF
${BOLD}Local GPU Pipeline Installer${NC}
Install all modules for local machine with GPU

Usage: bash install_local.sh [options]

Options:
  --conda-env-dir DIR    Conda environment directory (default: ./conda-envs/)
  --skip-verify          Skip verification tests
  --skip-checkpoints     Skip checkpoint downloads
  -h, --help            Show help

Examples:
  bash install_local.sh
  bash install_local.sh --conda-env-dir ~/envs --skip-checkpoints

EOF
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    cat << EOF

${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}
${BOLD}${BLUE}║  Local GPU Pipeline - Installer                             ║${NC}
${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Configuration:${NC}
  Script Directory:     $SCRIPT_DIR
  Conda Environments:   $CONDA_ENV_DIR
  Skip Verification:    $SKIP_VERIFY
  Skip Checkpoints:     $SKIP_CHECKPOINTS

Starting at $(date '+%Y-%m-%d %H:%M:%S')
This may take 30-60 minutes

EOF

    # Check prerequisites
    log_info "Checking prerequisites..."

    if ! command -v python3 &> /dev/null; then
        log_error "Python3 not found"
        exit 1
    fi
    log_success "Python found"

    if ! command -v conda &> /dev/null; then
        log_error "Conda not found. Install Miniconda: https://docs.conda.io/projects/miniconda/"
        exit 1
    fi
    log_success "Conda found"

    if ! command -v git &> /dev/null; then
        log_error "Git not found"
        exit 1
    fi
    log_success "Git found"

    if command -v nvidia-smi &> /dev/null; then
        log_success "NVIDIA GPU detected"
    else
        log_warn "GPU not detected (may be needed for folding)"
    fi

    # Setup conda paths
    log_info "Setting up conda paths..."
    mkdir -p "$CONDA_ENV_DIR"
    conda config --append envs_dirs "$CONDA_ENV_DIR" || true
    log_success "Conda paths configured"

    # Install RFD3
    log_info "Installing RFDiffusion (RFD3)..."
    if [[ ! -d "$SCRIPT_DIR/../rfd3_new/foundry" ]]; then
        mkdir -p "$SCRIPT_DIR/.."
        cd "$SCRIPT_DIR/.."
        log_info "Cloning Foundry repository..."
        git clone https://github.com/RosettaCommons/foundry.git rfd3_new/foundry || true
    fi

    cd "$SCRIPT_DIR/../rfd3_new/foundry" 2>/dev/null || cd "$SCRIPT_DIR/../foundry"
    if ! conda env list | grep -q "rfd3"; then
        log_info "Creating RFD3 environment..."
        conda env create -f environments/rfd3_env.yml -p "$CONDA_ENV_DIR/rfd3_env" -y
    fi
    log_success "RFD3 ready"

    # Install MPNN
    log_info "Installing LigandMPNN..."
    if [[ ! -d "$SCRIPT_DIR/../LigandMPNN" ]]; then
        cd "$SCRIPT_DIR/.."
        log_info "Cloning LigandMPNN..."
        git clone https://github.com/dauparas/LigandMPNN.git || true
    fi

    cd "$SCRIPT_DIR/../LigandMPNN"
    if [[ ! -d "model_params" ]]; then
        log_info "Downloading LigandMPNN parameters..."
        bash get_model_params.sh "./model_params" || true
    fi

    if ! conda env list | grep -q "ligandmpnn"; then
        log_info "Creating MPNN environment..."
        conda env create -f environments/ligandmpnn_env.yml -p "$CONDA_ENV_DIR/ligandmpnn_env" -y
    fi
    log_success "LigandMPNN ready"

    # Install Chai
    log_info "Installing Chai (Structure Prediction)..."
    if ! conda env list | grep -q "chai"; then
        log_info "Creating Chai environment..."
        cd "$SCRIPT_DIR"
        if [[ -f "environments/chai_env.yml" ]]; then
            conda env create -f environments/chai_env.yml -p "$CONDA_ENV_DIR/chai_env" -y
        else
            log_warn "chai_env.yml not found, creating basic environment..."
            conda create -p "$CONDA_ENV_DIR/chai_env" python=3.10 -y
        fi
    fi
    log_success "Chai ready"

    # Checkpoints
    if [[ "$SKIP_CHECKPOINTS" != true ]]; then
        log_info "Downloading RFD3 checkpoints..."
        mkdir -p "$SCRIPT_DIR/checkpoints"
        eval "$(conda shell.bash hook)"
        conda activate "$CONDA_ENV_DIR/rfd3_env" 2>/dev/null && {
            if [[ ! -f "$SCRIPT_DIR/checkpoints/rfd3_latest.ckpt" ]]; then
                foundry install rfd3 --checkpoint-dir "$SCRIPT_DIR/checkpoints" || log_warn "Checkpoint download failed"
            fi
            conda deactivate
        } || log_warn "Could not activate RFD3 environment for checkpoints"
    fi
    log_success "Installation complete!"

    # Final summary
    cat << EOF

${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}
${BOLD}${GREEN}║  Installation Successful! 🎉                                  ║${NC}
${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Environment Paths:${NC}
  Conda:       $CONDA_ENV_DIR/
  RFD3:        $CONDA_ENV_DIR/rfd3_env
  MPNN:        $CONDA_ENV_DIR/ligandmpnn_env
  Chai:        $CONDA_ENV_DIR/chai_env
  Checkpoints: $SCRIPT_DIR/checkpoints

${BOLD}Next Steps:${NC}
  1. Run pipeline: bash run_local.sh --config config/rfd3_compact_3epi.yaml
  2. Check logs:   ls logs/
  3. View results: ls HA_MES_outputs/design_generation/

EOF
}

main "$@"
