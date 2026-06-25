#!/usr/bin/env python3
"""
Structure prediction script for designed proteins.

Extracts protein sequences from PDB/CIF files and predicts structures
using a specified folding engine (Chai, AlphaFold, Boltz).
Supports ligand/cofactor SMILES specification for binding predictions.
"""

import os
import argparse
import logging
import sys
from pathlib import Path
from Bio.PDB import PDBParser, MMCIFParser, is_aa

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

THREE_TO_ONE = {
    'ALA': 'A', 'CYS': 'C', 'ASP': 'D', 'GLU': 'E', 'PHE': 'F',
    'GLY': 'G', 'HIS': 'H', 'ILE': 'I', 'LYS': 'K', 'LEU': 'L',
    'MET': 'M', 'ASN': 'N', 'PRO': 'P', 'GLN': 'Q', 'ARG': 'R',
    'SER': 'S', 'THR': 'T', 'VAL': 'V', 'TRP': 'W', 'TYR': 'Y'
}


def get_sequence(file_path, file_type, chain_id='A'):
    """Extract protein sequence from PDB or CIF file."""
    if file_type == 'cif':
        parser = MMCIFParser(QUIET=True)
    else:
        parser = PDBParser(QUIET=True)

    try:
        structure = parser.get_structure("mol", str(file_path))
        model = structure[0]
        if chain_id not in model:
            return None

        seq = "".join([THREE_TO_ONE.get(res.get_resname(), 'X')
                       for res in model[chain_id] if is_aa(res)])
        return seq
    except Exception as e:
        logger.error(f"Error reading {file_path}: {e}")
        return None


def create_fasta(seq, name, ligand_dict, out_path, engine='chai', msa_path=None):
    """
    Generate folding engine-compatible FASTA.

    For Boltz: Single-sequence mode (msa: empty)
      - Simple >protein format without MSA
    For others: uses >protein|<name> format with ligand support
    """
    with open(out_path, "w") as f:
        if engine == 'boltz':
            # Boltz single-sequence mode (msa: empty) - no MSA used
            f.write(f">protein\n{seq}\n")
        else:
            # Chai/AlphaFold format: >protein|<name>
            f.write(f">protein|{name}\n{seq}\n")
            for lig_name, smiles in ligand_dict.items():
                f.write(f">ligand|{lig_name}\n{smiles}\n")


def run_chai_inference(fasta_path, output_dir, recycles, timesteps, use_embeddings):
    """Run Chai1 structure prediction."""
    from chai_lab.chai1 import run_inference

    try:
        candidates = run_inference(
            fasta_file=fasta_path,
            output_dir=output_dir,
            num_trunk_recycles=recycles,
            num_diffn_timesteps=timesteps,
            seed=42,
            device="cuda:0",
            use_esm_embeddings=use_embeddings,
        )
        return True
    except Exception as e:
        logger.error(f"Chai inference failed: {e}")
        return False


def run_alphafold_inference(fasta_path, output_dir, model_preset="multimer",
                            max_template_date="2022-01-01",
                            alphafold_data_dir=None, use_gpu_relax=True):
    """
    Run AlphaFold2 structure prediction.

    Requires:
    - AlphaFold module loaded via HPC module system
    - ALPHAFOLD_DATA_DIR environment variable set
    - run_alphafold.py available in PATH

    Args:
        fasta_path: Path to FASTA file (protein + ligands)
        output_dir: Output directory for predictions
        model_preset: "monomer" or "multimer" (default: multimer)
        max_template_date: Template cutoff date (default: 2022-01-01)
        alphafold_data_dir: Path to AlphaFold database (uses env var if None)
        use_gpu_relax: Enable GPU relaxation (default: True)

    Returns:
        True if successful, False otherwise
    """
    import subprocess
    from pathlib import Path
    import os

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        # Set AlphaFold data directory if provided
        env = os.environ.copy()
        if alphafold_data_dir:
            env['ALPHAFOLD_DATA_DIR'] = alphafold_data_dir

        # Build command (matches cluster setup)
        cmd = [
            "run_alphafold.py",
            f"--fasta_paths={fasta_path}",
            f"--max_template_date={max_template_date}",
            f"--model_preset={model_preset}",
            f"--output_dir={output_dir}",
            f"--use_gpu_relax={use_gpu_relax}"
        ]

        logger.info(f"Running AlphaFold with command: {' '.join(cmd)}")

        # Execute
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)

        if result.returncode == 0:
            logger.info(f"AlphaFold prediction succeeded")
            return True
        else:
            logger.error(f"AlphaFold failed with code {result.returncode}")
            logger.error(f"STDOUT: {result.stdout}")
            logger.error(f"STDERR: {result.stderr}")
            return False

    except Exception as e:
        logger.error(f"AlphaFold inference error: {e}")
        return False


