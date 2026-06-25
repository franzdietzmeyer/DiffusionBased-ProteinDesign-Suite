# Multi-Stage Protein Design Pipeline

A modular, production-ready pipeline for **protein design and structure prediction** combining RFDiffusion, sequence design (MPNN), and multiple folding engines (Chai, AlphaFold, Boltz).

![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Status](https://img.shields.io/badge/Status-Production-brightgreen.svg)

### Core Pipeline Components

1. **RFDiffusion** - Backbone generation
   ```
   Lin et al. (2024). "Diffusion-based protein design" 
   Code: https://github.com/RosettaCommons/foundry
   ```

2. **MPNN (Sequence Design)**
   ```
   Dauparas et al. (2022). "ProteinMPNN"
   https://github.com/dauparas/LigandMPNN
   ```

3. **Chai Research** - Structure prediction
   ```
   https://github.com/chai-research
   ```

4. **AlphaFold2** - Structure prediction alternative
   ```
   Jumper et al. (2021). "Highly accurate protein structure 
   prediction with AlphaFold2"
   https://github.com/google-deepmind/alphafold
   ```

5. **Boltz** - Structure prediction alternative
   ```
   https://github.com/jwohlwend/boltz
   ```

6. **Binder Design Framework**
   ```
   https://github.com/nrbennet/dl_binder_design
   ```

---

## Features

- **Checkpoint-based resumption** — Resume from any stage without recalculating earlier stages
- **Modular folding engines** — Easily swap between Chai, AlphaFold, and Boltz
- **Graceful error handling** — Stage failures don't require full restart
- **SLURM-optimized** — Separate jobs prevent timeouts and optimize resource allocation
- **Comprehensive logging** — All outputs organized in `logs/` directory
- **Configuration-driven** — Single YAML file controls all parameters
- **Cluster support** — Flexible partition selection (paula/clara)
- **Output organization** — Automatic directory structure with results filtering

---

## 🔧 Installation Guide

### Prerequisites

- Python 3.10+
- Conda or Mamba package manager
- CUDA-capable GPU (for folding engines)
- Git

### Module Installation

#### 1. RFDiffusion (RFD3) + Foundry

**Clone and setup Foundry:**

```bash
git clone https://github.com/RosettaCommons/foundry.git
cd foundry
```

**Create conda environment from YAML:**

```bash
conda env create -f environments/rfd3_env.yml
conda activate rfd3
```

**Install Foundry packages:**

```bash
# For complete installation (RFD3, LigandMPNN, ProteinMPNN, RF3):
uv pip install 'rc-foundry[all]'

# OR for RFD3 only:
uv pip install rc-foundry[rfd3]
```

**Download RFD3 checkpoints:**

```bash
# All checkpoints
foundry install all --checkpoint-dir /path/to/checkpoint/dir

# RFD3 only
foundry install rfd3 --checkpoint-dir /path/to/checkpoint/dir
```

---

#### 2. LigandMPNN (Sequence Design)

```bash
# Clone repository
git clone https://github.com/dauparas/LigandMPNN.git
cd LigandMPNN

# Download model parameters
bash get_model_params.sh "./model_params"

# Create conda environment from YAML:
conda env create -f environments/ligandmpnn_env.yml
conda activate ligandmpnn_env
```

---

#### 3. Chai1 (Structure Prediction)

**Create conda environment from YAML:**

```bash
conda env create -f environments/chai_env.yml
conda activate chai_env
```

Chai is already installed in the environment.

---

#### 4. AlphaFold2 (Optional Alternative)

Follow the official AlphaFold2 installation guide:
- https://github.com/google-deepmind/alphafold

Typically loaded as an HPC module:
```bash
module load AlphaFold
```

---

#### 5. Boltz (Optional Alternative)

**Create conda environment from YAML:**

```bash
conda env create -f environments/boltz_env.yml
conda activate boltz203
```

Boltz is already installed in the environment.

---

### Verify Installations

Test that each module is correctly installed:

```bash
# Test RFD3
source /path/to/rfd3_env/bin/activate
python -c "from foundry import rfd3; print('RFD3 OK')"

# Test LigandMPNN
source /path/to/ligandmpnn_env/bin/activate
python -c "import ligandmpnn; print('LigandMPNN OK')"

# Test Chai
source /path/to/chai_env/bin/activate
python -c "from chai_lab import chai1; print('Chai OK')"

# Test Boltz
source /path/to/boltz_env/bin/activate
python -c "import boltz; print('Boltz OK')"
```

---

## Pipeline Overview

### Two-Stage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   INPUT PDB (Epitope)                       │
└────────────────────────────┬────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   STAGE 1 JOB   │
                    └────────┬────────┘
                             │
            ┌────────────────┴────────────────┐
            │                                 │
    ┌───────▼────────┐           ┌──────────▼──────────┐
    │  RFDiffusion   │           │      MPNN Seq       │
    │  (Backbone)    │──────────▶│    Design (×N)      │
    └────────────────┘           └──────────┬──────────┘
                                            │
                                 ┌──────────▼──────────┐
                                 │   STAGE 2 JOB       │
                                 └──────────┬──────────┘
                                            │
                  ┌─────────────────────────┼─────────────────────────┐
                  │                         │                         │
         ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
         │     Chai1       │      │   AlphaFold2    │      │     Boltz       │
         │  (Folding)      │      │  (Folding)      │      │  (Folding)      │
         └────────┬────────┘      └────────┬────────┘      └────────┬────────┘
                  │                         │                         │
                  └─────────────────────────┼─────────────────────────┘
                                            │
                                 ┌──────────▼──────────┐
                                 │    Analysis &      │
                                 │ Filtering (pLDDT,  │
                                 │ RMSD, etc.)        │
                                 └──────────┬──────────┘
                                            │
                    ┌───────────────────────┴───────────────────────┐
                    │                                               │
         ┌──────────▼──────────┐                     ┌─────────────▼────────┐
         │  Passed Designs     │                     │ Detailed Analysis    │
         │  (High Quality)     │                     │ (Logs & Metrics)     │
         └─────────────────────┘                     └──────────────────────┘
```

### Stage 1: Backbone Generation & Sequence Design
- **Duration**: ~6-12 hours
- **Input**: Template PDB + RFD3 settings JSON
- **Process**: 
  - RFDiffusion generates protein backbones
  - MPNN designs sequences for each backbone
  - Fixed residues automatically extracted from RFD3 outputs
- **Output**: Designed sequences (PDB format)

### Stage 2: Structure Prediction & Validation
- **Duration**: Variable (depends on folding engine)
- **Input**: Designed sequences from Stage 1
- **Process**:
  - Selected folding engine predicts 3D structures
  - Confidence filtering (pLDDT, RMSD thresholds)
  - Optional sequence optimization round
- **Output**: 
  - Predicted structures (PDB/CIF)
  - Passed designs (filtered by quality metrics)
  - Analysis metrics and logs

---

## Quick Start

### 1. Setup Conda Environments

Create all conda environments from the provided YAML files:

```bash
conda env create -f environments/rfd3_env.yml
conda env create -f environments/ligandmpnn_env.yml
conda env create -f environments/chai_env.yml
conda env create -f environments/boltz_env.yml
```

Verify installations by running the test commands in the "Verify Installations" section of the Installation Guide.

### 2. Configure Your Design

Copy and customize the example configuration:

```bash
cp config/example_design.yaml config/my_design.yaml
nano config/my_design.yaml
```

**Key parameters to set:**

```yaml
# Input settings
rfd3:
  settings_json: "/path/to/your_design.json"      # RFD3 design parameters
  checkpoint: "/path/to/rfd3_latest.ckpt"         # RFD3 checkpoint
  foundry_path: "/path/to/rfd3/foundry"           # RFD3 environment

# Folding engine (choose one: chai, alphafold, boltz)
folding_engine:
  engine: "chai"                                   # or "boltz", "alphafold"
  chai:
    conda_env: "/path/to/chai_env"

# Output location
output:
  work_directory: "/path/to/results"              # Base output directory
  subdirectory: "design_run_001"                  # Run name

# Hardware
hardware:
  partition: "paula"                              # paula (8x A30) or clara (4x V100)
```

### 3. Submit the Pipeline

```bash
./submit_design_pipeline.sh --config config/my_design.yaml
```

Monitor job submission:
```bash
squeue -u $USER
```

### 4. Monitor Progress

Check stage-specific logs:
```bash
tail -f logs/stage1_*.log
tail -f logs/stage2_*.log
```

View job status:
```bash
squeue -j <job_id>
```

---

## Directory Structure

```
pipeline_scaffolding/
├── README.md                           # This file
├── config/
│   ├── design_pipeline.yaml            # Configuration template (all options)
│   ├── example_design.yaml             # Pre-filled example
│   └── HA_design.yaml                  # Your specific design config
├── scripts/
│   ├── design_stage1_rfd3_mpnn.sh      # Stage 1 implementation
│   ├── design_stage2_folding.sh        # Stage 2 implementation
│   ├── design_refolding.py             # Folding engine interface
│   ├── design_helper_script.py         # Utility functions
│   ├── config_utils.py                 # Configuration loader
│   └── convert_cif_gz.py               # File format conversion
├── submit_design_pipeline.sh           # Main entry point
├── logs/                               # Pipeline logs (auto-created)
└── environments/                       # Conda environment YAML files (TODO)
```

### Output Directory Structure

```
work_directory/design_generation/subdirectory/
├── output/
│   ├── rfd3_output/                    # RFDiffusion outputs
│   │   ├── *.json                      # Design metadata
│   │   └── *.pdb                       # Generated structures
│   ├── backbones/                      # RFD3 backbones
│   │   └── *.pdb
│   ├── mpnn_output/                    # MPNN sequences
│   │   ├── backbones/                  # Designed backbone structures
│   │   └── *.json                      # Sequence information
│   ├── folding_output/                 # Folding predictions
│   │   ├── <engine>_output/            # Engine-specific (chai/boltz/alphafold)
│   │   └── *.pdb / *.cif               # Predicted structures
│   └── analysis/                       # Filtered & analyzed results
│       ├── metrics.csv                 # Design metrics
│       └── *.pdb                       # Analyzed structures
├── passed_predictions/                 # High-quality designs only
│   └── *.pdb
└── .checkpoints/                       # Pipeline state (for resumption)
    ├── rfd3.checkpoint
    ├── mpnn.checkpoint
    ├── folding.checkpoint
    └── analysis.checkpoint
```

---

## Configuration Guide

### Folding Engines

#### Chai1
Recommended for accuracy and speed:
```yaml
folding_engine:
  engine: "chai"
  chai:
    conda_env: "/path/to/chai_env"
    recycles: 3                    # More = slower but potentially better
    timesteps: 200
    use_esm_embeddings: true
```

#### AlphaFold2
For multimer designs:
```yaml
folding_engine:
  engine: "alphafold"
  alphafold:
    hpc_module: "AlphaFold"
    data_dir: "/path/to/alphafold/db"
    model_preset: "multimer"       # or "monomer"
    max_template_date: "2022-01-01"
```

#### Boltz
Single-sequence mode (no MSA):
```yaml
folding_engine:
  engine: "boltz"
  boltz:
    conda_env: "/path/to/boltz_env"
    num_recycles: 4
```

### Hardware Selection

Choose based on your GPU availability:

| Partition | GPUs | CUDA Cores | Tensor Cores | Memory | Best For |
|-----------|------|-----------|--------------|--------|----------|
| **paula** | 8x A30 | 10,752 | 336 | 24GB HBM2 | Large batch sizes |
| **clara** | 4x V100 | 5,120 | 640 | 32GB HBM2 | Fast compute |

```yaml
hardware:
  partition: "paula"              # paula or clara
  cpus_per_task: 4
  memory_per_task: "40G"
  gpus_per_task: 1
  time_limit: "24:00:00"
```

### Filtering & Analysis

```yaml
filters:
  min_plddt_initial: 75.0         # After initial folding
  min_plddt_final: 80.0           # Final results
  min_motif_plddt: 85.0           # Active site residues
  max_backbone_rmsd: 2.0          # vs template (Ångströms)
  max_motif_rmsd: 1.5             # Active site (Ångströms)
```

---

## Advanced Usage

### Resume from Checkpoint

Resume from a specific stage:
```bash
./submit_design_pipeline.sh --config config/my_design.yaml --force-rerun folding
```

Available stages: `rfd3`, `mpnn`, `folding`, `analysis`

### Dry-Run Mode

See what would be submitted without executing:
```bash
./submit_design_pipeline.sh --config config/my_design.yaml --dry-run
```

### Override Cluster Settings

```bash
./submit_design_pipeline.sh \
  --config config/my_design.yaml \
  --partition paula \
  --cpus 8 \
  --mem 60G \
  --time 48:00:00
```

### Compare Folding Engines

Run the same design with different engines:

```bash
# With Chai
cp config/my_design.yaml config/my_design_chai.yaml
sed -i 's/engine: .*/engine: "chai"/' config/my_design_chai.yaml
./submit_design_pipeline.sh --config config/my_design_chai.yaml

# With Boltz
cp config/my_design.yaml config/my_design_boltz.yaml
sed -i 's/engine: .*/engine: "boltz"/' config/my_design_boltz.yaml
./submit_design_pipeline.sh --config config/my_design_boltz.yaml
```

---

## Understanding Outputs

### Design Metrics

Key metrics saved in `analysis/metrics.csv`:

| Metric | Range | Interpretation |
|--------|-------|-----------------|
| **pLDDT** | 0-100 | Confidence in structure prediction (higher = better) |
| **backbone_rmsd** | Ångströms | Deviation from template (lower = better) |
| **motif_rmsd** | Ångströms | Active site deviation (lower = better) |
| **num_design_positions** | Integer | Positions that were designed |

### File Formats

- **PDB**: Standard Protein Data Bank format
- **CIF**: Crystallographic Information File (more precise)
- **JSON**: Design metadata and parameters
- **CSV**: Analysis metrics and summary tables

---

## Troubleshooting

### Pipeline Won't Start

```bash
# Check config syntax
python3 scripts/config_utils.py config/my_design.yaml

# Check SLURM availability
sinfo
```

### Stage Times Out

- Increase `time_limit` in hardware config
- Reduce `n_batches` or `seqs_per_backbone`
- Check available GPU memory: `nvidia-smi`

### Low Quality Results

- Increase `recycles` (for Chai)
- Improve RFD3 settings (longer designs, better constraints)
- Use `min_plddt_final: 80.0` or higher

### Conda Environment Issues

```bash
# Activate and test environment
source /path/to/conda_env/bin/activate
python3 -c "import torch; print(torch.cuda.is_available())"
```

---

## How to Cite

If you use this pipeline, please cite the following works:

### Core Pipeline Components

1. **RFDiffusion** - Backbone generation
   ```
   Lin et al. (2024). "Diffusion-based protein design" 
   Code: https://github.com/RosettaCommons/foundry
   ```

2. **MPNN (Sequence Design)**
   ```
   Dauparas et al. (2022). "ProteinMPNN"
   https://github.com/dauparas/LigandMPNN
   ```

3. **Chai Research** - Structure prediction
   ```
   https://github.com/chai-research
   ```

4. **AlphaFold2** - Structure prediction alternative
   ```
   Jumper et al. (2021). "Highly accurate protein structure 
   prediction with AlphaFold2"
   https://github.com/google-deepmind/alphafold
   ```

5. **Boltz** - Structure prediction alternative
   ```
   https://github.com/jwohlwend/boltz
   ```

6. **Binder Design Framework**
   ```
   https://github.com/nrbennet/dl_binder_design
   ```

---

## Authors & Contributors

**Pipeline Development**: Multi-stage design workflow created for protein engineering applications.

**Acknowledgments**:
- thanks to Paul Schebeck for granting me access to his version.
- RosettaCommons team (Foundry, RFDiffusion)
- DeepMind AlphaFold team
- Chai Research
- Dauparas et al. (LigandMPNN)
- dl_binder_design framework contributors

---

## License

This pipeline implementation is provided as-is for research purposes.

**License of dependencies**: Each module retains its original license. Please refer to individual repositories:
- [RFDiffusion](https://github.com/RosettaCommons/foundry)
- [LigandMPNN](https://github.com/dauparas/LigandMPNN)
- [AlphaFold](https://github.com/google-deepmind/alphafold)
- [Chai](https://github.com/chai-research)
- [Boltz](https://github.com/jwohlwend/boltz)

---

## Support

For issues and questions:
1. Check the **Troubleshooting** section above
2. Review configuration examples in `config/`
3. Check log files: `logs/stage1_*.log`, `logs/stage2_*.log`
4. Verify SLURM job status: `squeue -j <job_id>`

---

## External Resources

- [RFDiffusion Documentation](https://github.com/RosettaCommons/foundry)
- [Chai Research](https://github.com/chai-research)
- [Boltz Prediction Docs](https://github.com/jwohlwend/boltz/blob/main/docs/prediction.md)
- [AlphaFold GitHub](https://github.com/google-deepmind/alphafold)
- [LigandMPNN](https://github.com/dauparas/LigandMPNN)

---

**Last Updated**: 2026-06-25  
