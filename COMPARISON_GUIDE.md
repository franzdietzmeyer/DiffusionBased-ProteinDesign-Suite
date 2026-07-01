# Cross-Approach Comparison Guide

## Overview
You have multiple design strategies for SialinBinder. This guide helps you identify the most promising approach.

## The Two Comparison Scripts

### 1. **`./compare_approaches.sh`** — Full Statistical Comparison
Compares all completed approaches across multiple metrics.

**Run it:**
```bash
./compare_approaches.sh
```

**Output:**
- **Ranking by Best Score** — Which approach has the highest single design?
- **Ranking by Mean Score** — Which approach is most consistent?
- **Ranking by ipTM/pTM** — Which has best ligand binding on average?
- **Top 3 Recommendations** — Quick summary of best approaches
- **CSV file** — Detailed metrics for spreadsheet analysis

**Key Metrics:**

| Metric | What to Look For |
|--------|-----------------|
| **Best Score** | Peak performance |
| **Mean Score** | Average quality (higher = better) |
| **Std Dev** | Consistency (lower = more reliable) |
| **Designs >0.85** | How many passed quality threshold |
| **Top5/Top10 Mean** | Elite designs consistency |

---

### 2. **`./extract_best_designs.sh`** — Master Collection
Extracts the #1 design from each completed approach into one folder.

**Run it:**
```bash
./extract_best_designs.sh
```

**Output:**
- All best designs copied to `best_designs_global/`
- Named with ranking prefix: `01_sialinbinder_exposed.cif`, `02_sialinbinder_with_ligand.cif`, etc.
- Ready for wet-lab validation or further analysis

---

## Workflow: Complete Comparison

### Step 1: Confirm All Jobs Finished
```bash
./monitor_jobs.sh
```
Look for all designs showing "✓ COMPLETE" status.

### Step 2: Run Analysis for Each Approach
For any approach without analysis yet:
```bash
./run_analysis.sh --config config/sialinbinder_pocket_refined.yaml
./run_analysis.sh --config config/sialinbinder_rasa_exposed.yaml
# ... repeat for each approach
```

This creates:
- Analysis output (plots, CSVs, JSON rankings)
- `top20_global_all_runs/` folder with top 20 structures from all 5 runs

### Step 3: Compare All Approaches
```bash
./compare_approaches.sh
```

**What to Look For:**

#### Best Performer
- High **Best Score** (>0.93)
- High **Mean Score** (>0.90)
- Low **Std Dev** (<0.01)

#### Most Reliable
- High **Mean Score**
- Low **Std Dev** (tight distribution)
- High **Top5/Top10 Mean** (elite designs are excellent)

#### Best for Ligand Binding
- High **Best ipTM/pTM** (>0.93)
- High **Mean ipTM/pTM** (>0.90)
- High **Best pLDDT** (>93)

### Step 4: Extract Best Candidates
```bash
./extract_best_designs.sh
```

This collects the top design from each approach into `best_designs_global/` for side-by-side analysis.

---

## What Metrics Mean for Your Design

### Score Formula (Ligand Designs)
```
Score = 0.8 × ipTM + 0.2 × (pLDDT/100) - RMSD_penalty
```

**Interpretation:**
- **ipTM** (80% weight) — Ligand-protein interface quality. **MOST IMPORTANT**
  - >0.93 = Excellent prediction
  - 0.85-0.93 = Good prediction
  - <0.85 = Uncertain

- **pLDDT** (20% weight) — Protein structure confidence
  - >90 = Very confident
  - 80-90 = Confident
  - <80 = Less confident

- **RMSD** — Backbone deviation from template
  - <2.0 Å = Very close to design
  - 2-3 Å = Good
  - >3 Å = Significant deviation

---

## Decision Matrix

Use this table to pick the best approach:

```
┌─ What's Your Priority? ──────────────────┐
│                                           │
│ Single Best Design?                       │
│ → Look at "Best Score" ranking            │
│ → Pick approach at top of list            │
│                                           │
│ Most Reliable/Consistent?                 │
│ → Look at "Mean Score" & "Std Dev"        │
│ → Pick lowest Std Dev (most reliable)     │
│                                           │
│ Best Ligand Binding?                      │
│ → Look at "Mean ipTM/pTM" ranking         │
│ → Pick highest mean ipTM                  │
│                                           │
│ Balanced (all-rounder)?                   │
│ → Look at "Top 3 Recommended"             │
│ → These balance all metrics               │
│                                           │
└─────────────────────────────────────────┘
```

---

## Example Analysis

**Your Current Results:**

```
BEST SINGLE DESIGN:
  sialinbinder_partexposed
  Score: 0.9433 | ipTM: 0.9500 | pLDDT: 96.3
  → Top-ranked single design

MOST CONSISTENT:
  sialinbinder_exposed
  Mean: 0.9291 | Std: 0.0063
  → Very tight distribution - highly reliable

BEST LIGAND BINDING:
  sialinbinder_exposed
  Mean ipTM: 0.9308 | Best: 0.9438
  → Consistently great ligand positioning
```

**Recommendation:** If you can only pick one → **sialinbinder_exposed** (best balance of top performance + consistency)

---

## Next Steps After Comparison

### If You Have a Winner:
1. Extract its best designs: `extract_best_designs.sh`
2. Open top structures in ChimeraX/PyMOL
3. Visually inspect:
   - Ligand positioning (if applicable)
   - Protein folding quality
   - Potential issues

### For Wet-Lab Validation:
1. Pick top 5-10 designs from best approach
2. Synthesize and test binding affinity
3. Correlate ipTM/pLDDT with experimental results

### For Further Refinement:
1. Take best approach's top structures
2. Use as templates for next design iteration
3. Adjust design constraints based on what worked

---

## Troubleshooting

**"No analysis found"**
→ Run `./run_analysis.sh` for that approach first

**"No structure files found"**
→ Run `./run_analysis.sh` which creates `top20_global_all_runs/`

**Results look different each run**
→ Normal - stochastic sampling. Compare means, not single values

---

## Files Generated

| File | Purpose |
|------|---------|
| `sialinbinder_approach_comparison.csv` | Detailed metrics for all approaches |
| `best_designs_global/` | Top design from each approach |
| `*/analysis/` | Detailed results per approach |

---

## Tips for Best Results

✓ Look at **mean metrics** not just best (more representative)  
✓ Check **Std Dev** (low = consistent, high = lottery)  
✓ For ligand: prioritize **ipTM over pLDDT**  
✓ Compare approaches with similar # of structures (fair comparison)  
✓ Visual inspection beats metrics (open in ChimeraX!)
