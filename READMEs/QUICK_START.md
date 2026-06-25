# Quick Start: Pre-filled Configuration

The `config/example_design.yaml` is now **pre-filled with your actual cluster setup**. You only need to make 3 small updates before running.

## What's Already Configured

✅ **RFD3 Settings:**
- Checkpoint: `/work2/fd55fani-genie3/rf3/foundry/checkpoints/rfd3_latest.ckpt`
- Foundry: `/work2/fd55fani-genie3/rfd3_new/foundry/foundry_new`
- Batch size: 4, Batches: 5

✅ **Sequence Design (MPNN):**
- Model: `protein` (your setting)
- Environment: `/work2/fd55fani-conda/ligandmpnn_env`
- LigandMPNN: `/work2/fd55fani-genie3/LigandMPNN`
- Temperature: 0.1, Seqs per backbone: 5

✅ **Structure Prediction (Chai):**
- Environment: `/work2/fd55fani-conda/chai_env`
- Recycles: 3, Timesteps: 200

✅ **Sequence Optimization:**
- Enabled: `true`
- Temperature: 0.2, Seqs: 3

✅ **Filtering Thresholds:**
- min_plddt_initial: 75%
- min_plddt_final: 80%
- min_motif_plddt: 75%
- max_backbone_rmsd: 2Å
- max_motif_rmsd: 1.5Å

## What You MUST Update

### 1. RFD3 Settings JSON File

Edit `config/example_design.yaml` line 8:

```yaml
rfd3:
  settings_json: "/work2/fd55fani-genie3/paul-pipe/jsons/YOUR_DESIGN_NAME.json"
```

Replace `YOUR_DESIGN_NAME` with your actual RFD3 settings JSON file.

### 2. Template PDB Directory

Edit `config/example_design.yaml` line 87:

```yaml
fixed_residues:
  template_pdb_dir: "/path/to/your/template/pdbs"
```

Point to the directory containing your input PDB structures. If using RFDiffusion-generated backbones, leave empty or point to where they'll be generated.

### 3. Subdirectory Name (Per Run)

Edit `config/example_design.yaml` line 94:

```yaml
output:
  subdirectory: "clara_run_001"
```

Change this per run:
- First run: `clara_run_001`
- Second run: `clara_run_002`
- Your design: `your_design_name`

## Quick Workflow

### Step 1: Update Config File

```bash
# Edit the three required fields above
nano config/example_design.yaml
```

Or create a new one with your actual paths:

```bash
cp config/example_design.yaml config/my_design.yaml
# Edit config/my_design.yaml
```

### Step 2: Verify Configuration

```bash
python3 scripts/config_utils.py config/example_design.yaml
```

Should output:
```
✓ Configuration loaded successfully
✓ Folding engine: chai
```

### Step 3: Submit Pipeline

```bash
./submit_design_pipeline.sh --config config/example_design.yaml
```

This will:
1. Run RFDiffusion (Stage 1)
2. Design sequences with MPNN (Stage 1)
3. Predict structures with Chai (Stage 2) - automatically starts when Stage 1 completes
4. Optimize sequences (Stage 2) - since you have it enabled
5. Final analysis and filtering

### Step 4: Monitor Progress

```bash
# Check job status
squeue -j <job_id>

# Watch logs in real-time
tail -f logs/stage1_*.log
tail -f logs/stage2_*.log

# After completion
ls -la work/*/design_generation/clara_run_001/results/
```

## Alternative: Run Stages Separately

If you prefer more control:

```bash
# Stage 1 only (backbone generation + sequence design)
./submit_design_pipeline.sh --config config/example_design.yaml --stage1-only

# Later: Stage 2 only (folding + analysis)
./submit_design_pipeline.sh --config config/example_design.yaml --stage2-only
```

## Testing Without Submitting

Preview the job script without submitting:

```bash
./submit_design_pipeline.sh --config config/example_design.yaml --dry-run
```

## Comparison: Old vs New

| Aspect | Old Setup | New Setup |
|--------|-----------|----------|
| Configuration | Command-line arguments | Single YAML file |
| Job structure | Monolithic (all stages) | Two separate jobs |
| Checkpoints | None | 5-level system |
| Recovery | Full restart | Resume from any stage |
| Folding engines | Chai only | Chai/AlphaFold/Boltz ready |
| Multiple runs | Array jobs | Direct config swap |

## Common Tasks

### Change Filtering Thresholds

```yaml
filters:
  min_plddt_final: 85.0      # Stricter
  max_backbone_rmsd: 1.5     # Stricter
  max_motif_rmsd: 1.0        # Stricter
```

### Switch to AlphaFold

Change one line in config:

```yaml
folding_engine:
  engine: "alphafold"  # Instead of "chai"
```

### Disable Sequence Optimization

```yaml
sequence_optimization:
  enabled: false  # Instead of true
```

### Change MPNN Parameters

```yaml
sequence_design:
  model_type: "ligand"        # Instead of "protein"
  temperature: 0.2            # More diverse
  seqs_per_backbone: 10       # More sequences
```

## File Locations

Key paths from your setup (already configured):

```
Checkpoints:
  /work2/fd55fani-genie3/rf3/foundry/checkpoints/rfd3_latest.ckpt

Environments:
  /work2/fd55fani-conda/chai_env
  /work2/fd55fani-conda/ligandmpnn_env

Tools:
  /work2/fd55fani-genie3/LigandMPNN
  /work2/fd55fani-genie3/rfd3_new/foundry/foundry_new

Inputs:
  /work2/fd55fani-genie3/paul-pipe/jsons/

Outputs:
  /work2/fd55fani-genie3/HA_MES_outputs/
```

## Troubleshooting

### Issue: "Config file not found"
```bash
python3 scripts/config_utils.py config/example_design.yaml
```

### Issue: "RFD3 settings JSON not found"
Check the path in `rfd3.settings_json` points to actual file:
```bash
ls -la /work2/fd55fani-genie3/paul-pipe/jsons/YOUR_FILE.json
```

### Issue: "Template PDB directory not found"
Check the path in `fixed_residues.template_pdb_dir`:
```bash
ls -la /path/to/your/templates/
```

### Issue: Jobs not starting
Check logs:
```bash
cat logs/stage1_*.log
cat logs/stage2_*.log
```

## Support

- For general usage: See `README.md`
- For technical details: See `IMPLEMENTATION_SUMMARY.md`
- For AlphaFold: See `ALPHAFOLD_SETUP.md`
- For adding engines: See `ADDING_FOLDING_ENGINES.md`

## Summary

You're ready to go! The config has your paths and settings. Just update 3 fields and run:

```bash
nano config/example_design.yaml     # Update 3 fields
./submit_design_pipeline.sh --config config/example_design.yaml
```

That's it! 🚀
