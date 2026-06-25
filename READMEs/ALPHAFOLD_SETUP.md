# AlphaFold Setup Guide

Quick reference for using AlphaFold2 with the design pipeline on your cluster.

## Quick Start

### 1. Create AlphaFold Config

```bash
cp config/example_design.yaml config/alphafold_design.yaml
```

The example config already has AlphaFold as default engine. Just verify/update paths if needed.

### 2. Verify Configuration

```bash
python3 scripts/config_utils.py config/alphafold_design.yaml
```

Should output:
```
✓ Configuration loaded successfully
✓ Folding engine: alphafold
✓ Work directory: <your_path>
```

### 3. Submit Pipeline

```bash
./submit_design_pipeline.sh --config config/alphafold_design.yaml
```

This will:
1. Run Stage 1: RFDiffusion + MPNN
2. Automatically trigger Stage 2: AlphaFold + Analysis

Or run Stage 2 only (if you already have MPNN output):

```bash
./submit_design_pipeline.sh --config config/alphafold_design.yaml --stage2-only
```

### 4. Monitor

```bash
squeue -j <job_id>
tail -f logs/stage2_*.log
```

## Configuration Parameters

```yaml
folding_engine:
  engine: "alphafold"
  
  alphafold:
    hpc_module: "AlphaFold"                    # Module name to load
    data_dir: "/software/databases/alphafold"  # ALPHAFOLD_DATA_DIR
    model_preset: "multimer"                   # "monomer" or "multimer"
    max_template_date: "2022-01-01"            # Template cutoff date
```

### Parameters Explained

| Parameter | Default | Options | Notes |
|-----------|---------|---------|-------|
| `hpc_module` | `AlphaFold` | Module name on your cluster | Used with `module load` |
| `data_dir` | None | `/software/databases/alphafold` | Sets ALPHAFOLD_DATA_DIR env var |
| `model_preset` | `multimer` | `monomer`, `multimer` | Use multimer for ligand-protein |
| `max_template_date` | `2022-01-01` | Any date | Template structures before this date |

## How It Works

Behind the scenes, the pipeline does this:

```bash
# 1. Load module
module load AlphaFold

# 2. Set environment
export ALPHAFOLD_DATA_DIR=/software/databases/alphafold

# 3. Run prediction (for each designed sequence)
run_alphafold.py \
    --fasta_paths=sequence.fasta \
    --max_template_date=2022-01-01 \
    --model_preset=multimer \
    --output_dir=output/ \
    --use_gpu_relax=True

# 4. Unload module
module unload AlphaFold
```

The pipeline automates all this for you across all designed sequences.

## Output Structure

After AlphaFold stage completes:

```
work_directory/design_generation/subdirectory/
├── output/
│   └── folding_output/
│       ├── protein_name_1/
│       │   ├── protein_name_1_0.cif       ← Predicted structure
│       │   ├── protein_name_1_idx_0.npz   ← Confidence scores
│       │   └── ... (other AF output files)
│       └── protein_name_2/
│           └── ...
├── results/
│   ├── scores.csv                         ← Analysis results
│   ├── designs/                           ← All designs
│   └── ... (filtered designs, etc)
```

## Common Issues & Solutions

### Issue: Module not found
```
ERROR: module load AlphaFold
```

**Solution**: Check available modules
```bash
module avail AlphaFold
# Adjust hpc_module in config if name differs
```

### Issue: ALPHAFOLD_DATA_DIR not found
```
ERROR: cannot find database files
```

**Solution**: Verify data directory path
```bash
ls -la /software/databases/alphafold
# Update data_dir in config if path differs
```

### Issue: CIF output not generated
```
ERROR: No CIF files found in output
```

**Check**:
1. AlphaFold actually ran: `ls -la output_dir/*/`
2. Output format: AF should create `*_0.cif` files
3. Run AlphaFold manually to test:
   ```bash
   module load AlphaFold
   export ALPHAFOLD_DATA_DIR=/software/databases/alphafold
   run_alphafold.py --fasta_paths=test.fasta --output_dir=test_out/
   ```

