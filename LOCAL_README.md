# Local GPU Pipeline

Run the protein design pipeline on a single Linux machine with GPU (no SLURM required).

## Quick Start

### 1. Install Everything
```bash
bash install_local.sh
```

Or with custom directory:
```bash
bash install_local.sh --conda-env-dir ~/my-envs
```

**Time:** ~45-90 minutes (depending on internet speed)

### 2. Run Pipeline
```bash
bash run_local.sh --config config/rfd3_compact_3epi.yaml
```

**That's it!** Results save to `HA_MES_outputs/design_generation/`

---

## Options

### Installation Options

```bash
# Skip checkpoints (faster, ~15 min)
bash install_local.sh --skip-checkpoints

# Custom directory
bash install_local.sh --conda-env-dir ~/software/conda-envs

# Skip verification tests
bash install_local.sh --skip-verify
```

### Pipeline Options

```bash
# Stage 1 only (RFD3 + MPNN)
bash run_local.sh --config config/rfd3_compact_3epi.yaml --stage1-only

# Stage 2 only (Folding + Analysis)
bash run_local.sh --config config/rfd3_compact_3epi.yaml --stage2-only

# Specific GPU
bash run_local.sh --config config/rfd3_compact_3epi.yaml --gpu 1

# Rerun specific stage
bash run_local.sh --config config/rfd3_compact_3epi.yaml --force-rerun folding

# Show all options
bash run_local.sh --help
```

---

## Configuration

Edit YAML files in `config/` to customize:

```bash
# View available configs
ls config/

# Create your own
cp config/rfd3_compact_3epi.yaml config/my_design.yaml
nano config/my_design.yaml

# Run it
bash run_local.sh --config config/my_design.yaml
```

Key parameters to adjust:
- `rfd3.n_batches` - Number of RFD3 designs (increase for more diversity)
- `filters.max_backbone_rmsd` - Relax/tighten structure constraints
- `folding_engine.engine` - Switch between chai/boltz/alphafold

---

## Hardware Requirements

| Component | Min | Recommended |
|-----------|-----|-------------|
| GPU VRAM | 6GB | 8GB+ |
| GPU Type | Any NVIDIA | RTX 3070+ or A100 |
| CPU | 4 cores | 8+ cores |
| RAM | 16GB | 32GB+ |
| Disk | 50GB | 100GB+ |

**GPU Check:**
```bash
nvidia-smi
```

---

## Troubleshooting

### GPU Not Found
```bash
nvidia-smi              # Check if GPU detected
nvidia-smi -i 0         # Test GPU 0
```

### Out of Memory
```bash
# Reduce batch sizes in config
rfd3.n_batches: 2
rfd3.batch_size: 2
sequence_design.seqs_per_backbone: 2

# Or use GPU with more VRAM
bash run_local.sh --config config/rfd3_compact_3epi.yaml --gpu 1
```

### Installation Issues
```bash
# Check environments
conda env list

# Manually activate
conda activate ./conda-envs/rfd3_env
python -c "from foundry import rfd3; print('OK')"

# Reinstall
rm -rf conda-envs/
bash install_local.sh --skip-checkpoints
```

### Pipeline Fails
```bash
# Check logs
tail -50 logs/stage1_local_*.log
tail -50 logs/stage2_local_*.log

# Rerun single stage
bash run_local.sh --config config/rfd3_compact_3epi.yaml --stage2-only --force-rerun folding

# Verify GPU is available
nvidia-smi
```

---

## Output

Results are saved to:

```
HA_MES_outputs/design_generation/
├── rfd3_compact_3epi/
│   ├── output/           # Stage 1 outputs (backbones + sequences)
│   ├── folding_output/   # Folded structures (CIF files)
│   ├── plots/            # Analysis plots + metrics
│   │   ├── rfd3_compact_3epi_plddt_vs_ptm.png
│   │   ├── rfd3_compact_3epi_metrics_summary.json
│   │   └── top20_summary.json
│   └── top20/            # Best 20 designs
│       ├── 01_protein_modelX.cif
│       ├── 02_protein_modelY.cif
│       └── ...
```

### View Results
```bash
# Check plots
ls HA_MES_outputs/design_generation/*/plots/

# View metrics
cat HA_MES_outputs/design_generation/*/plots/*metrics*.json

# List top 20
ls HA_MES_outputs/design_generation/*/top20/

# Download structures
cp HA_MES_outputs/design_generation/*/top20/*.cif ~/Downloads/
```

---

## Advanced

### Different Configs

```bash
# Compact scaffold (fastest)
bash run_local.sh --config config/rfd3_compact_3epi.yaml

# Contiguous design
bash run_local.sh --config config/rfd3_contig_3epi.yaml

# Medium size
bash run_local.sh --config config/rfd3_medium_3epi.yaml

# Large scaffold (slowest)
bash run_local.sh --config config/rfd3_large_3epi.yaml

# Optimized variants (more diversity)
bash run_local.sh --config config/rfd3_compact_3epi_opt.yaml
```

### Monitor Progress

```bash
# In another terminal, watch GPU
watch -n 1 nvidia-smi

# Or check output growth
watch -n 5 'du -sh HA_MES_outputs/design_generation/*'

# Or tail logs
tail -f logs/stage2_local_*.log
```

### Parallel Runs (Multiple GPUs)

```bash
# Terminal 1: GPU 0
bash run_local.sh --config config/rfd3_compact_3epi.yaml --gpu 0

# Terminal 2: GPU 1 (different config)
bash run_local.sh --config config/rfd3_medium_3epi.yaml --gpu 1
```

---

## Environments

Installed in `conda-envs/`:
- `rfd3_env` - RFDiffusion + Foundry
- `ligandmpnn_env` - Sequence design
- `chai_env` - Structure prediction

Activate manually:
```bash
conda activate ./conda-envs/rfd3_env
```

---

## Citation

```bibtex
@article{lin2024diffusion,
  title={Diffusion-based protein design},
  author={Lin, Zhaoqiang and others},
  year={2024}
}

@article{dauparas2022proteinmpnn,
  title={ProteinMPNN: Decoding anytime},
  author={Dauparas, Justas and others},
  year={2022}
}
```

---

## Support

- Check `logs/` for error messages
- Read `README.md` for detailed documentation
- Examine `config/` examples for customization

**Last Updated:** 2026-06-26
