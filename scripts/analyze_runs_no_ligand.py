#!/usr/bin/env python3
"""
Aggregate and analyze results from multiple runs WITHOUT LIGAND
Prioritizes pTM (scaffold quality) and pLDDT (confidence)
Generates top 100 global ranking with detailed plots and CSV exports
"""

import json
import numpy as np
import matplotlib.pyplot as plt
import csv
from pathlib import Path
import argparse
from collections import defaultdict

def load_run_metrics(run_dir):
    """Load metrics from a single run's results directory"""
    run_path = Path(run_dir)
    metrics = []

    top20_file = run_path / 'top20' / 'top20_summary.json'

    if not top20_file.exists():
        print(f"Warning: No top20_summary.json found in {run_dir}")
        return metrics

    with open(top20_file, 'r') as f:
        data = json.load(f)

    run_name = run_path.parent.name
    for struct in data.get('structures', []):
        struct['run'] = run_name
        struct['pTM'] = struct.get('ptm', 0)  # Template modeling score
        struct['pLDDT'] = struct.get('plddt', 0)  # Confidence
        struct['RMSD'] = struct.get('rmsd', 2.0) if 'rmsd' in struct else 2.0
        metrics.append(struct)

    return metrics

def calculate_aggregate_score_no_ligand(struct):
    """
    Best practice ranking for SCAFFOLD DESIGN (no ligand):
    Balanced between interface quality (pTM) and confidence (pLDDT)

    Score = 0.5 × pTM + 0.5 × (pLDDT/100) - RMSD_penalty
    """
    pTM = struct.get('pTM', 0)
    pLDDT = struct.get('pLDDT', 0)
    RMSD = struct.get('RMSD', 2.0)

    score = 0.5 * pTM + 0.5 * (pLDDT / 100.0)

    # Penalty for high RMSD
    if RMSD > 3.5:
        score -= 0.03 * (RMSD - 3.5)

    return max(0, score)

def save_results_to_csv(all_metrics, top_100, output_dir, approach_name):
    """Save results to CSV files for easy analysis in Excel/spreadsheets"""
    output_path = Path(output_dir)

    # Save all structures to CSV
    all_csv = output_path / f'all_structures_{approach_name}_scaffold.csv'
    with open(all_csv, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['rank', 'run', 'protein', 'pTM', 'pLDDT', 'RMSD', 'aggregate_score', 'filename'])
        writer.writeheader()
        for i, struct in enumerate(all_metrics, 1):
            writer.writerow({
                'rank': i,
                'run': struct['run'],
                'protein': struct['protein'],
                'pTM': f"{struct['pTM']:.4f}",
                'pLDDT': f"{struct['pLDDT']:.1f}",
                'RMSD': f"{struct['RMSD']:.2f}",
                'aggregate_score': f"{struct['aggregate_score']:.4f}",
                'filename': struct.get('filename', 'N/A')
            })
    print(f"✓ Saved all structures CSV: {all_csv}")

    # Save top 100 to CSV
    top100_csv = output_path / f'top100_structures_{approach_name}_scaffold.csv'
    with open(top100_csv, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['rank', 'run', 'protein', 'pTM', 'pLDDT', 'RMSD', 'aggregate_score', 'filename'])
        writer.writeheader()
        for i, struct in enumerate(top_100, 1):
            writer.writerow({
                'rank': i,
                'run': struct['run'],
                'protein': struct['protein'],
                'pTM': f"{struct['pTM']:.4f}",
                'pLDDT': f"{struct['pLDDT']:.1f}",
                'RMSD': f"{struct['RMSD']:.2f}",
                'aggregate_score': f"{struct['aggregate_score']:.4f}",
                'filename': struct.get('filename', 'N/A')
            })
    print(f"✓ Saved top 100 structures CSV: {top100_csv}")

