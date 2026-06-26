#!/bin/bash
#
# Master Installation Script - Multi-Stage Protein Design Pipeline
# Automates installation of all modules, environments, and dependencies
# Usage: bash install_all.sh [options]
#

set -e  # Exit on error

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
# CONFIGURATION
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$SCRIPT_DIR}"
PARENT_DIR="$(dirname "$INSTALL_DIR")"

# Conda environment directory (with smart defaults)
if [[ -z "$CONDA_ENV_DIR" ]]; then
    # Try local conda-envs/ first
    if mkdir -p "$INSTALL_DIR/conda-envs" 2>/dev/null; then
        CONDA_ENV_DIR="$(cd "$INSTALL_DIR/conda-envs" && pwd)"
    else
        # Fall back to system directory
        CONDA_ENV_DIR="/opt/conda/envs"
        mkdir -p "$CONDA_ENV_DIR" 2>/dev/null || CONDA_ENV_DIR="$HOME/conda-envs"
        mkdir -p "$CONDA_ENV_DIR"
    fi
fi

CHECKPOINT_DIR="${CHECKPOINT_DIR:-$INSTALL_DIR/checkpoints}"

# Module paths (with fallback discovery)
if [[ -z "$RFD3_DIR" ]]; then
    if [[ -d "$PARENT_DIR/rfd3_new/foundry" ]]; then
        RFD3_DIR="$PARENT_DIR/rfd3_new/foundry"
    elif [[ -d "$PARENT_DIR/foundry" ]]; then
        RFD3_DIR="$PARENT_DIR/foundry"
    else
        RFD3_DIR="$PARENT_DIR/foundry"  # Will be cloned here if doesn't exist
    fi
fi

if [[ -z "$LIGANDMPNN_DIR" ]]; then
    if [[ -d "$PARENT_DIR/LigandMPNN" ]]; then
        LIGANDMPNN_DIR="$PARENT_DIR/LigandMPNN"
    else
        LIGANDMPNN_DIR="$PARENT_DIR/LigandMPNN"  # Will be cloned here if doesn't exist
    fi
fi

# Resolve to absolute paths (safely)
if [[ -d "$CONDA_ENV_DIR" ]]; then
    CONDA_ENV_DIR="$(cd "$CONDA_ENV_DIR" && pwd)"
fi

mkdir -p "$CHECKPOINT_DIR"
CHECKPOINT_DIR="$(cd "$CHECKPOINT_DIR" && pwd)"

mkdir -p "$(dirname "$RFD3_DIR")"
mkdir -p "$(dirname "$LIGANDMPNN_DIR")"

# Conda env names
RFD3_ENV="rfd3_env"
MPNN_ENV="ligandmpnn_env"
CHAI_ENV="chai_env"
BOLTZ_ENV="boltz203"

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================
SKIP_VERIFY=false
SKIP_CHECKPOINTS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-verify) SKIP_VERIFY=true; shift ;;
        --skip-checkpoints) SKIP_CHECKPOINTS=true; shift ;;
        --conda-env-dir) CONDA_ENV_DIR="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --rfd3-dir) RFD3_DIR="$2"; shift 2 ;;
        --mpnn-dir) LIGANDMPNN_DIR="$2"; shift 2 ;;
        --checkpoint-dir) CHECKPOINT_DIR="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
