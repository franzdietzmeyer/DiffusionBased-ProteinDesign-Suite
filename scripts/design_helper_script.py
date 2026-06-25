#!/usr/bin/env python3
"""
Helper script for validation and filtering of design structures.

This script performs automated validation and filtering of designed structures
using outputs from RFDiffusion, LigandMPNN, and various folding engines.
It extracts confidence metrics (pLDDT, pTM), parses fixed-residue constraints,
and calculates structural metrics to ensure active site preservation.
"""

import os
import json
import argparse
import shutil
import pandas as pd
import numpy as np
import sys
from pathlib import Path
from Bio.PDB import PDBParser, MMCIFParser, PDBIO, Superimposer, ShrakeRupley, is_aa
import gemmi

# Mapping for sequence extraction
THREE_TO_ONE_MAP = {
    'ALA': 'A', 'CYS': 'C', 'ASP': 'D', 'GLU': 'E', 'PHE': 'F',
    'GLY': 'G', 'HIS': 'H', 'ILE': 'I', 'LYS': 'K', 'LEU': 'L',
    'MET': 'M', 'ASN': 'N', 'PRO': 'P', 'GLN': 'Q', 'ARG': 'R',
    'SER': 'S', 'THR': 'T', 'VAL': 'V', 'TRP': 'W', 'TYR': 'Y'
}


def extract_chain_sequence(cif_path, chain_id='A'):
    """Extract amino acid sequence from CIF file."""
    parser = MMCIFParser(QUIET=True)
    structure = parser.get_structure("pdb", cif_path)
    model = structure[0]
    if chain_id not in model:
        return None
    seq = ''.join([THREE_TO_ONE_MAP.get(res.get_resname(), 'X')
                   for res in model[chain_id] if is_aa(res, standard=True)])
    return seq, len(seq)


def get_structure_data(pdb_path):
    """Extract CA atoms and sequence from PDB or CIF."""
    ext = Path(pdb_path).suffix.lower()
    parser = MMCIFParser(QUIET=True) if ext == '.cif' else PDBParser(QUIET=True)

    structure = parser.get_structure('id', str(pdb_path))
    ca_atoms = []
    sequence = ""

    from Bio.PDB import PPBuilder
    ppb = PPBuilder()
    for model in structure:
        for pp in ppb.build_peptides(model):
            sequence += str(pp.get_sequence())
            for res in pp:
                if 'CA' in res:
                    ca_atoms.append(res['CA'])
    return ca_atoms, sequence


def calculate_motif_rmsd(design_cif, template_pdb, indices, chain_id="A"):
    """Calculate all-atom RMSD for specific residues (active site)."""
    parser = PDBParser(QUIET=True)
    cif_parser = MMCIFParser(QUIET=True)
    design_model = cif_parser.get_structure("design", design_cif)[0]
    template_model = parser.get_structure("template", template_pdb)[0]

    design_atoms = []
    template_atoms = []

    for idx in indices:
        try:
            res_d = design_model[chain_id][idx]
            res_t = template_model[chain_id][idx]

            for atom in res_t:
                if atom.element not in ["H", "D"]:
                    atom_name = atom.get_name()
                    if atom_name in res_d:
                        design_atoms.append(res_d[atom_name])
                        template_atoms.append(res_t[atom_name])
        except KeyError:
            continue

    if not design_atoms:
        return None

    si = Superimposer()
    si.set_atoms(template_atoms, design_atoms)
    return si.rms


def extract_metrics_from_npz(npz_path):
    """Extract folding metrics from .npz score file."""
    scores = np.load(npz_path)
    return (
        scores['aggregate_score'].item(),
        scores['ptm'].item(),
        scores['iptm'].item()
    )


