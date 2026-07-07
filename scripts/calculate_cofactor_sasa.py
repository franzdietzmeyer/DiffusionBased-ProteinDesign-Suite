#!/usr/bin/env python3
"""
Utility to calculate solvent-accessible surface area (SASA) for ligands/cofactors in a structure.
"""

import argparse
from pathlib import Path
from Bio.PDB import PDBParser, MMCIFParser, ShrakeRupley

def calculate_cofactor_sasa(structure_file, cofactor_names=None):
    """Calculate solvent-accessible surface area for ligand/cofactor.

    Checks for standard names (LIG2, BGC, GAL, SIA, etc.) or custom names provided.
    """
    if cofactor_names is None:
        cofactor_names = {'LIG2', 'LIG', 'BGC', 'GAL', 'SIA', 'GLC', 'MAN', 'NAG'}
    elif isinstance(cofactor_names, str):
        cofactor_names = {cofactor_names}
    else:
        cofactor_names = set(cofactor_names)

    ext = Path(structure_file).suffix.lower()
    if ext == '.cif':
        parser = MMCIFParser(QUIET=True)
    elif ext == '.pdb':
        parser = PDBParser(QUIET=True)
    else:
        raise ValueError(f"Unsupported file format: {ext}")

    structure = parser.get_structure("struct", str(structure_file))

    # Calculate SASA
    sr = ShrakeRupley(n_points=100)
    sr.compute(structure, level="A")

    # Sum SASA for ligand residues
    sasa_total = 0.0
    found_cofactors = []

    for model in structure:
        for chain in model:
            for residue in chain:
                res_name = residue.get_resname()
                if res_name in cofactor_names:
                    found_cofactors.append((res_name, residue.get_id()))
                    for atom in residue:
                        if hasattr(atom, 'sasa'):
                            sasa_total += atom.sasa

    return sasa_total, found_cofactors

def main():
    parser = argparse.ArgumentParser(description="Calculate cofactor SASA from PDB/CIF structure")
    parser.add_argument("structure_file", help="Path to PDB or CIF structure file")
    parser.add_argument("--cofactors", nargs="+", help="Cofactor residue names to check (default: LIG2, BGC, GAL, SIA, etc.)")
    args = parser.parse_args()

    structure_file = Path(args.structure_file)
    if not structure_file.exists():
        print(f"Error: File not found: {structure_file}")
        return 1

    cofactor_names = set(args.cofactors) if args.cofactors else None
    sasa, cofactors = calculate_cofactor_sasa(str(structure_file), cofactor_names)

    print(f"Structure: {structure_file.name}")
    if cofactors:
        print(f"Found cofactors: {', '.join(f'{name} {id}' for name, id in cofactors)}")
        print(f"Cofactor SASA: {sasa:.2f}")
    else:
        print("No cofactors found in structure")

    return 0

if __name__ == "__main__":
    exit(main())
