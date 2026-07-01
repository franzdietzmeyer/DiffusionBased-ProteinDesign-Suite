#!/bin/bash
#
# Extract the single best design from each approach
# Copies top-ranked structures to a master collection for easy access and comparison
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "=========================================================================="
echo "Extracting Best Designs from All Approaches"
echo "=========================================================================="
echo ""

# Create master folder
MASTER_DESIGNS="$SCRIPT_DIR/best_designs_global"
mkdir -p "$MASTER_DESIGNS"

python3 << 'PYEOF'
import json
import yaml
import os
import shutil
from pathlib import Path
from collections import defaultdict

master_dir = Path("./best_designs_global")
master_dir.mkdir(exist_ok=True)

print("Extracting top design from each approach...\n")
print(f"{'Rank':<5} {'Approach':<40} {'Best Score':<12} {'ipTM/pTM':<12} {'pLDDT':<10}")
print("-" * 85)

rank = 1
extracted = []

# Get all sialinbinder configs
for config_file in sorted(Path("./config").glob("sialinbinder*.yaml")):
    config_name = config_file.stem

    try:
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)

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
        top20_dir = design_dir / "top20_global_all_runs"

        # Look for ranking JSON
        json_files = list(analysis_dir.glob("top100_global_ranking_*.json"))

        if json_files and top20_dir.exists():
            with open(json_files[0], 'r') as f:
                data = json.load(f)

            top_100 = data.get('top_100', [])

            if top_100:
                best = top_100[0]
                score = best.get('aggregate_score', 0)
                iptm = best.get('ipTM', best.get('pTM', 0))
                plddt = best.get('pLDDT', 0)
                filename = best.get('filename', '')

                # Try to find the structure file
                found_file = None
                for ext in ['.cif', '.pdb']:
                    # Try in top20_global_all_runs first
                    candidates = list(top20_dir.glob(f"*{filename}*{ext}"))
                    if candidates:
                        found_file = candidates[0]
                        break

                    # Try in top20 folder
                    top20_single = design_dir / "top20"
                    if top20_single.exists():
                        candidates = list(top20_single.glob(f"01_*{ext}"))
                        if candidates:
                            found_file = candidates[0]
                            break

                if found_file:
                    dest_name = f"{rank:02d}_{config_name}_{found_file.name}"
                    dest = master_dir / dest_name
                    shutil.copy(found_file, dest)
                    extracted.append((rank, config_name, score, iptm, plddt))
                    print(f"{rank:<5} {config_name:<40} {score:<12.4f} {iptm:<12.4f} {plddt:<10.1f}")
                    rank += 1
                else:
                    print(f"⚠️  {config_name:<40} Found ranking but no structure file")
        else:
            if not json_files:
                pass  # Silently skip - analysis not done yet
            else:
                print(f"⚠️  {config_name:<40} No top20_global_all_runs folder")

    except Exception as e:
        print(f"✗  {config_name:<40} Error: {e}")

print(f"\n✓ Extracted {len(extracted)} best designs to: {master_dir}")
print(f"  Use these for wet-lab experiments or further validation")

PYEOF

echo ""
echo "=========================================================================="
echo "Best designs ready for review in: $MASTER_DESIGNS/"
echo "=========================================================================="