def run_boltz_inference(fasta_path, output_dir, num_recycles=4):
    """
    Run Boltz structure prediction in single-sequence mode (msa: empty).

    Requires:
    - Boltz conda environment activated
    - boltz command available in PATH

    Args:
        fasta_path: Path to FASTA file (protein sequences, no MSA)
        output_dir: Output directory for predictions
        num_recycles: Number of recycles (not used by Boltz, kept for API compatibility)

    Returns:
        True if successful, False otherwise
    """
    import subprocess
    from pathlib import Path

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        # Run Boltz prediction in single-sequence mode (msa: empty)
        cmd = [
            "boltz",
            "predict",
            str(fasta_path),
            "--output_dir",
            str(output_dir)
        ]

        logger.info(f"Running Boltz (single-sequence mode, msa: empty)")
        logger.info(f"Command: {' '.join(cmd)}")

        # Execute
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode == 0:
            logger.info(f"Boltz prediction succeeded")
            return True
        else:
            logger.error(f"Boltz failed with code {result.returncode}")
            logger.error(f"STDOUT: {result.stdout}")
            logger.error(f"STDERR: {result.stderr}")
            return False

    except Exception as e:
        logger.error(f"Boltz inference error: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Structure prediction for designed proteins"
    )
    parser.add_argument("--input_dir", required=True, help="Path to PDB/CIF files")
    parser.add_argument("--output_dir", required=True, help="Output directory")
    parser.add_argument("--format", choices=['pdb', 'cif'], default='pdb',
                       help="Input file format")
    parser.add_argument("--engine", choices=['chai', 'alphafold', 'boltz'], default='chai',
                       help="Folding engine to use")
    parser.add_argument("--smiles", action="append", help="SMILES strings (format: 'NAME SMILES')",
                       default=[])
    parser.add_argument("--recycles", type=int, default=3,
                       help="Number of trunk recycles (Chai)")
    parser.add_argument("--timesteps", type=int, default=200,
                       help="Diffusion timesteps (Chai)")
    parser.add_argument("--use_embeddings", type=bool, default=True,
                       help="Use ESM embeddings (Chai)")

    args = parser.parse_args()

    input_path = Path(args.input_dir)
    output_base = Path(args.output_dir)
    output_base.mkdir(parents=True, exist_ok=True)

    extension = f"*.{args.format}"
    files = list(input_path.glob(extension))

    if not files:
        logger.error(f"No {args.format} files found in {input_path}")
        sys.exit(1)

    ligand_dict = {}
    if args.smiles:
        for entry in args.smiles:
            parts = entry.split(maxsplit=1)
            if len(parts) == 2:
                name, smiles = parts
                ligand_dict[name] = smiles
            else:
                logger.warning(f"Invalid SMILES format: {entry}")

    success_count = 0
    failed_count = 0

    for f_path in files:
        protein_name = f_path.stem
        sequence = get_sequence(f_path, args.format)
        if not sequence:
            logger.warning(f"Could not extract sequence from {f_path}")
            failed_count += 1
            continue

        work_dir = output_base / protein_name
        fasta_dir = output_base / "fastas"
        work_dir.mkdir(exist_ok=True, parents=True)
        fasta_dir.mkdir(exist_ok=True, parents=True)

        fasta_path = fasta_dir / f"{protein_name}.fasta"
        create_fasta(sequence, protein_name, ligand_dict, fasta_path, engine=args.engine)

        logger.info(f"Predicting structure for {protein_name} using {args.engine}")

        success = False
        if args.engine == 'chai':
            success = run_chai_inference(fasta_path, work_dir, args.recycles,
                                        args.timesteps, args.use_embeddings)
        elif args.engine == 'alphafold':
            success = run_alphafold_inference(fasta_path, work_dir)
        elif args.engine == 'boltz':
            success = run_boltz_inference(fasta_path, work_dir, args.recycles)

        if success:
            success_count += 1
        else:
            failed_count += 1

    logger.info(f"✓ Prediction complete: {success_count} succeeded, {failed_count} failed")

    if failed_count > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