show_help() {
    cat << EOF
${BOLD}Master Installation Script${NC}
Automates setup of Multi-Stage Protein Design Pipeline

Usage: bash install_all.sh [options]

Options:
  --skip-verify          Skip verification tests after installation
  --skip-checkpoints     Skip checkpoint downloads
  --conda-env-dir DIR    Custom conda environment directory
                         Can be relative (e.g., conda-envs/) or absolute
                         Default: auto-detected or /work2/fd55fani-conda
  --rfd3-dir DIR         Custom RFD3/Foundry installation directory
  --mpnn-dir DIR         Custom LigandMPNN installation directory
  --checkpoint-dir DIR   Custom checkpoint directory
  -h, --help            Show this help message

Examples:
  # Use local conda-envs directory
  bash install_all.sh --conda-env-dir conda-envs/

  # Custom locations
  bash install_all.sh \\
    --conda-env-dir ~/conda-envs \\
    --rfd3-dir ~/software/foundry \\
    --mpnn-dir ~/software/LigandMPNN

  # Skip checkpoints
  bash install_all.sh --skip-checkpoints

  # Minimal
  bash install_all.sh

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 not found. Please install Python 3.10+"
        exit 1
    fi
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    log_success "Python $PYTHON_VERSION found"

    # Check Conda
    if ! command -v conda &> /dev/null; then
        log_error "Conda not found. Please install Miniconda or Anaconda"
        exit 1
    fi
    log_success "Conda found"

    # Check Git
    if ! command -v git &> /dev/null; then
        log_error "Git not found. Please install Git"
        exit 1
    fi
    log_success "Git found"

    # Check CUDA/GPU
    if ! command -v nvidia-smi &> /dev/null; then
        log_warn "nvidia-smi not found. GPU-dependent modules may fail"
    else
        CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        log_success "NVIDIA GPU detected (Driver: $CUDA_VERSION)"
    fi
}

setup_conda_paths() {
    log_info "Setting up conda environment paths..."

    # Create conda env directory if it doesn't exist
    mkdir -p "$CONDA_ENV_DIR"

    # Configure conda to use custom environment directory
    conda config --append envs_dirs "$CONDA_ENV_DIR" || true

    log_success "Conda environment directory: $CONDA_ENV_DIR"
}

install_rfd3() {
    log_info "Installing RFDiffusion (RFD3 + Foundry)..."

    # Check if already cloned
    if [[ ! -d "$RFD3_DIR" ]]; then
        log_info "Cloning Foundry repository..."
        mkdir -p "$(dirname "$RFD3_DIR")"
        cd "$(dirname "$RFD3_DIR")"
        git clone https://github.com/RosettaCommons/foundry.git "$(basename "$RFD3_DIR")"
    else
        log_warn "Foundry directory already exists: $RFD3_DIR"
    fi

    cd "$RFD3_DIR"

    # Check if conda env exists
    if conda env list | grep -q "$RFD3_ENV"; then
        log_warn "Conda environment '$RFD3_ENV' already exists"
    else
        log_info "Creating RFD3 conda environment..."
        # Try to find and use environment YAML
        ENV_FILE=""
        if [[ -f "environments/rfd3_env.yml" ]]; then
            ENV_FILE="environments/rfd3_env.yml"
        elif [[ -f "env/rfd3_env.yml" ]]; then
            ENV_FILE="env/rfd3_env.yml"
        fi

        if [[ -n "$ENV_FILE" ]]; then
            conda env create -f "$ENV_FILE" -p "$CONDA_ENV_DIR/$RFD3_ENV" -y
        else
            log_warn "No environment YAML found, creating basic Python environment..."
            conda create -p "$CONDA_ENV_DIR/$RFD3_ENV" python=3.12 -y
            eval "$(conda shell.bash hook)"
            conda activate "$CONDA_ENV_DIR/$RFD3_ENV"
            pip install 'rc-foundry[rfd3]' || log_warn "Could not install rc-foundry, will need manual setup"
            conda deactivate
        fi
    fi

    log_success "RFD3 environment ready"
}

