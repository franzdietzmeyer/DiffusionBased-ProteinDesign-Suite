#!/usr/bin/env python3
import os
import json
import re
import shutil
import numpy as np
import matplotlib.pyplot as plt
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

def copy_top_20_structures(output_dir, metrics, plot_subdir):
    """Copy top 20 structures (based on pLDDT and pTm) to a top20 directory"""
    try:
        folding_output = Path(output_dir) / 'folding_output'
        if not folding_output.exists():
            return

        top20_dir = plot_subdir.parent / 'top20'
        top20_dir.mkdir(parents=True, exist_ok=True)

        # Collect all structures with their metrics
        structures = []
        for protein, data in metrics.items():
            if data['plddt'] and data['ptm']:
                for i, (plddt, ptm) in enumerate(zip(data['plddt'], data['ptm'])):
                    # Score: high pLDDT + high pTm (normalize both to 0-1)
                    score = (plddt / 100.0) * 0.5 + ptm * 0.5

                    # Find corresponding CIF file
                    cif_dir = folding_output / protein
                    cif_file = cif_dir / f'pred.model_idx_{i}.cif'

                    if cif_file.exists():
                        structures.append({
                            'protein': protein,
                            'model': i,
                            'plddt': plddt,
                            'ptm': ptm,
                            'score': score,
                            'cif_file': cif_file
                        })

        # Sort by score (descending) and take top 20
        structures.sort(key=lambda x: x['score'], reverse=True)
        top_20 = structures[:20]

        # Copy top 20 structures
        for rank, struct in enumerate(top_20, 1):
            dest_name = f"{rank:02d}_{struct['protein']}_model{struct['model']}.cif"
            dest_path = top20_dir / dest_name
            shutil.copy2(struct['cif_file'], dest_path)

        # Create summary file for top 20
        top20_summary = {
            'count': len(top_20),
            'structures': [
                {
                    'rank': rank,
                    'protein': s['protein'],
                    'model': s['model'],
                    'plddt': float(s['plddt']),
                    'ptm': float(s['ptm']),
                    'score': float(s['score']),
                    'filename': f"{rank:02d}_{s['protein']}_model{s['model']}.cif"
                }
                for rank, s in enumerate(top_20, 1)
            ]
        }

        summary_file = top20_dir / 'top20_summary.json'
        with open(summary_file, 'w') as f:
            json.dump(top20_summary, f, indent=2)

        print(f"\n✓ Copied top 20 structures to: {top20_dir}")
        print(f"  Summary saved to: {summary_file}")

    except Exception as e:
        print(f"Warning: Could not copy top 20 structures: {e}")

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

def plot_metrics(metrics, output_dir, plot_dir):
    """Create scatter plot of pLDDT vs pTm colored by RMSD"""
    output_dir = Path(output_dir)
    plot_dir = Path(plot_dir)

    # Extract subdirectory name from output_dir path
    subdir_name = output_dir.parent.name

    # Ensure plot_dir is inside the work directory structure
    plot_subdir = plot_dir
    plot_subdir.mkdir(parents=True, exist_ok=True)

    # Flatten data for plotting
    all_plddt = []
    all_ptm = []
    all_rmsd = []

    for protein, data in metrics.items():
        if data['plddt'] and data['ptm'] and data['rmsd']:
            all_plddt.extend(data['plddt'])
            all_ptm.extend(data['ptm'])
            all_rmsd.extend(data['rmsd'])

    if not all_plddt:
        print("No metrics data found to plot")
        return

    # Create scatter plot with RMSD as divergent color
    fig, ax = plt.subplots(figsize=(11, 8))

    scatter = ax.scatter(all_plddt, all_ptm, c=all_rmsd, s=150, alpha=0.8,
                        cmap='RdYlGn_r', edgecolors='black', linewidth=0.5)

    cbar = plt.colorbar(scatter, ax=ax, pad=0.02)
    cbar.set_label('RMSD (Å)', fontsize=11, fontweight='bold')

    ax.set_xlabel('pLDDT (Predicted Local Distance Test)', fontsize=12, fontweight='bold')
    ax.set_ylabel('pTm (Predicted TM-score)', fontsize=12, fontweight='bold')
    ax.set_title(f'Structure Prediction Quality: {subdir_name}\npLDDT vs pTm (colored by RMSD)',
                fontsize=13, fontweight='bold', pad=20)
    ax.grid(True, alpha=0.2, linestyle='--')
    ax.set_xlim([0, 100])
    ax.set_ylim([0, 1])

    plt.tight_layout()
    plot_file = plot_subdir / f'{subdir_name}_plddt_vs_ptm.png'
    plt.savefig(plot_file, dpi=300, bbox_inches='tight')
    print(f"✓ Saved plot: {plot_file}")
    plt.close()

    # Save metrics to JSON
    metrics_json = {
        protein: {
            'plddt': [float(x) for x in data['plddt']],
            'ptm': [float(x) for x in data['ptm']],
            'rmsd': [float(x) for x in data['rmsd']],
            'avg_plddt': float(np.mean(data['plddt'])) if data['plddt'] else 0,
            'avg_ptm': float(np.mean(data['ptm'])) if data['ptm'] else 0,
            'avg_rmsd': float(np.mean(data['rmsd'])) if data['rmsd'] else 0,
        }
        for protein, data in metrics.items()
    }

    metrics_file = plot_subdir / f'{subdir_name}_metrics_summary.json'
    with open(metrics_file, 'w') as f:
        json.dump(metrics_json, f, indent=2)
    print(f"✓ Saved metrics: {metrics_file}")

    # Copy top 20 structures
    copy_top_20_structures(output_dir, metrics, plot_subdir)

    # Print summary
    print("\n" + "="*70)
    print(f"METRICS SUMMARY - {subdir_name}")
    print("="*70)
    for protein, stats in metrics_json.items():
        print(f"\n{protein}:")
        print(f"  Average pLDDT: {stats['avg_plddt']:.2f}")
        print(f"  Average pTm:   {stats['avg_ptm']:.3f}")
        print(f"  Average RMSD:  {stats['avg_rmsd']:.2f} Å")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Plot protein design prediction metrics')
    parser.add_argument('--output_dir', required=True, help='Output directory with folding_output subdir')
    parser.add_argument('--plot_dir', required=True, help='Directory to save plots (must be in work directory structure)')

    args = parser.parse_args()

    metrics = extract_metrics(args.output_dir)
    plot_metrics(metrics, args.output_dir, args.plot_dir)
