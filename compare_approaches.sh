#!/bin/bash
#
# Compare results across multiple design approaches
# Aggregates top results from each approach for ranking and comparison
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "=========================================================================="
echo "Cross-Approach Comparison Analysis"
echo "=========================================================================="
echo ""

# Run Python analysis to compare approaches
python3 << 'PYEOF'
import json
import yaml
import os
import pandas as pd
import numpy as np
from pathlib import Path
from collections import defaultdict

print("Scanning all approaches for analysis results...\n")

results = []
configs = []

# Load all config files
for config_file in sorted(Path("./config").glob("sialinbinder*.yaml")):
    try:
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
        configs.append((config_file.stem, config))
    except Exception as e:
        print(f"Warning: Could not load {config_file}: {e}")

# Extract results from each approach
for config_name, config in configs:
    work_dir = config.get('output', {}).get('work_directory', '')
    config_subdir = config.get('output', {}).get('subdirectory', '')

    if not config_subdir or config_subdir == 'design_run':
        rfd3_settings = config.get('rfd3', {}).get('settings_json', '')
        json_name = os.path.splitext(os.path.basename(rfd3_settings))[0]
        subdir = json_name if json_name else 'design_run'
    else:
        subdir = config_subdir

    design_dir = Path(work_dir) / "design_generation" / subdir
    analysis_dir = design_dir / "analysis"

    # Look for ranking JSON
    json_files = list(analysis_dir.glob("top100_global_ranking_*.json"))

    if json_files:
        try:
            with open(json_files[0], 'r') as f:
                data = json.load(f)

            top_100 = data.get('top_100', [])
            total_structures = data.get('total_structures', len(top_100))

            if top_100:
                # Extract metrics
                scores = [s.get('aggregate_score', 0) for s in top_100]
                iptm_ptm = [s.get('ipTM', s.get('pTM', 0)) for s in top_100]
                plddt = [s.get('pLDDT', 0) for s in top_100]

                # Calculate statistics
                result = {
                    'Approach': config_name,
                    'Total': total_structures,
                    'Best Score': max(scores),
                    'Mean Score': np.mean(scores),
                    'Std Score': np.std(scores),
                    'Best ipTM/pTM': max(iptm_ptm),
                    'Mean ipTM/pTM': np.mean(iptm_ptm),
                    'Best pLDDT': max(plddt),
                    'Mean pLDDT': np.mean(plddt),
                    'Top5 Mean': np.mean(scores[:5]),
                    'Top10 Mean': np.mean(scores[:10]),
                }

                # Count designs above threshold
                high_score_count = sum(1 for s in scores if s > 0.85)
                result['Designs >0.85'] = high_score_count

                results.append(result)
                print(f"✓ {config_name:<40} Total: {total_structures:<3} Best: {result['Best Score']:.4f}")
        except Exception as e:
            print(f"✗ {config_name:<40} Error: {e}")
    else:
        print(f"⏳ {config_name:<40} No analysis found (maybe still running?)")

if not results:
    print("\nNo completed analyses found. Run analysis scripts first!")
    exit(1)

# Create comparison dataframe
df = pd.DataFrame(results)

# Sort by best score
df_sorted = df.sort_values('Best Score', ascending=False)

print("\n" + "="*120)
print("OVERALL RANKING BY BEST SCORE")
print("="*120)
print(df_sorted[['Approach', 'Total', 'Best Score', 'Mean Score', 'Best ipTM/pTM', 'Mean ipTM/pTM', 'Best pLDDT', 'Designs >0.85']].to_string(index=False))

print("\n" + "="*120)
print("RANKED BY MEAN SCORE (Most Consistent)")
print("="*120)
df_mean = df.sort_values('Mean Score', ascending=False)
print(df_mean[['Approach', 'Best Score', 'Mean Score', 'Std Score', 'Top5 Mean', 'Top10 Mean']].to_string(index=False))

print("\n" + "="*120)
print("RANKED BY MEAN ipTM/pTM (Ligand Binding Quality)")
print("="*120)
df_iptm = df.sort_values('Mean ipTM/pTM', ascending=False)
print(df_iptm[['Approach', 'Best ipTM/pTM', 'Mean ipTM/pTM', 'Best pLDDT', 'Mean pLDDT']].to_string(index=False))

print("\n" + "="*120)
print("TOP 3 RECOMMENDED APPROACHES")
print("="*120)
print("\n1️⃣  BEST SINGLE DESIGN:")
best = df_sorted.iloc[0]
print(f"   {best['Approach']}")
print(f"      Best Score: {best['Best Score']:.4f} | ipTM/pTM: {best['Best ipTM/pTM']:.4f} | pLDDT: {best['Best pLDDT']:.1f}")

print("\n2️⃣  MOST CONSISTENT:")
most_consistent = df_mean.iloc[0]
print(f"   {most_consistent['Approach']}")
print(f"      Mean Score: {most_consistent['Mean Score']:.4f} | Std: {most_consistent['Std Score']:.4f}")

print("\n3️⃣  BEST LIGAND BINDING:")
best_ligand = df_iptm.iloc[0]
print(f"   {best_ligand['Approach']}")
print(f"      Mean ipTM: {best_ligand['Mean ipTM/pTM']:.4f} | Best ipTM: {best_ligand['Best ipTM/pTM']:.4f}")

# Save comparison to CSV
csv_file = Path("sialinbinder_approach_comparison.csv")
df_sorted.to_csv(csv_file, index=False)
print(f"\n✓ Saved detailed comparison to: {csv_file}")

PYEOF

echo ""
echo "=========================================================================="
echo "Comparison complete!"
echo "=========================================================================="