install_mpnn() {
    log_info "Installing LigandMPNN (Sequence Design)..."

    # Check if already cloned
    if [[ ! -d "$LIGANDMPNN_DIR" ]]; then
        log_info "Cloning LigandMPNN repository..."
        mkdir -p "$(dirname "$LIGANDMPNN_DIR")"
        cd "$(dirname "$LIGANDMPNN_DIR")"
        git clone https://github.com/dauparas/LigandMPNN.git "$(basename "$LIGANDMPNN_DIR")"
    else
        log_warn "LigandMPNN directory already exists: $LIGANDMPNN_DIR"
    fi

    cd "$LIGANDMPNN_DIR"

    # Download model parameters
    if [[ ! -d "model_params" ]]; then
        log_info "Downloading LigandMPNN model parameters..."
        if [[ -f "get_model_params.sh" ]]; then
            bash get_model_params.sh "./model_params"
        else
            log_error "get_model_params.sh not found in $LIGANDMPNN_DIR"
            return 1
        fi
    else
        log_warn "Model parameters already downloaded"
    fi

    # Check if conda env exists
    if conda env list | grep -q "$MPNN_ENV"; then
        log_warn "Conda environment '$MPNN_ENV' already exists"
    else
        log_info "Creating MPNN conda environment..."
        ENV_FILE=""
        if [[ -f "environments/ligandmpnn_env.yml" ]]; then
            ENV_FILE="environments/ligandmpnn_env.yml"
        elif [[ -f "env/ligandmpnn_env.yml" ]]; then
            ENV_FILE="env/ligandmpnn_env.yml"
        fi

        if [[ -n "$ENV_FILE" ]]; then
            conda env create -f "$ENV_FILE" -p "$CONDA_ENV_DIR/$MPNN_ENV" -y
        else
            log_warn "No environment YAML found, creating basic Python environment..."
            conda create -p "$CONDA_ENV_DIR/$MPNN_ENV" python=3.11 -y
            eval "$(conda shell.bash hook)"
            conda activate "$CONDA_ENV_DIR/$MPNN_ENV"
            pip install -e . 2>/dev/null || log_warn "Could not install LigandMPNN, will need manual setup"
            conda deactivate
        fi
    fi

    log_success "LigandMPNN environment ready"
}

install_chai() {
    log_info "Installing Chai (Structure Prediction)..."

    # Check if conda env exists
    if conda env list | grep -q "$CHAI_ENV"; then
        log_warn "Conda environment '$CHAI_ENV' already exists"
    else
        log_info "Creating Chai conda environment..."
        if [[ -f "$INSTALL_DIR/environments/chai_env.yml" ]]; then
            conda env create -f "$INSTALL_DIR/environments/chai_env.yml" -p "$CONDA_ENV_DIR/$CHAI_ENV" -y
        else
            log_warn "chai_env.yml not found, creating basic environment..."
            conda create -p "$CONDA_ENV_DIR/$CHAI_ENV" python=3.10 -y
            eval "$(conda shell.bash hook)"
            conda activate "$CONDA_ENV_DIR/$CHAI_ENV"
            pip install git+https://github.com/chaidiscovery/chai-lab.git
            conda deactivate
        fi
    fi

    log_success "Chai environment ready"
}

install_boltz() {
    log_info "Installing Boltz (Structure Prediction)..."

    # Check if conda env exists
    if conda env list | grep -q "$BOLTZ_ENV"; then
        log_warn "Conda environment '$BOLTZ_ENV' already exists"
    else
        log_info "Creating Boltz conda environment..."
        if [[ -f "$INSTALL_DIR/environments/boltz_env.yml" ]]; then
            conda env create -f "$INSTALL_DIR/environments/boltz_env.yml" -p "$CONDA_ENV_DIR/$BOLTZ_ENV" -y
        else
            log_warn "boltz_env.yml not found, creating basic environment..."
            conda create -p "$CONDA_ENV_DIR/$BOLTZ_ENV" python=3.10 -y
            eval "$(conda shell.bash hook)"
            conda activate "$CONDA_ENV_DIR/$BOLTZ_ENV"
            pip install boltz-suite
            conda deactivate
        fi
    fi

    log_success "Boltz environment ready"
}

download_checkpoints() {
    if [[ "$SKIP_CHECKPOINTS" == true ]]; then
        log_warn "Skipping checkpoint download (--skip-checkpoints)"
        return
    fi

    log_info "Downloading RFD3 checkpoints..."
    mkdir -p "$CHECKPOINT_DIR"

    # Download checkpoints
    if [[ -f "$CHECKPOINT_DIR/rfd3_latest.ckpt" ]]; then
        log_warn "RFD3 checkpoints already downloaded"
    else
        log_info "This may take several minutes..."
        eval "$(conda shell.bash hook)"
        conda activate "$CONDA_ENV_DIR/$RFD3_ENV"
        foundry install rfd3 --checkpoint-dir "$CHECKPOINT_DIR" || {
            log_error "Failed to download RFD3 checkpoints. Please try manually:"
            log_error "  conda activate $CONDA_ENV_DIR/$RFD3_ENV"
            log_error "  foundry install rfd3 --checkpoint-dir $CHECKPOINT_DIR"
        }
        conda deactivate
    fi

    log_success "Checkpoints ready"
}

