#!/usr/bin/env python3
import os
import json
import re
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
                # Find the column index for B_iso_or_equiv
                if '_atom_site.B_iso_or_equiv' in line:
                    b_iso_index = col_index

                # Track column indices in loop
                if line.startswith('_atom_site.'):
                    in_atom_loop = True
                    if 'B_iso_or_equiv' not in line:
                        col_index += 1
                    continue

                # Parse atom data lines
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

def load_chai_scores(cif_dir, npz_file):
    """Load pLDDT from CIF and pTm from NPZ"""
    try:
        # Extract pLDDT from CIF file
        plddt = None
        cif_file = Path(cif_dir) / 'pred.model_idx_0.cif'
        if cif_file.exists():
            plddt = extract_plddt_from_cif(cif_file)

        # Load pTm from NPZ
        data = np.load(npz_file)
        ptm = data.get('ptm', None)

        if ptm is not None:
            ptm = float(np.mean(ptm) if isinstance(ptm, np.ndarray) else ptm)

        return plddt, ptm
    except Exception as e:
        print(f"Error loading scores: {e}")
        return None, None

def get_rmsd_from_template(pred_cif, template_pdb=None):
    """Extract or estimate RMSD (placeholder - returns 0 if no template)"""
    # This is a placeholder. In practice, you'd compute RMSD vs template
    # For now, we'll note this as TBD
    return None

def extract_metrics(output_dir):
    """Extract all metrics from folding output directory"""
    metrics = defaultdict(lambda: {'plddt': [], 'ptm': [], 'model': []})

    folding_output = Path(output_dir) / 'folding_output'
    if not folding_output.exists():
        print(f"Folding output directory not found: {folding_output}")
        return metrics

    # Iterate through each protein prediction directory
    for pred_dir in sorted(folding_output.iterdir()):
        if not pred_dir.is_dir() or pred_dir.name == 'fastas':
            continue

        protein_name = pred_dir.name

        # Load all scores for this protein
        for score_file in sorted(pred_dir.glob('scores.model_idx_*.npz')):
            model_idx = score_file.stem.split('_')[-1]
            plddt, ptm = load_chai_scores(pred_dir, score_file)

            if plddt is not None and ptm is not None:
                metrics[protein_name]['plddt'].append(plddt)
                metrics[protein_name]['ptm'].append(ptm)
                metrics[protein_name]['model'].append(f"Model {model_idx}")

    return metrics

def plot_metrics(metrics, output_dir):
    """Create scatter plots of pLDDT vs pTm"""
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)

    # Flatten data for plotting
    all_plddt = []
    all_ptm = []
    protein_labels = []

    for protein, data in metrics.items():
        if data['plddt'] and data['ptm']:
            all_plddt.extend(data['plddt'])
            all_ptm.extend(data['ptm'])
            protein_labels.extend([protein] * len(data['plddt']))

    if not all_plddt:
        print("No metrics data found to plot")
        return

    # Create scatter plot: pLDDT vs pTm
    fig, ax = plt.subplots(figsize=(12, 8))

    # Color by protein
    unique_proteins = list(set(protein_labels))
    colors = plt.cm.tab10(np.linspace(0, 1, len(unique_proteins)))
    color_map = {p: colors[i] for i, p in enumerate(unique_proteins)}

    for protein in unique_proteins:
        mask = [p == protein for p in protein_labels]
        plddt_subset = [all_plddt[i] for i in range(len(all_plddt)) if mask[i]]
        ptm_subset = [all_ptm[i] for i in range(len(all_ptm)) if mask[i]]

        ax.scatter(plddt_subset, ptm_subset, label=protein,
                  s=100, alpha=0.7, color=color_map[protein])

    ax.set_xlabel('pLDDT (Predicted Local Distance Test)', fontsize=12)
    ax.set_ylabel('pTm (Predicted TM-score)', fontsize=12)
    ax.set_title('Protein Structure Prediction Quality Metrics', fontsize=14, fontweight='bold')
    ax.legend(bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xlim([0, 100])
    ax.set_ylim([0, 1])

    plt.tight_layout()
    plot_file = output_dir / 'plddt_vs_ptm.png'
    plt.savefig(plot_file, dpi=300, bbox_inches='tight')
    print(f"✓ Saved plot: {plot_file}")
    plt.close()

    # Save metrics to JSON
    metrics_json = {
        protein: {
            'plddt': [float(x) for x in data['plddt']],
            'ptm': [float(x) for x in data['ptm']],
            'avg_plddt': float(np.mean(data['plddt'])) if data['plddt'] else 0,
            'avg_ptm': float(np.mean(data['ptm'])) if data['ptm'] else 0,
        }
        for protein, data in metrics.items()
    }

    metrics_file = output_dir / 'metrics_summary.json'
    with open(metrics_file, 'w') as f:
        json.dump(metrics_json, f, indent=2)
    print(f"✓ Saved metrics: {metrics_file}")

    # Print summary
    print("\n" + "="*70)
    print("METRICS SUMMARY")
    print("="*70)
    for protein, stats in metrics_json.items():
        print(f"\n{protein}:")
        print(f"  Average pLDDT: {stats['avg_plddt']:.2f}")
        print(f"  Average pTm:   {stats['avg_ptm']:.3f}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Plot protein design prediction metrics')
    parser.add_argument('--output_dir', required=True, help='Output directory with folding_output subdir')
    parser.add_argument('--plot_dir', default='plots', help='Directory to save plots')

    args = parser.parse_args()

    metrics = extract_metrics(args.output_dir)
    plot_metrics(metrics, args.plot_dir)