def aggregate_runs(run_dirs, output_dir, approach_name):
    """Aggregate metrics from multiple runs"""
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    all_metrics = []
    for run_dir in run_dirs:
        metrics = load_run_metrics(run_dir)
        all_metrics.extend(metrics)

    if not all_metrics:
        print("Error: No metrics found in any run!")
        return

    # Calculate aggregate scores
    for struct in all_metrics:
        struct['aggregate_score'] = calculate_aggregate_score_no_ligand(struct)

    # Sort by aggregate score
    all_metrics.sort(key=lambda x: x['aggregate_score'], reverse=True)

    # Get top 100 globally
    top_100 = all_metrics[:100]

    # Print summary
    print(f"\n{'='*80}")
    print(f"MULTI-RUN ANALYSIS WITHOUT LIGAND (SCAFFOLD): {approach_name}")
    print(f"{'='*80}")
    print(f"Total structures analyzed: {len(all_metrics)}")
    print(f"Runs included: {len(run_dirs)}")
    print(f"\nTOP 20 STRUCTURES:")
    print(f"{'Rank':<5} {'Run':<25} {'Protein':<35} {'pTM':<8} {'pLDDT':<8} {'RMSD':<8} {'Score':<8}")
    print("-" * 100)

    for i, struct in enumerate(top_100[:20], 1):
        print(f"{i:<5} {struct['run']:<25} {struct['protein']:<35} "
              f"{struct['pTM']:<8.4f} {struct['pLDDT']:<8.1f} {struct['RMSD']:<8.2f} {struct['aggregate_score']:<8.4f}")

    # Statistics
    print(f"\nOVERALL STATISTICS (all {len(all_metrics)} structures):")
    print(f"  Best pTM: {max(s['pTM'] for s in all_metrics):.4f}")
    print(f"  Mean pTM: {np.mean([s['pTM'] for s in all_metrics]):.4f}")
    print(f"  Best pLDDT: {max(s['pLDDT'] for s in all_metrics):.1f}")
    print(f"  Mean pLDDT: {np.mean([s['pLDDT'] for s in all_metrics]):.1f}")
    print(f"  Mean RMSD: {np.mean([s['RMSD'] for s in all_metrics]):.2f} Å")

    # Per-run statistics
    print(f"\nPER-RUN PERFORMANCE:")
    runs = defaultdict(list)
    for struct in all_metrics:
        runs[struct['run']].append(struct)

    for run_name in sorted(runs.keys()):
        run_metrics = runs[run_name]
        best_score = max(s['aggregate_score'] for s in run_metrics)
        mean_score = np.mean([s['aggregate_score'] for s in run_metrics])
        mean_pTM = np.mean([s['pTM'] for s in run_metrics])
        mean_plddt = np.mean([s['pLDDT'] for s in run_metrics])

        print(f"  {run_name:30} Best Score: {best_score:.4f}  Mean: {mean_score:.4f}  pTM: {mean_pTM:.4f}  pLDDT: {mean_plddt:.1f}")

    # Save results
    top_100_data = {
        'approach': approach_name,
        'type': 'no_ligand',
        'total_structures': len(all_metrics),
        'num_runs': len(run_dirs),
        'ranking_formula': '0.5 × pTM + 0.5 × (pLDDT/100) - RMSD_penalty',
        'top_100': [
            {
                'rank': i,
                'run': s['run'],
                'protein': s['protein'],
                'pTM': float(s['pTM']),
                'pLDDT': float(s['pLDDT']),
                'RMSD': float(s['RMSD']),
                'aggregate_score': float(s['aggregate_score']),
                'filename': s.get('filename', 'N/A')
            }
            for i, s in enumerate(top_100, 1)
        ]
    }

    json_file = output_path / f'top100_global_ranking_{approach_name}_scaffold.json'
    with open(json_file, 'w') as f:
        json.dump(top_100_data, f, indent=2)
    print(f"\n✓ Saved top 100 rankings to: {json_file}")

    # Save to CSV
    save_results_to_csv(all_metrics, top_100, output_path, approach_name)

    # Create plots
    create_comparison_plots_no_ligand(all_metrics, top_100, output_path, approach_name)

    return all_metrics

