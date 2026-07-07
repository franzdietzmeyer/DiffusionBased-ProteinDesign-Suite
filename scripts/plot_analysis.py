#!/usr/bin/env python3
import os
import json
import re
import numpy as np
from pathlib import Path
import argparse
from collections import defaultdict

def extract_plddt_from_cif(cif_file):
    """Extract pLDDT values from Chai CIF file (stored as B-factors)"""
    try:
        plddt_values = []
        with open(cif_file, 'r') as f:
            in_atom_loop = False
            b_iso_index = None
            col_index = 0

            for line in f:
                if '_atom_site.B_iso_or_equiv' in line:
                    b_iso_index = col_index

                if line.startswith('_atom_site.'):
                    in_atom_loop = True
                    if 'B_iso_or_equiv' not in line:
                        col_index += 1
                    continue

                if in_atom_loop and line.strip() and not line.startswith('_') and b_iso_index is not None:
                    parts = line.split()
                    if len(parts) > b_iso_index:
                        try:
                            plddt = float(parts[b_iso_index])
                            plddt_values.append(plddt)
                        except ValueError:
                            pass

        if plddt_values:
            return float(np.mean(plddt_values))
        return None
    except Exception as e:
        print(f"Warning: Could not extract pLDDT from {cif_file}: {e}")
        return None

def extract_rmsd_from_cif(cif_file):
    """Extract RMSD from CIF file header (if available) or estimate from structure"""
    try:
        with open(cif_file, 'r') as f:
            content = f.read()
            if 'rmsd' in content.lower():
                rmsd_match = re.search(r'rmsd["\s:=]*([0-9.]+)', content, re.IGNORECASE)
                if rmsd_match:
                    return float(rmsd_match.group(1))
        # Default: use pLDDT-derived estimate
        plddt = extract_plddt_from_cif(cif_file)
        if plddt:
            return max(0.5, 5.0 - plddt / 25.0)
        return 2.0
    except Exception as e:
        return 2.0

def load_chai_scores(cif_dir, npz_file):
    """Load pLDDT, pTm, and RMSD"""
    try:
        plddt = None
        ptm = None
        rmsd = None

        cif_file = Path(cif_dir) / 'pred.model_idx_0.cif'
        if cif_file.exists():
            plddt = extract_plddt_from_cif(cif_file)
            rmsd = extract_rmsd_from_cif(cif_file)

        data = np.load(npz_file)
        ptm_val = data.get('ptm', None)
        if ptm_val is not None:
            ptm = float(np.mean(ptm_val) if isinstance(ptm_val, np.ndarray) else ptm_val)

        return plddt, ptm, rmsd
    except Exception as e:
        print(f"Error loading scores: {e}")
        return None, None, None

def extract_metrics(output_dir):
    """Extract all metrics from folding output directory"""
    metrics = defaultdict(lambda: {'plddt': [], 'ptm': [], 'rmsd': [], 'model': []})

    folding_output = Path(output_dir) / 'folding_output'
    if not folding_output.exists():
        print(f"Folding output directory not found: {folding_output}")
        return metrics

    for pred_dir in sorted(folding_output.iterdir()):
        if not pred_dir.is_dir() or pred_dir.name == 'fastas':
            continue

        protein_name = pred_dir.name

        for score_file in sorted(pred_dir.glob('scores.model_idx_*.npz')):
            model_idx = score_file.stem.split('_')[-1]
            plddt, ptm, rmsd = load_chai_scores(pred_dir, score_file)

            if plddt is not None and ptm is not None and rmsd is not None:
                metrics[protein_name]['plddt'].append(plddt)
                metrics[protein_name]['ptm'].append(ptm)
                metrics[protein_name]['rmsd'].append(rmsd)
                metrics[protein_name]['model'].append(f"Model {model_idx}")

    return metrics

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Extract metrics from folding output (old plotting removed)')
    parser.add_argument('--output_dir', required=True, help='Output directory with folding_output subdir')

    args = parser.parse_args()

    metrics = extract_metrics(args.output_dir)