def calculate_backbone_rmsd(template_path, refolded_path):
    """Calculate Cα backbone RMSD between structures."""
    p = PDBParser(QUIET=True)
    c = MMCIFParser(QUIET=True)
    try:
        ref_struct = p.get_structure('ref', str(template_path))
        deg_struct = c.get_structure('deg', str(refolded_path))
        ref_atoms = [a for a in ref_struct.get_atoms() if a.get_id() == 'CA']
        deg_atoms = [a for a in deg_struct.get_atoms() if a.get_id() == 'CA']
        if len(ref_atoms) != len(deg_atoms):
            return None
        sup = Superimposer()
        sup.set_atoms(ref_atoms, deg_atoms)
        return sup.rms
    except Exception:
        return None


def get_total_plddt(design_cif, chain_id="A"):
    """Get average pLDDT for entire structure."""
    parser = MMCIFParser(QUIET=True)
    design_model = parser.get_structure("design", design_cif)[0]
    plddt_values = [atom.get_bfactor() for res in design_model[chain_id]
                    for atom in res if is_aa(res)]
    return (np.mean(plddt_values) / 100) if plddt_values else None


def get_motif_plddt(design_cif, indices, chain_id="A"):
    """Extract average pLDDT for specific residues (active site)."""
    parser = MMCIFParser(QUIET=True)
    design_model = parser.get_structure("design", design_cif)[0]

    plddt_values = []
    if indices:
        for idx in indices:
            try:
                res_d = design_model[chain_id][idx]
                for atom in res_d:
                    plddt_values.append(atom.get_bfactor())
            except KeyError:
                continue
    return (np.mean(plddt_values) / 100) if plddt_values else None


def calculate_cofactor_sasa(cif_file, cofactor='VO4'):
    """Calculate solvent-accessible surface area for ligand/cofactor."""
    parser = MMCIFParser(QUIET=True)
    structure = parser.get_structure("struct", cif_file)

    sr = ShrakeRupley(n_points=100)
    sr.compute(structure, level="A")

    sasa_total = 0.0
    for model in structure:
        for chain in model:
            for residue in chain:
                if residue.get_resname() == 'LIG2':
                    for atom in residue:
                        sasa_total += atom.sasa
                    break
    return sasa_total


def save_csv(df, filepath):
    """Save DataFrame to CSV, appending if file exists."""
    header = not os.path.exists(filepath)
    df.to_csv(filepath, mode='a', index=False, header=header)


def read_fixed_res_json(fixed_res_json, template_name):
    """Parse fixed residues from LigandMPNN JSON output."""
    with open(fixed_res_json, 'r') as f:
        data = json.load(f)
    res_str = None
    for key in data.keys():
        if Path(key).name == template_name:
            res_str = data[key]
            break
    if res_str is None:
        print(f"Warning: No key matching structure '{template_name}' in {fixed_res_json}")
        return []

    indices = [int(''.join(filter(str.isdigit, s))) for s in res_str.split()]
    return indices


