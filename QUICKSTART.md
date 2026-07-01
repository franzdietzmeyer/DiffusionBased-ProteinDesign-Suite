# Quick Start Guide

## One-Command Installation

Install everything automatically:

```bash
bash install_all.sh
```

The script will:
✅ Check prerequisites (Python, Conda, GPU, Git)
✅ Clone all repositories (Foundry, LigandMPNN)
✅ Create all conda environments (RFD3, MPNN, Chai, Boltz)
✅ Download model checkpoints
✅ Verify installations
✅ Print final setup summary

### Installation Time
- **Fast (no checkpoints):** ~15-20 min
- **Full (with checkpoints):** ~45-90 min depending on internet speed

---

## Installation Options

### Skip Checkpoint Download (faster)
```bash
bash install_all.sh --skip-checkpoints
# Download checkpoints later:
# foundry install rfd3 --checkpoint-dir /path/to/checkpoints
```

### Skip Verification Tests
```bash
bash install_all.sh --skip-verify
```

### Custom Directories

**Local conda-envs directory (relative path):**
```bash
bash install_all.sh --conda-env-dir conda-envs/
```

**Absolute paths:**
```bash
bash install_all.sh \
  --conda-env-dir ~/my-conda-envs \
  --rfd3-dir ~/software/foundry \
  --mpnn-dir ~/software/LigandMPNN \
  --checkpoint-dir ~/models/rfd3-checkpoints
```

**Mix and match:**
```bash
bash install_all.sh \
  --conda-env-dir conda-envs/ \
  --checkpoint-dir ~/large-disk/checkpoints
```

### Show All Options
```bash
bash install_all.sh --help
```

---

## After Installation

### 1. Test the Pipeline
```bash
./submit_design_pipeline.sh --config config/rfd3_compact_3epi.yaml
```

### 2. Monitor Jobs
```bash
./scripts/monitor_pipeline.sh --live
```

### 3. View Results
```bash
ls -la /work2/fd55fani-genie3/pipeline_scaffolding/HA_MES_outputs/design_generation/
```

---

## Troubleshooting

### "Conda not found"
Install Miniconda: https://docs.conda.io/projects/miniconda/en/latest/

### "CUDA not found"
Install NVIDIA drivers: https://www.nvidia.com/Download/driverDetails.aspx

### "Permission denied"
Make script executable:
```bash
chmod +x install_all.sh
```

### Installation Interrupted?
The script is **resumable** - just run it again. It will:
- Skip already cloned repositories
- Skip already created environments
- Continue from where it left off

### Manual Checkpoint Download (if script fails)
```bash
# Activate RFD3 environment
conda activate /work2/fd55fani-conda/rfd3_env

# Download checkpoints
foundry install rfd3 --checkpoint-dir ./checkpoints

# Deactivate when done
conda deactivate
```

---

## Environment Locations

After installation, conda environments are at:
```
/work2/fd55fani-conda/
├── rfd3_env/          (RFDiffusion + Foundry)
├── ligandmpnn_env/    (Sequence Design)
├── chai_env/          (Structure Prediction)
└── boltz203/          (Alternative Structure Prediction)
```

Activate environments:
```bash
conda activate /work2/fd55fani-conda/rfd3_env
conda activate /work2/fd55fani-conda/ligandmpnn_env
conda activate /work2/fd55fani-conda/chai_env
conda activate /work2/fd55fani-conda/boltz203
```

---

## Configuration Files

After installation, edit config files in `./config/`:
```
config/
├── rfd3_compact_3epi.yaml      (Small scaffold)
├── rfd3_contig_3epi.yaml       (Contiguous design)
├── rfd3_medium_3epi.yaml       (Medium size)
├── rfd3_large_3epi.yaml        (Large scaffold)
├── rfd3_compact_3epi_opt.yaml  (Optimized for diverse design)
└── ... more optimized configs
```

---

## Next Steps

1. **Read the README:** `cat README.md`
2. **Understand the pipeline:** View `docs/` directory
3. **Run your first design:** `./submit_design_pipeline.sh --config config/rfd3_compact_3epi.yaml`
4. **Check results:** `./scripts/monitor_pipeline.sh --live`

---

## Support

For issues or questions:
- Check `README.md` for detailed documentation
- Review `logs/` directory for error messages
- See `config/rfd3_compact_3epi.yaml` for all available options

Happy designing! 🚀