def create_comparison_plots_no_ligand(all_metrics, top_100, output_dir, approach_name):
    """Create detailed comparison plots for scaffold design"""
    output_path = Path(output_dir)

    # Group by run
    runs = defaultdict(lambda: {'pTM': [], 'pLDDT': [], 'RMSD': [], 'score': []})

    for struct in all_metrics:
        run = struct['run']
        runs[run]['pTM'].append(struct['pTM'])
        runs[run]['pLDDT'].append(struct['pLDDT'])
        runs[run]['RMSD'].append(struct['RMSD'])
        runs[run]['score'].append(struct['aggregate_score'])

    colors = plt.cm.Set1(np.linspace(0, 1, len(runs)))
    run_names = sorted(runs.keys())

    # SEPARATE PLOT 1: ALL STRUCTURES (high resolution)
    fig1, ax1 = plt.subplots(figsize=(14, 10))
    for (run_name, data), color in zip(sorted(runs.items()), colors):
        # Add jitter to x-axis to spread overlapping points
        plddt_jitter = np.array(data['pLDDT']) + np.random.normal(0, 0.5, len(data['pLDDT']))
        ax1.scatter(plddt_jitter, data['pTM'],
                   label=run_name, s=80, alpha=0.5, color=color, edgecolors='black', linewidth=0.3)

    ax1.set_xlabel('pLDDT (Confidence)', fontsize=13, fontweight='bold')
    ax1.set_ylabel('pTM (Template Modeling Score)', fontsize=13, fontweight='bold')
    ax1.set_title(f'ALL STRUCTURES: {approach_name} ({len(all_metrics)} total)', fontsize=14, fontweight='bold')
    ax1.legend(loc='lower right', fontsize=11, title='Run ID', title_fontsize=11)
    ax1.grid(True, alpha=0.3, linestyle='--')
    ax1.set_xlim([0, 105])
    ax1.set_ylim([-0.05, 1.05])
    fig1.tight_layout()
    plt.savefig(output_path / f'all_structures_{approach_name}_scaffold.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved all structures plot: {output_path / f'all_structures_{approach_name}_scaffold.png'}")
    plt.close()

    # SEPARATE PLOT 2: TOP 100 ONLY (high resolution, colored by RMSD)
    fig2, ax2 = plt.subplots(figsize=(14, 10))
    top100_plddt = [s['pLDDT'] for s in top_100]
    top100_pTM = [s['pTM'] for s in top_100]
    top100_rmsd = [s['RMSD'] for s in top_100]

    scatter = ax2.scatter(top100_plddt, top100_pTM, c=top100_rmsd, s=150, alpha=0.8,
                         cmap='RdYlGn_r', edgecolors='black', linewidth=0.7)
    cbar = plt.colorbar(scatter, ax=ax2, pad=0.02)
    cbar.set_label('RMSD (Å)', fontsize=12, fontweight='bold')

    ax2.set_xlabel('pLDDT (Confidence)', fontsize=13, fontweight='bold')
    ax2.set_ylabel('pTM (Template Modeling Score)', fontsize=13, fontweight='bold')
    ax2.set_title(f'TOP 100 STRUCTURES: {approach_name}', fontsize=14, fontweight='bold')
    ax2.grid(True, alpha=0.3, linestyle='--')
    ax2.set_xlim([0, 105])
    ax2.set_ylim([-0.05, 1.05])
    fig2.tight_layout()
    plt.savefig(output_path / f'top100_structures_{approach_name}_scaffold.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved top 100 structures plot: {output_path / f'top100_structures_{approach_name}_scaffold.png'}")
    plt.close()

    # OPTIONAL: Create comprehensive 4-panel figure with statistics
    fig3 = plt.figure(figsize=(18, 12))
    gs = fig3.add_gridspec(2, 2, hspace=0.3, wspace=0.3)

    # Plot 1: Score distribution per run (box plot)
    ax3 = fig3.add_subplot(gs[0, 0])
    scores = [runs[run]['score'] for run in run_names]
    bp = ax3.boxplot(scores, labels=run_names, patch_artist=True)

    for patch, color in zip(bp['boxes'], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)

    ax3.set_ylabel('Aggregate Score', fontsize=11, fontweight='bold')
    ax3.set_title('Score Distribution per Run', fontsize=12, fontweight='bold')
    ax3.grid(True, alpha=0.3, linestyle='--', axis='y')

    # Plot 2: pTM distribution per run (violin plot)
    ax4 = fig3.add_subplot(gs[0, 1])
    pTM_data = [runs[run]['pTM'] for run in run_names]
    parts = ax4.violinplot(pTM_data, positions=range(len(run_names)), showmeans=True, showmedians=True)

    ax4.set_xticks(range(len(run_names)))
    ax4.set_xticklabels(run_names, rotation=45, ha='right')
    ax4.set_ylabel('pTM (Template Modeling Score)', fontsize=11, fontweight='bold')
    ax4.set_title('pTM Distribution per Run', fontsize=12, fontweight='bold')
    ax4.grid(True, alpha=0.3, linestyle='--', axis='y')
    ax4.set_ylim([0, 1])

    # Plot 3: pLDDT distribution per run
    ax5 = fig3.add_subplot(gs[1, 0])
    plddt_data = [runs[run]['pLDDT'] for run in run_names]
    parts = ax5.violinplot(plddt_data, positions=range(len(run_names)), showmeans=True, showmedians=True)

    ax5.set_xticks(range(len(run_names)))
    ax5.set_xticklabels(run_names, rotation=45, ha='right')
    ax5.set_ylabel('pLDDT (Confidence)', fontsize=11, fontweight='bold')
    ax5.set_title('pLDDT Distribution per Run', fontsize=12, fontweight='bold')
    ax5.grid(True, alpha=0.3, linestyle='--', axis='y')
    ax5.set_ylim([0, 100])

    # Plot 4: RMSD distribution per run
    ax6 = fig3.add_subplot(gs[1, 1])
    rmsd_data = [runs[run]['RMSD'] for run in run_names]
    parts = ax6.violinplot(rmsd_data, positions=range(len(run_names)), showmeans=True, showmedians=True)

    ax6.set_xticks(range(len(run_names)))
    ax6.set_xticklabels(run_names, rotation=45, ha='right')
    ax6.set_ylabel('RMSD (Å)', fontsize=11, fontweight='bold')
    ax6.set_title('RMSD Distribution per Run', fontsize=12, fontweight='bold')
    ax6.grid(True, alpha=0.3, linestyle='--', axis='y')

    fig3.suptitle(f'{approach_name} - Per-Run Statistics', fontsize=14, fontweight='bold', y=0.995)
    plt.savefig(output_path / f'perrun_statistics_{approach_name}_scaffold.png', dpi=300, bbox_inches='tight')
    print(f"✓ Saved per-run statistics plot: {output_path / f'perrun_statistics_{approach_name}_scaffold.png'}")
    plt.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Aggregate and analyze multiple runs WITHOUT LIGAND')
    parser.add_argument('--runs', nargs='+', required=True,
                       help='Directories of each run (e.g., run1_dir run2_dir run3_dir run4_dir)')
    parser.add_argument('--output', required=True, help='Output directory for analysis')
    parser.add_argument('--name', default='scaffold_design', help='Approach name for labeling')

    args = parser.parse_args()

    aggregate_runs(args.runs, args.output, args.name)