def main():
    parser = argparse.ArgumentParser(
        description="Validation and filtering of designed structures"
    )
    parser.add_argument("--input", required=True, help="Path to folding output directory")
    parser.add_argument("--template_pdbs", help="Directory containing template PDBs")
    parser.add_argument("--passed_output_dir", default="filtered_designs")
    parser.add_argument("--output_dir", default="designs")
    parser.add_argument("--min_plddt", type=float, default=80.0)
    parser.add_argument("--min_motif_plddt", type=float, default=85.0)
    parser.add_argument("--max_rmsd", type=float, default=3.0)
    parser.add_argument("--max_motif_rmsd", type=float, default=3.0)
    parser.add_argument("--fixed_res_json", type=str,
                       help="Fixed residues JSON from sequence design")
    parser.add_argument("--cofactor", type=str, default="VO4")
    parser.add_argument("--min_cofactor_sasa", type=float, default=None)
    args = parser.parse_args()

    input_path = Path(args.input)
    os.makedirs(args.output_dir, exist_ok=True)
    os.makedirs(args.passed_output_dir, exist_ok=True)

    results = []

    for sub_dir in input_path.iterdir():
        if not sub_dir.is_dir():
            continue

        cif_file = next(sub_dir.glob("*_0.cif"), None)
        npz_file = next(sub_dir.glob("*_idx_0.npz"), None)

        if not cif_file:
            continue

        if cif_file and npz_file:
            try:
                aggregate_score, ptm, iptm = extract_metrics_from_npz(npz_file)
                plddt = get_total_plddt(cif_file)
                seq, length = extract_chain_sequence(cif_file)

                cofactor_sasa = None
                if args.cofactor and args.cofactor != "":
                    try:
                        cofactor_sasa = calculate_cofactor_sasa(cif_file)
                    except Exception:
                        print(f'Warning: cofactor SASA calculation failed for {sub_dir.name}')

                template_pdb = None
                if args.template_pdbs:
                    all_templates = list(Path(args.template_pdbs).glob("*.pdb"))
                    all_templates.sort(key=lambda x: len(x.name), reverse=True)
                    for tp in all_templates:
                        if sub_dir.name.startswith(tp.stem):
                            template_pdb = tp
                            break

                rmsd = None
                try:
                    rmsd = calculate_backbone_rmsd(template_pdb, cif_file) \
                        if template_pdb and template_pdb.exists() else None
                except Exception as e:
                    print(f'Error calculating RMSD for {template_pdb}: {e}')

                indices = None
                motif_rmsd = None
                motif_plddt = None
                if args.fixed_res_json:
                    try:
                        indices = read_fixed_res_json(args.fixed_res_json, template_pdb.name)
                        motif_rmsd = calculate_motif_rmsd(cif_file, template_pdb, indices)
                    except Exception as e:
                        print(f'Warning: Error reading fixed residues: {e}')

                    motif_plddt = get_motif_plddt(cif_file, indices)

                # Filtering logic
                failed_list = []
                passed = True

                if plddt is None or plddt < args.min_plddt:
                    passed = False
                    failed_list.append('pLDDT')

                if rmsd is not None and rmsd > args.max_rmsd:
                    passed = False
                    failed_list.append('backbone_RMSD')

                if args.fixed_res_json:
                    if motif_plddt is not None and motif_plddt < args.min_motif_plddt:
                        passed = False
                        failed_list.append('motif_pLDDT')

                    if motif_rmsd is not None and motif_rmsd > args.max_motif_rmsd:
                        passed = False
                        failed_list.append('motif_RMSD')

                if args.min_cofactor_sasa and str(args.min_cofactor_sasa) != "":
                    if cofactor_sasa and cofactor_sasa < args.min_cofactor_sasa:
                        passed = False
                        failed_list.append('cofactor_SASA')

                row = {
                    'Name': sub_dir.stem,
                    'pLDDT': plddt,
                    'pTM': ptm,
                    'rmsd': rmsd,
                    'motif_rmsd': motif_rmsd,
                    'motif_plddt': motif_plddt,
                    'cofactor_sasa': cofactor_sasa,
                    'Passed': passed,
                    'length': length,
                    'sequence': seq,
                    'failed_filters': str(failed_list)
                }
                results.append(row)

                full_out_path = Path(args.output_dir) / f"{sub_dir.stem}.pdb"
                structure = gemmi.read_structure(str(cif_file))
                structure.update_mmcif_block
                options = gemmi.PdbWriteOptions()
                structure.write_pdb(str(full_out_path), options)

                if passed:
                    passed_out_path = Path(args.passed_output_dir) / f"{sub_dir.stem}.pdb"
                    shutil.copy(full_out_path, passed_out_path)

            except Exception as e:
                print(f'Error processing {sub_dir.name}: {e}', file=sys.stderr)
                continue

    if results:
        df = pd.DataFrame(results)
        save_csv(df, Path(args.output_dir) / 'scores.csv')
        save_csv(df[df['Passed'] == True], Path(args.passed_output_dir) / 'passed_scores.csv')
        print(f"✓ Analysis complete: {len(results)} designs processed")
        print(f"✓ Results saved to {args.output_dir}")
    else:
        print("✗ No valid designs found", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
