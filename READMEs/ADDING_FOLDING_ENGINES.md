# Adding New Folding Engines

Guide for implementing AlphaFold, Boltz, or other folding engines in the design pipeline.

## Overview

The pipeline uses a plugin architecture for folding engines. Currently **Chai1** is fully implemented; **AlphaFold** and **Boltz** have placeholder infrastructure ready.

Adding a new engine requires changes to **3 files**:
1. `scripts/design_refolding.py` - Engine implementation
2. `config/design_pipeline.yaml` - Configuration parameters
3. `scripts/design_stage2_folding.sh` - Engine dispatch logic

## Step-by-Step: Adding AlphaFold as Example

### Step 1: Add to Configuration (`config/design_pipeline.yaml`)

In the `folding_engine` section, uncomment and populate AlphaFold parameters:

```yaml
folding_engine:
  engine: "alphafold"  # Change this to enable AlphaFold

  # Existing Chai config
  chai:
    conda_env: "..."

  # AlphaFold Configuration
  alphafold:
    hpc_module: "alphafold/2.3"      # HPC module to load (if using modules)
    conda_env: "/path/to/af_env"     # OR use conda env instead of module
    db_preset: "full_dbs"            # "full_dbs" or "reduced_dbs"
    max_template_date: "2021-11-01"  # Optional: for AF2 only
    num_multimer_predictions_per_model: 5  # For multimers
```

### Step 2: Implement Engine in `scripts/design_refolding.py`

Replace the placeholder `run_alphafold_inference()` function:

```python
def run_alphafold_inference(fasta_path, output_dir, db_preset="full_dbs", 
                            hpc_module=None, conda_env=None):
    """Run AlphaFold2 structure prediction."""
    import subprocess
    from pathlib import Path
    
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        # Option 1: Using HPC module
        if hpc_module:
            cmd = f"module load {hpc_module} && "
        else:
            cmd = f"source {conda_env}/bin/activate && "
        
        # AlphaFold command
        cmd += f"python /path/to/run_alphafold.py "
        cmd += f"--fasta_paths={fasta_path} "
        cmd += f"--output_dir={output_dir} "
        cmd += f"--db_preset={db_preset} "
        cmd += f"--max_template_date=2021-11-01 "
        cmd += f"--use_gpu_relax=true"
        
        # Execute
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info(f"AlphaFold prediction succeeded for {fasta_path}")
            return True
        else:
            logger.error(f"AlphaFold failed: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"AlphaFold inference error: {e}")
        return False
```

### Step 3: Update Engine Dispatch in `scripts/design_stage2_folding.sh`

In the "Structure Prediction" section, add AlphaFold handling:

```bash
if [[ "$FOLDING_ENGINE" == "alphafold" ]]; then
    # Load HPC module or activate conda env
    if [[ -n "$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alphafold_hpc_module', ''))")" ]]; then
        AF_MODULE=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['alphafold_hpc_module'])")
        module load $AF_MODULE
    else
        AF_ENV=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alphafold_conda_env', ''))")
        source "$AF_ENV/bin/activate"
    fi
    
    # Run AlphaFold
    "$AF_ENV/bin/python" "$SCRIPT_DIR/design_refolding.py" \
        --input_dir "$MPNN_BACKBONES" \
        --output_dir "$FOLDING_OUTPUT" \
        --engine alphafold
    
    deactivate
```

### Step 4: Test

Create a test configuration:

```bash
cp config/example_design.yaml config/test_alphafold.yaml
# Edit to set: folding_engine.engine = "alphafold"
# Edit to add AlphaFold paths

# Dry run (preview job script)
./submit_design_pipeline.sh --config config/test_alphafold.yaml --dry-run

# Or run Stage 2 only with an existing Stage 1 output
./submit_design_pipeline.sh --config config/test_alphafold.yaml --stage2-only
```

---

## Detailed Implementation Template

Here's a complete template for any new folding engine:

### 1. Configuration Section (YAML)

```yaml
folding_engine:
  engine: "new_engine"
  
  new_engine:
    # Common parameters
    conda_env: "/path/to/env"        # OR hpc_module
    hpc_module: "module_name"
    
    # Engine-specific parameters
    param1: value1
    param2: value2
    param3: value3
```