verify_installations() {
    if [[ "$SKIP_VERIFY" == true ]]; then
        log_warn "Skipping verification (--skip-verify)"
        return
    fi

    log_info "Verifying installations..."

    eval "$(conda shell.bash hook)"

    # Test RFD3
    log_info "Testing RFD3..."
    if conda activate "$CONDA_ENV_DIR/$RFD3_ENV" 2>/dev/null && python -c "from foundry import rfd3; print('RFD3 OK')" 2>/dev/null && conda deactivate; then
        log_success "RFD3 verified"
    else
        log_warn "RFD3 verification failed (may work despite this)"
    fi

    # Test MPNN
    log_info "Testing LigandMPNN..."
    if conda activate "$CONDA_ENV_DIR/$MPNN_ENV" 2>/dev/null && python -c "import sys; sys.path.insert(0, '$LIGANDMPNN_DIR'); import ligandmpnn; print('MPNN OK')" 2>/dev/null && conda deactivate; then
        log_success "LigandMPNN verified"
    else
        log_warn "LigandMPNN verification failed (may work despite this)"
    fi

    # Test Chai
    log_info "Testing Chai..."
    if conda activate "$CONDA_ENV_DIR/$CHAI_ENV" 2>/dev/null && python -c "from chai_lab import chai1; print('Chai OK')" 2>/dev/null && conda deactivate; then
        log_success "Chai verified"
    else
        log_warn "Chai verification failed (may work despite this)"
    fi

    # Test Boltz
    log_info "Testing Boltz..."
    if conda activate "$CONDA_ENV_DIR/$BOLTZ_ENV" 2>/dev/null && python -c "import boltz; print('Boltz OK')" 2>/dev/null && conda deactivate; then
        log_success "Boltz verified"
    else
        log_warn "Boltz verification failed (may work despite this)"
    fi
}

print_summary() {
    cat << EOF

${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}
${BOLD}${GREEN}║     Installation Complete! 🎉                                  ║${NC}
${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Environment Paths:${NC}
  Conda Environments: $CONDA_ENV_DIR
  RFD3 Installation:  $RFD3_DIR
  LigandMPNN:        $LIGANDMPNN_DIR
  Checkpoints:       $CHECKPOINT_DIR

${BOLD}Installed Environments:${NC}
  • $RFD3_ENV (RFDiffusion)
  • $MPNN_ENV (LigandMPNN)
  • $CHAI_ENV (Chai)
  • $BOLTZ_ENV (Boltz)

${BOLD}Next Steps:${NC}
  1. Test the pipeline with a sample config:
     ./submit_design_pipeline.sh --config config/rfd3_compact_3epi.yaml

  2. Check configuration in: ${INSTALL_DIR}/config/

  3. View pipeline status:
     ./scripts/monitor_pipeline.sh --live

${BOLD}For Help:${NC}
  • README: cat README.md
  • Config guide: cat config/rfd3_compact_3epi.yaml
  • Logs: ls -lah logs/

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    cat << EOF
${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}
${BOLD}${BLUE}║  Multi-Stage Protein Design Pipeline - Master Installer       ║${NC}
${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}

${BOLD}Installation Paths:${NC}
  Script Location:      $SCRIPT_DIR
  Install Directory:    $INSTALL_DIR
  Parent Directory:     $PARENT_DIR

${BOLD}Environment & Module Paths:${NC}
  Conda Environments:   $CONDA_ENV_DIR
  Checkpoint Directory: $CHECKPOINT_DIR
  RFD3 Installation:    $RFD3_DIR
  LigandMPNN Path:      $LIGANDMPNN_DIR

${BOLD}Options:${NC}
  Verify Installs:      ${SKIP_VERIFY:-false}
  Download Checkpoints: ${SKIP_CHECKPOINTS:-true}

Starting installation at $(date '+%Y-%m-%d %H:%M:%S')
${BOLD}This may take 30-60 minutes depending on your internet speed and GPU${NC}

EOF

    check_prerequisites
    setup_conda_paths
    install_rfd3
    install_mpnn
    install_chai
    install_boltz
    download_checkpoints
    verify_installations
    print_summary

    log_success "Installation finished at $(date '+%Y-%m-%d %H:%M:%S')"
}

main "$@"
