#!/usr/bin/env python3
"""
Convert .cif.gz files to .cif or .pdb files using gemmi.

This script processes all .cif.gz files in a specified output folder
and converts them to uncompressed .cif or .pdb files.

Usage:
    uv run python convert_cif_gz.py <output_folder> [--format cif|pdb]
    
Examples:
    uv run python convert_cif_gz.py logs/inference_outs/demo/0
    uv run python convert_cif_gz.py logs/inference_outs/demo/0 --format pdb
    uv run python convert_cif_gz.py logs/inference_outs/demo/0 --format cif
"""

import argparse
import sys
from pathlib import Path
from typing import Optional

try:
    import gemmi
except ImportError:
    print("ERROR: gemmi is not installed. Please install it with:")
    print("  uv pip install gemmi")
    sys.exit(1)


def convert_cif_gz_to_format(
    input_path: Path,
    output_format: str = "cif",
    output_path: Optional[Path] = None,
    keep_original: bool = True,
) -> bool:
    """
    Convert a .cif.gz file to .cif or .pdb format using gemmi.
    
    Args:
        input_path: Path to the input .cif.gz file
        output_format: Output format, either "cif" or "pdb" (default: "cif")
        output_path: Path for the output file. If None, uses input path with new extension
        keep_original: Whether to keep the original .cif.gz file
        
    Returns:
        True if conversion was successful, False otherwise
    """
    # DEBUG: Print input path
    print(f"DEBUG: Processing {input_path} -> {output_format.upper()}")
    
    # Validate input file exists
    if not input_path.exists():
        print(f"ERROR: Input file does not exist: {input_path}")
        return False
    
    # Validate input file extension
    if not input_path.name.endswith('.cif.gz'):
        print(f"WARNING: File does not end with .cif.gz: {input_path}")
        return False
    
    # Validate output format
    output_format = output_format.lower()
    if output_format not in ["cif", "pdb"]:
        print(f"ERROR: Invalid output format '{output_format}'. Must be 'cif' or 'pdb'")
        return False
    
    # Determine output path
    if output_path is None:
        # Remove .gz and .cif, then add new extension
        base_name = input_path.stem.replace('.cif', '')  # Remove .cif from .cif.gz
        output_path = input_path.parent / f"{base_name}.{output_format}"
    
    try:
        # Read the compressed CIF file using gemmi
        # gemmi can read gzipped files directly
        doc = gemmi.cif.read(str(input_path))
        
        if output_format == "cif":
            # Write to uncompressed CIF file
            doc.write_file(str(output_path))
            
        elif output_format == "pdb":
            # Convert CIF to PDB format
            # First, get the structure from the CIF document
            block = doc.sole_block()  # Get the first (and usually only) block
            
            # Parse the structure from CIF
            structure = gemmi.make_structure_from_block(block)
            
            # Write to PDB file
            structure.write_pdb(str(output_path))
        
        print(f"SUCCESS: Converted {input_path.name} -> {output_path.name}")
        
        # Optionally remove the original file
        if not keep_original:
            input_path.unlink()
            print(f"DEBUG: Removed original file: {input_path.name}")
        
        return True
        
    except Exception as e:
        print(f"ERROR: Failed to convert {input_path.name}: {str(e)}")
        # DEBUG: Print full exception details
        import traceback
        print(f"DEBUG: Traceback:\n{traceback.format_exc()}")
        return False


def process_directory(
    directory: Path,
    output_format: str = "cif",
    recursive: bool = False,
    keep_original: bool = True,
) -> tuple[int, int]:
    """
    Process all .cif.gz files in a directory.
    
    Args:
        directory: Directory to process
        output_format: Output format, either "cif" or "pdb" (default: "cif")
        recursive: Whether to search recursively in subdirectories
        keep_original: Whether to keep original .cif.gz files
        
    Returns:
        Tuple of (successful_count, failed_count)
    """
    if not directory.exists():
        print(f"ERROR: Directory does not exist: {directory}")
        return (0, 0)
    
    if not directory.is_dir():
        print(f"ERROR: Path is not a directory: {directory}")
        return (0, 0)
    
    # Find all .cif.gz files
    pattern = "**/*.cif.gz" if recursive else "*.cif.gz"
    cif_gz_files = list(directory.glob(pattern))
    
    if not cif_gz_files:
        print(f"WARNING: No .cif.gz files found in {directory}")
        return (0, 0)
    
    print(f"Found {len(cif_gz_files)} .cif.gz file(s) to process")
    print(f"Output format: {output_format.upper()}")
    print("-" * 60)
    
    successful = 0
    failed = 0
    
    for cif_gz_file in sorted(cif_gz_files):
        if convert_cif_gz_to_format(
            cif_gz_file,
            output_format=output_format,
            keep_original=keep_original
        ):
            successful += 1
        else:
            failed += 1
    
    print("-" * 60)
    print(f"Conversion complete: {successful} successful, {failed} failed")
    
    return (successful, failed)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Convert .cif.gz files to .cif or .pdb files using gemmi",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    
    parser.add_argument(
        "output_folder",
        type=str,
        help="Path to the output folder containing .cif.gz files",
    )
    
    parser.add_argument(
        "-f", "--format",
        type=str,
        choices=["cif", "pdb"],
        default="cif",
        help="Output format: 'cif' or 'pdb' (default: 'cif')",
    )
    
    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Search for .cif.gz files recursively in subdirectories",
    )
    
    parser.add_argument(
        "--remove-original",
        action="store_true",
        help="Remove original .cif.gz files after conversion",
    )
    
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug output",
    )
    
    args = parser.parse_args()
    
    # Convert to Path object
    output_folder = Path(args.output_folder).resolve()
    
    # DEBUG: Print configuration
    if args.debug:
        print(f"DEBUG: Output folder: {output_folder}")
        print(f"DEBUG: Output format: {args.format}")
        print(f"DEBUG: Recursive: {args.recursive}")
        print(f"DEBUG: Remove original: {args.remove_original}")
        print(f"DEBUG: Gemmi version: {gemmi.__version__ if hasattr(gemmi, '__version__') else 'unknown'}")
        print("-" * 60)
    
    # Process the directory
    successful, failed = process_directory(
        output_folder,
        output_format=args.format,
        recursive=args.recursive,
        keep_original=not args.remove_original,
    )
    
    # Exit with appropriate code
    if failed > 0:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()