### 2. Python Implementation Template

```python
def run_new_engine_inference(fasta_path, output_dir, **kwargs):
    """
    Run new folding engine structure prediction.
    
    Args:
        fasta_path: Path to FASTA file with protein and ligands
        output_dir: Directory to save predictions
        **kwargs: Engine-specific parameters (param1, param2, etc.)
    
    Returns:
        True if successful, False otherwise
    """
    from pathlib import Path
    import subprocess
    
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        # Activate environment
        env_setup = ""
        if kwargs.get('hpc_module'):
            env_setup = f"module load {kwargs['hpc_module']} && "
        elif kwargs.get('conda_env'):
            env_setup = f"source {kwargs['conda_env']}/bin/activate && "
        
        # Build command
        cmd = env_setup
        cmd += f"python /path/to/engine_script.py "
        cmd += f"--input {fasta_path} "
        cmd += f"--output {output_dir} "
        
        # Add engine-specific parameters
        for key, value in kwargs.items():
            if key not in ['hpc_module', 'conda_env']:
                cmd += f"--{key}={value} "
        
        # Execute
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info(f"New engine prediction succeeded")
            return True
        else:
            logger.error(f"New engine failed: {result.stderr}")
            return False
            
    except Exception as e:
        logger.error(f"New engine error: {e}")
        return False
```

### 3. Bash Dispatch Template

```bash
elif [[ "$FOLDING_ENGINE" == "new_engine" ]]; then
    # Extract engine-specific config
    NEW_ENGINE_ENV=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('new_engine_conda_env', ''))")
    NEW_ENGINE_PARAM1=$(echo "$CONFIG_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('new_engine_param1', ''))")
    
    # Activate environment
    if [[ -n "$NEW_ENGINE_ENV" ]]; then
        source "$NEW_ENGINE_ENV/bin/activate"
    fi
    
    # Run prediction
    "$CHAI_ENV/bin/python" "$SCRIPT_DIR/design_refolding.py" \
        --input_dir "$MPNN_BACKBONES" \
        --output_dir "$FOLDING_OUTPUT" \
        --engine new_engine \
        --param1 "$NEW_ENGINE_PARAM1"
    
    deactivate
fi
```

---

## Key Implementation Considerations

### Environment Management

**Option A: Conda Environment**
```python
source /path/to/env/bin/activate
python script.py ...
deactivate
```

**Option B: HPC Module**
```bash
module load module_name/version
python script.py ...
module unload module_name
```

**Option C: Direct (if in PATH)**
```bash
python script.py ...
```

### Input Format

All engines receive a FASTA file with format:
```
>protein|protein_name
MKTAYLRR...SQRRK
>ligand|ligand_name
SMILES_STRING
```

**Important**: Parse this format in your implementation:
```python
with open(fasta_path) as f:
    lines = f.readlines()
    protein_seq = None
    ligands = {}
    
    for i, line in enumerate(lines):
        if line.startswith('>protein|'):
            protein_name = line.split('|')[1].strip()
            protein_seq = lines[i+1].strip()
        elif line.startswith('>ligand|'):
            ligand_name = line.split('|')[1].strip()
            smiles = lines[i+1].strip()
            ligands[ligand_name] = smiles
```

### Output Format

Engine must produce:
- `output_dir/[protein_name]/[protein_name]_0.cif` - Structure file (CIF format)
- `output_dir/[protein_name]/[protein_name]_idx_0.npz` - Confidence metrics:
  ```python
  np.savez(npz_file,
      aggregate_score=float,  # 0-1 confidence
      ptm=float,             # Predicted TM-score
      iptm=float)            # Interface TM (if protein complex)
  ```

The analysis step in Stage 2 depends on these outputs.

---

## Examples: AlphaFold vs Boltz vs Chai

### AlphaFold2

**Config:**
```yaml
alphafold:
  hpc_module: "alphafold/2.3"
  db_preset: "full_dbs"
```

**Key differences:**
- Uses HPC module (typically)
- Slower but more accurate for monomers
- Requires large database
- Output: `pdb` files (need conversion to CIF)