### Issue: Memory/GPU errors
```
ERROR: CUDA out of memory or GPU not available
```

**Solution**: Increase resources in job submission
```bash
./submit_design_pipeline.sh --config config/alphafold_design.yaml \
    --stage2-only \
    --gpus 2 \
    --mem 100G
```

## SLURM Job Resources

Typical resource requirements for Stage 2 (AlphaFold):

```bash
./submit_design_pipeline.sh --config config/alphafold_design.yaml \
    --partition gpu \
    --cpus 8 \
    --mem 80G \
    --gpus 1 \
    --time 48:00:00
```

Adjust based on:
- Number of designs: more designs = longer time
- Protein size: larger proteins = more memory
- GPU type: newer GPUs = faster

## Monomer vs Multimer

### Use `monomer`
- Single protein chains only
- Faster prediction
- Lower memory requirement

```yaml
alphafold:
  model_preset: "monomer"
```

### Use `multimer`
- Protein-protein complexes
- Protein-ligand complexes (recommended for design pipeline)
- Slower but better for interactions
- Higher memory requirement

```yaml
alphafold:
  model_preset: "multimer"
```

The design pipeline uses **multimer by default** (recommended for enzyme design with cofactors).

## Advanced: Using Different Templates

AlphaFold can use structure templates to guide predictions:

```yaml
alphafold:
  max_template_date: "2021-01-01"   # Only use older structures
  # or
  max_template_date: "2025-01-01"   # Use newest available
```

Templates help when designing similar to known structures, but limit to pre-existing templates.

## Monitoring AlphaFold Progress

During Stage 2 execution:

```bash
# Watch logs in real-time
tail -f logs/stage2_*.log

# Check output directory growth
watch -n 5 'ls -R work/*/design_generation/*/output/folding_output/ | wc -l'

# Check GPU usage (if on same node)
nvidia-smi -l 2
```

## Testing Before Full Submission

### 1. Dry-run (no actual submission)
```bash
./submit_design_pipeline.sh --config config/alphafold_design.yaml --dry-run
```

Prints job scripts without submitting. Check the Stage 2 script!

### 2. Test with Stage 2 only
If you have existing MPNN output:
```bash
./submit_design_pipeline.sh --config config/alphafold_design.yaml --stage2-only
```

### 3. Manual test (debug)
```bash
# Load module
module load AlphaFold

# Set environment
export ALPHAFOLD_DATA_DIR=/software/databases/alphafold

# Test with simple FASTA
echo -e ">protein|test\nMETALLASL\n>ligand|VO4\n[O-][V](=O)([O-])[O-]" > test.fasta

# Run manually
python3 scripts/design_refolding.py \
    --input_dir . \
    --output_dir test_af_output/ \
    --engine alphafold \
    --model_preset multimer

# Check output
ls -la test_af_output/
```

## Reference: Complete AlphaFold Config

```yaml
folding_engine:
  engine: "alphafold"
  
  alphafold:
    hpc_module: "AlphaFold"
    data_dir: "/software/databases/alphafold"
    model_preset: "multimer"
    max_template_date: "2022-01-01"
```

## Next: Add More Analyses

After AlphaFold predictions, the pipeline runs:
1. Analysis/filtering (`design_helper_script.py`)
2. Extracts metrics: pLDDT, pTM, RMSD, SASA
3. Filters based on thresholds from config
4. Outputs best designs to `passed_designs/`

Adjust filtering thresholds in config:

```yaml
filters:
  min_plddt_final: 80.0
  min_motif_plddt: 85.0
  max_backbone_rmsd: 3.0
```

## Support

For issues:
1. Check `logs/stage2_*.log` for errors
2. Verify AlphaFold works manually
3. See README.md Troubleshooting section
4. Check ADDING_FOLDING_ENGINES.md for technical details
