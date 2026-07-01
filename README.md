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

## 🚀 Quick Start

**New users:** Start here!

```bash
bash install_all.sh
./submit_design_pipeline.sh --config config/rfd3_compact_3epi.yaml
```

👉 See [QUICKSTART.md](QUICKSTART.md) for detailed guide and troubleshooting.

---

## 📖 Table of Contents

- [Quick Start](#-quick-start) — Get up and running in minutes
- [Installation Guide](#-installation-guide) — Automated or manual setup
- [Features](#features) — What this pipeline offers
- [Pipeline Overview](#pipeline-overview) — How it works
- [Configuration](#configuration) — Customize your designs
- [Running the Pipeline](#running-the-pipeline) — Submit jobs and monitor
- [Output & Results](#output--results) — Understanding the results
- [Troubleshooting](#troubleshooting) — Common issues
- [External Resources](#external-resources) — Links to original tools

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
- **Automated installation** — Single-command setup with `install_all.sh`

---

## 🔧 Installation Guide

### ⚡ Quick Installation (Recommended)

**Automated installation with a single command:**

```bash
bash install_all.sh
```

This script automatically:
- ✅ Checks prerequisites (Python, Conda, Git, GPU)
- ✅ Clones all repositories (Foundry, LigandMPNN)
- ✅ Creates all conda environments (RFD3, MPNN, Chai, Boltz)
- ✅ Downloads model checkpoints (~30-45 min)
- ✅ Verifies installations
- ✅ Prints setup summary

**Installation time:** ~45-90 minutes (depending on internet speed)

**Skip checkpoint download for faster setup:**
```bash
bash install_all.sh --skip-checkpoints
```

**For more options and troubleshooting, see:** [QUICKSTART.md](QUICKSTART.md)

---

### Manual Installation (Detailed)

If you prefer to install components manually, follow these steps:

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

**If using `install_all.sh`:**
The verification is done automatically at the end of installation.

**Manual verification (if installing manually):**

```bash
# Test RFD3
conda activate /work2/fd55fani-conda/rfd3_env
python -c "from foundry import rfd3; print('RFD3 OK')"
conda deactivate

# Test LigandMPNN
conda activate /work2/fd55fani-conda/ligandmpnn_env
python -c "import ligandmpnn; print('LigandMPNN OK')"
conda deactivate

# Test Chai
conda activate /work2/fd55fani-conda/chai_env
python -c "from chai_lab import chai1; print('Chai OK')"
conda deactivate

# Test Boltz
conda activate /work2/fd55fani-conda/boltz203
python -c "import boltz; print('Boltz OK')"
conda deactivate
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

## 📊 Analysis & Comparison Tools

### Multi-Run Analysis: `run_analysis.sh`

After 5 parallel design runs complete, aggregate and analyze results across all runs.

**Usage:**
```bash
./run_analysis.sh --config config/sialinbinder_with_ligand.yaml
```

**What it does:**
1. ✅ Finds all 5 run directories (Run 1-5)
2. ✅ Loads top 20 structures from each run (100 total)
3. ✅ Aggregates metrics (ipTM, pTM, pLDDT, RMSD)
4. ✅ Calculates global ranking across all runs
5. ✅ Generates visualization plots
6. ✅ Exports results to CSV
7. ✅ Collects top 20 globally into `top20_global_all_runs/`

**Output Files:**
- `all_structures_[name]_ligand.csv` — All 100 structures with metrics
- `top100_structures_[name]_ligand.csv` — Top 100 ranked globally
- `all_structures_[name]_ligand.png` — Scatter plot: all structures
- `top100_structures_[name]_ligand.png` — Scatter plot: top 100 only
- `perrun_statistics_[name]_ligand.png` — Box plots per run
- `top100_global_ranking_[name]_ligand.json` — Full ranking data
- `top20_global_all_runs/` — Folder with 100 best structures

**Key Metrics (Ligand Designs):**

| Metric | Target | Meaning |
|--------|--------|---------|
| **Best Score** | >0.92 | Peak performance |
| **Mean Score** | >0.88 | Average quality |
| **Best ipTM** | >0.93 | Best binding prediction |
| **Mean ipTM** | >0.88 | Consistent binding quality |
| **Best pLDDT** | >92 | Confident prediction |
| **Mean pLDDT** | >89 | Consistent confidence |

---

### Job Monitoring: `monitor_jobs.sh`

Check completion status of all design approaches at once.

**Usage:**
```bash
./monitor_jobs.sh
```

**Output:**
```
Config                                   Status          Folder    
------                                   ------          ------    
sialinbinder_with_ligand                 ✓ COMPLETE    top20     
sialinbinder_exposed                     ✓ COMPLETE    top20     
sialinbinder_partexposed                 ⏳ RUNNING     output    
sialinbinder_pocket_refined              ✗ NOT FOUND    -     
```

**Indicators:**
- ✓ **COMPLETE** — Job finished (has `top20/` or `results/`)
- ⏳ **RUNNING** — In progress (has `output/` folder)
- ✗ **NOT FOUND** — Directory doesn't exist

---

### Cross-Approach Comparison: `compare_approaches.sh`

Compare multiple design approaches to find the best strategy.

**Usage:**
```bash
./compare_approaches.sh
```

**Output Tables:**

1. **Overall Ranking by Best Score** — Which approach has best single design?
2. **Ranking by Mean Score** — Which is most consistent?
3. **Ranking by ipTM/pTM** — Which has best ligand binding?
4. **Top 3 Recommendations** — Quick summary

**Example Output:**
```
OVERALL RANKING BY BEST SCORE
Approach                Best Score  Mean Score  Best ipTM  Mean ipTM
sialinbinder_exposed       0.9418      0.9291     0.9438     0.9308
sialinbinder_partexposed   0.9433      0.9282     0.9500     0.9272
sialinbinder_with_ligand   0.9299      0.8905     0.9315     0.8882

TOP 3 RECOMMENDED APPROACHES
1️⃣  BEST SINGLE DESIGN:    sialinbinder_partexposed (0.9433)
2️⃣  MOST CONSISTENT:       sialinbinder_exposed (Mean: 0.9291, Std: 0.0063)
3️⃣  BEST LIGAND BINDING:   sialinbinder_exposed (Mean ipTM: 0.9308)
```

**Output:**
- `sialinbinder_approach_comparison.csv` — Detailed metrics for spreadsheet analysis

---

### Extract Best Designs: `extract_best_designs.sh`

Collect the top-ranked design from each approach into one folder for easy comparison.

**Usage:**
```bash
./extract_best_designs.sh
```

**Output:**
```
best_designs_global/
├── 01_sialinbinder_exposed.cif
├── 02_sialinbinder_partexposed.cif
├── 03_sialinbinder_with_ligand.cif
└── ... (one per approach)
```

Use these structures for:
- Visual inspection in ChimeraX/PyMOL
- Wet-lab validation
- Further refinement

---

## 🔄 Complete Analysis Workflow

### Step 1: Monitor Jobs
```bash
./monitor_jobs.sh
```
Wait until designs show "✓ COMPLETE"

### Step 2: Run Analysis for Each Approach
```bash
./run_analysis.sh --config config/sialinbinder_exposed.yaml
./run_analysis.sh --config config/sialinbinder_with_ligand.yaml
./run_analysis.sh --config config/sialinbinder_partexposed.yaml
# ... repeat for all approaches
```

### Step 3: Compare Approaches
```bash
./compare_approaches.sh
```

### Step 4: Extract Winners
```bash
./extract_best_designs.sh
```

### Step 5: Visual Inspection
```bash
# Open in structure viewer (ChimeraX, PyMOL, Jmol)
cd best_designs_global/
# Open .cif files to inspect binding interfaces
```

---

## 📈 Understanding Analysis Results

### Score Calculation (Ligand Designs)

```
Aggregate Score = 0.8 × ipTM + 0.2 × (pLDDT/100) - RMSD_penalty
```

**Weights:**
- **80% ipTM** — Ligand-protein interface quality (most important!)
- **20% pLDDT** — Overall protein confidence
- **RMSD penalty** — Backbone deviation from template

### Metric Interpretation

**ipTM/pTM (Interface Template Modeling)**
```
>0.93 = Excellent ⭐⭐⭐ — Very confident binding prediction
0.88-0.93 = Good  ⭐⭐   — Solid prediction
0.80-0.88 = Fair  ⭐    — Reasonable, worth testing
<0.80  = Uncertain ❌   — High uncertainty
```

**pLDDT (Predicted Local Distance Difference Test)**
```
>92 = Very High Confidence — Excellent structure prediction
85-92 = High Confidence    — Good prediction
75-85 = Moderate          — Moderate confidence
<75   = Low Confidence    — Uncertain
```

**RMSD (Root Mean Square Deviation)**
```
<2.0 Å  = Excellent    — Very close to template
2-3 Å   = Good         — Moderate deviation
3-4 Å   = Acceptable   — Significant but okay
>4 Å    = Poor         — Major deviation
```

### Consistency Metrics

**Mean vs Best Score:**
- **High Best, Low Mean** → Lottery (few great, many mediocre)
- **High Best, High Mean** → Reliable (consistently good)

**Standard Deviation:**
- **Std < 0.01** → Very consistent ✓
- **Std 0.01-0.02** → Reasonably consistent
- **Std > 0.02** → Inconsistent (lottery-like)

---

## 📚 Configuration Options Reference

### Design Approaches

**Protein-Only (No Ligand)**
```yaml
ligands:
  smiles_list: []           # Empty = no ligand
```

**With Ligand/Cofactor**
```yaml
ligands:
  smiles_list:
    - "NAME SMILES_STRING"  # e.g., "glycan O1C(O)..."
  cofactor_name: "glycan"   # Identifier for filtering
  min_cofactor_sasa: 10.0   # Optional SASA threshold
```

### Folding Engine Selection

**Chai (Recommended)**
```yaml
folding_engine:
  engine: "chai"
  chai:
    conda_env: "/path/to/chai_env"
    recycles: 3             # 1-5 (more = slower)
    timesteps: 200
    use_esm_embeddings: true
```

**AlphaFold2**
```yaml
folding_engine:
  engine: "alphafold"
  alphafold:
    model_preset: "multimer"  # or "monomer"
    max_template_date: "2022-01-01"
```

**Boltz**
```yaml
folding_engine:
  engine: "boltz"
  boltz:
    num_recycles: 4
```

### Quality Thresholds

```yaml
filters:
  min_plddt_initial: 50     # Initial folding filter
  min_plddt_final: 75       # Final results filter
  min_motif_plddt: 55       # Active site confidence
  max_backbone_rmsd: 3.5    # Template deviation
  max_backbone_rmsd: 1.5    # Active site deviation
```

Higher values = stricter filtering = fewer but higher-quality results

### Parallel Run Configuration

```yaml
output:
  work_directory: "/path/to/SialinBinder"
  # Generates: SialinBinder/, SialinBinder_2, SialinBinder_3, etc.
```

**Automatically detects 5 runs for aggregation:**
- `SialinBinder/design_generation/approach_name`
- `SialinBinder_2/design_generation/approach_name`
- `SialinBinder_3/design_generation/approach_name`
- `SialinBinder_4/design_generation/approach_name`
- `SialinBinder_5/design_generation/approach_name`

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

## Getting Help

### Installation Issues?
```bash
bash install_all.sh --help
```
See [QUICKSTART.md](QUICKSTART.md) for detailed troubleshooting.

### Pipeline Issues?
1. Check the **Troubleshooting** section in [QUICKSTART.md](QUICKSTART.md)
2. Review configuration examples in `config/`
3. Check log files:
   ```bash
   tail -100 logs/stage1_*.log
   tail -100 logs/stage2_*.log
   ```
4. Monitor jobs:
   ```bash
   ./scripts/monitor_pipeline.sh --live
   squeue -u $USER
   ```

### Common Questions?
- **How do I customize parameters?** → Edit `config/rfd3_*.yaml`
- **How do I switch folding engines?** → Set `engine: "chai" | "alphafold" | "boltz"` in config
- **Can I resume interrupted runs?** → Yes! Use checkpoint system (automatic)
- **How do I parallelize across machines?** → Run different configs on different machines

## Support

For bugs, features, or documentation improvements:
1. Check existing documentation: [README.md](README.md), [QUICKSTART.md](QUICKSTART.md)
2. Review configuration examples in `config/`
3. Check log files: `logs/stage1_*.log`, `logs/stage2_*.log`
4. Verify SLURM job status: `squeue -j <job_id>`
5. Run diagnostics:
   ```bash
   nvidia-smi              # Check GPU
   conda env list          # Check environments
   python --version        # Check Python
   ```

---

## External Resources

- [RFDiffusion Documentation](https://github.com/RosettaCommons/foundry)
- [Chai Research](https://github.com/chai-research)
- [Boltz Prediction Docs](https://github.com/jwohlwend/boltz/blob/main/docs/prediction.md)
- [AlphaFold GitHub](https://github.com/google-deepmind/alphafold)
- [LigandMPNN](https://github.com/dauparas/LigandMPNN)

---

**Last Updated**: 2026-07-01
**Latest Features**:
- Multi-run analysis with `run_analysis.sh` (aggregates 5 parallel runs)
- Cross-approach comparison with `compare_approaches.sh`
- Job monitoring with `monitor_jobs.sh`
- Best design extraction with `extract_best_designs.sh`
- CSV exports and comprehensive visualization plots
- Per-run statistics and global ranking

**Documentation**:
- [QUICKSTART.md](QUICKSTART.md) — Installation & basic usage
- [COMPARISON_GUIDE.md](COMPARISON_GUIDE.md) — Approach comparison workflow
- [README.md](README.md) — Complete reference (this file)