**Implementation note**: Convert PDB to CIF:
```python
import gemmi
struct = gemmi.read_structure('structure.pdb')
struct.write_cif('structure.cif')
```

### Boltz (Beta/Future)

**Config:**
```yaml
boltz:
  conda_env: "/path/to/boltz_env"
  num_recycles: 4
  bf16: true
```

**Key differences:**
- Requires conda environment
- Potentially faster than AF2
- Newer model architecture

### Chai1 (Current)

**Config:**
```yaml
chai:
  conda_env: "/path/to/chai_env"
  recycles: 3
  timesteps: 200
```

**Key differences:**
- Dedicated conda environment
- Supports ligand binding
- Already integrated

---

## Checklist for New Engine

- [ ] Create implementation function in `design_refolding.py`
- [ ] Add config section to `config/design_pipeline.yaml`
- [ ] Add config parameters to `config_utils.py` validation (if strict mode)
- [ ] Add dispatch logic to `design_stage2_folding.sh`
- [ ] Verify FASTA input format compatibility
- [ ] Verify CIF/NPZ output format
- [ ] Test with `--dry-run` first
- [ ] Test with single design (--stage2-only)
- [ ] Test full pipeline with --force-rerun
- [ ] Document engine-specific parameters in README.md

---

## Common Pitfalls

### ❌ Wrong output format
Output must be `.cif` files (not `.pdb`). The analysis step expects CIF format.

**Fix**: Convert PDB to CIF if needed
```python
import gemmi
struct = gemmi.read_structure('pred.pdb')
struct.write_cif('pred.cif')
```

### ❌ Missing confidence scores
Analysis step needs `*_idx_0.npz` with `aggregate_score`, `ptm`, `iptm`.

**Fix**: Always create NPZ with required fields
```python
np.savez(npz_file,
    aggregate_score=confidence,
    ptm=tm_score,
    iptm=interface_tm)
```

### ❌ Wrong FASTA parsing
Engine receives FASTA with both protein and ligands. Must parse correctly.

**Fix**: Check for both `>protein|` and `>ligand|` markers

### ❌ Environment not activated
Conda/module environment must be active for Python to find packages.

**Fix**: Source env in bash before calling Python script

---

## Testing Your Implementation

### 1. Validate Configuration

```bash
python3 scripts/config_utils.py config/my_new_engine.yaml
```

### 2. Dry Run (Preview Scripts)

```bash
./submit_design_pipeline.sh --config config/my_new_engine.yaml \
    --stage2-only --dry-run
```

### 3. Test with Single Design

```bash
# Run Stage 1 first (or use existing output)
./submit_design_pipeline.sh --config config/my_new_engine.yaml --stage1-only

# Then run Stage 2 with new engine
./submit_design_pipeline.sh --config config/my_new_engine.yaml --stage2-only
```

### 4. Check Output

```bash
ls -la work/design_generation/[subdir]/output/folding_output/
# Should see: [protein_name]_0.cif and [protein_name]_idx_0.npz
```

### 5. Verify Analysis

```bash
cat work/design_generation/[subdir]/results/scores.csv
# Should have: pLDDT, pTM, rmsd columns populated
```

---

## Quick Reference

| File | Change | Purpose |
|------|--------|---------|
| `config/design_pipeline.yaml` | Add `engine: "new_engine"` section with parameters | Configuration template |
| `scripts/design_refolding.py` | Implement `run_new_engine_inference()` | Engine execution logic |
| `scripts/design_stage2_folding.sh` | Add `elif` block for new engine | Job script dispatch |
| `README.md` | Add engine to "Folding Engine Support" | User documentation |

---

## Support & Debugging

If your engine implementation isn't working:

1. **Check logs**: `tail -f logs/stage2_*.log`
2. **Test manually**: Run engine command directly
3. **Verify output**: Check CIF and NPZ files exist
4. **Validate config**: `python3 scripts/config_utils.py config/your_engine.yaml`
5. **Use --dry-run**: Preview job script before submission

Good luck! The infrastructure is ready to support multiple folding engines seamlessly.
