#!/usr/bin/env python3
"""
Configuration utilities for design pipeline.
Handles loading, validation, and stage checkpoint management.
"""

import sys
import yaml
import json
import os
from pathlib import Path
from typing import Dict, Any, Optional, List


class ConfigLoader:
    """Load and validate design pipeline configuration from YAML."""

    REQUIRED_FIELDS = {
        'rfd3': ['settings_json', 'checkpoint', 'batch_size', 'n_batches', 'foundry_path'],
        'sequence_design': ['model_type', 'conda_env', 'ligandmpnn_path'],
        'folding_engine': ['engine'],
        'output': ['work_directory'],
    }

    FOLDING_ENGINES = ['chai', 'alphafold', 'boltz']

    def __init__(self, config_path: str):
        """Initialize with config file path."""
        self.config_path = Path(config_path)
        self.config = None
        self._load_config()
        self._validate_config()

    def _load_config(self) -> None:
        """Load YAML config file."""
        try:
            with open(self.config_path, 'r') as f:
                self.config = yaml.safe_load(f)
            if not self.config:
                raise ValueError("Config file is empty")
        except FileNotFoundError:
            raise FileNotFoundError(f"Config file not found: {self.config_path}")
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML in config file: {e}")

    def _validate_config(self) -> None:
        """Validate that required fields are present and paths exist."""
        errors = []

        # Check required top-level fields
        for section, fields in self.REQUIRED_FIELDS.items():
            if section not in self.config:
                errors.append(f"Missing section: {section}")
                continue

            for field in fields:
                if field not in self.config[section]:
                    errors.append(f"Missing required field: {section}.{field}")

        # Validate folding engine
        if self.config.get('folding_engine', {}).get('engine') not in self.FOLDING_ENGINES:
            errors.append(f"Invalid folding engine. Must be one of: {self.FOLDING_ENGINES}")

        # Validate paths that must exist
        paths_to_check = [
            ('rfd3.settings_json', self.config.get('rfd3', {}).get('settings_json')),
            ('rfd3.checkpoint', self.config.get('rfd3', {}).get('checkpoint')),
            ('rfd3.foundry_path', self.config.get('rfd3', {}).get('foundry_path')),
            ('sequence_design.conda_env', self.config.get('sequence_design', {}).get('conda_env')),
            ('sequence_design.ligandmpnn_path', self.config.get('sequence_design', {}).get('ligandmpnn_path')),
            ('fixed_residues.template_pdb_dir', self.config.get('fixed_residues', {}).get('template_pdb_dir')),
        ]

        for field_name, path in paths_to_check:
            if path and not Path(path).exists():
                errors.append(f"Path does not exist: {field_name} = {path}")

        # Validate folding engine specific paths
        engine = self.config.get('folding_engine', {}).get('engine')
        if engine == 'chai':
            chai_env = self.config.get('folding_engine', {}).get('chai', {}).get('conda_env')
            if chai_env and not Path(chai_env).exists():
                errors.append(f"Chai conda env does not exist: {chai_env}")
        elif engine == 'boltz':
            boltz_env = self.config.get('folding_engine', {}).get('boltz', {}).get('conda_env')
            if boltz_env and not Path(boltz_env).exists():
                errors.append(f"Boltz conda env does not exist: {boltz_env}")

        if errors:
            raise ValueError("Configuration validation failed:\n" + "\n".join(f"  - {e}" for e in errors))

    def get(self, key: str, default: Any = None) -> Any:
        """Get config value using dot notation (e.g., 'rfd3.batch_size')."""
        keys = key.split('.')
        value = self.config
        for k in keys:
            if isinstance(value, dict):
                value = value.get(k)
            else:
                return default
        return value if value is not None else default

    def get_section(self, section: str) -> Dict[str, Any]:
        """Get entire config section."""
        return self.config.get(section, {})

    def to_dict(self) -> Dict[str, Any]:
        """Return config as dictionary."""
        return self.config


class StageCheckpoint:
    """Manage stage checkpoints to enable resumable pipeline."""

    STAGES = ['rfd3', 'mpnn', 'folding', 'analysis']

    def __init__(self, work_dir: Path):
        """Initialize checkpoint manager."""
        self.work_dir = Path(work_dir)
        self.checkpoint_dir = self.work_dir / '.checkpoints'
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    def mark_stage_complete(self, stage: str, metadata: Optional[Dict[str, Any]] = None) -> None:
        """Mark a stage as complete."""
        if stage not in self.STAGES:
            raise ValueError(f"Invalid stage: {stage}. Must be one of {self.STAGES}")

        checkpoint_file = self.checkpoint_dir / f"{stage}.checkpoint"
        checkpoint_data = {
            'stage': stage,
            'completed_at': str(Path.cwd()),
            'metadata': metadata or {}
        }

        try:
            with open(checkpoint_file, 'w') as f:
                json.dump(checkpoint_data, f, indent=2)
        except IOError as e:
            raise IOError(f"Failed to write checkpoint for stage {stage}: {e}")

    def is_stage_complete(self, stage: str) -> bool:
        """Check if a stage has been completed."""
        if stage not in self.STAGES:
            raise ValueError(f"Invalid stage: {stage}. Must be one of {self.STAGES}")

        checkpoint_file = self.checkpoint_dir / f"{stage}.checkpoint"
        return checkpoint_file.exists()

    def get_completed_stages(self) -> List[str]:
        """Get list of completed stages."""
        completed = []
        for stage in self.STAGES:
            if self.is_stage_complete(stage):
                completed.append(stage)
        return completed

    def get_next_stage(self) -> Optional[str]:
        """Get the next stage that needs to run."""
        for stage in self.STAGES:
            if not self.is_stage_complete(stage):
                return stage
        return None

    def reset_checkpoint(self, stage: str) -> None:
        """Remove checkpoint for a stage (force rerun)."""
        checkpoint_file = self.checkpoint_dir / f"{stage}.checkpoint"
        if checkpoint_file.exists():
            checkpoint_file.unlink()

    def reset_all_checkpoints(self) -> None:
        """Reset all checkpoints."""
        for stage in self.STAGES:
            self.reset_checkpoint(stage)


def load_config(config_path: str) -> ConfigLoader:
    """Load and validate configuration."""
    try:
        return ConfigLoader(config_path)
    except Exception as e:
        print(f"Error loading configuration: {e}", file=sys.stderr)
        sys.exit(1)


def setup_logging(log_dir: Path, stage: str) -> str:
    """Setup logging directory and return log file path."""
    log_dir = Path(log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)

    import datetime
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"{stage}_{timestamp}.log"

    return str(log_file)


if __name__ == "__main__":
    # Test configuration loading
    if len(sys.argv) > 1:
        try:
            config = load_config(sys.argv[1])
            print("✓ Configuration loaded successfully")
            print(f"✓ Folding engine: {config.get('folding_engine.engine')}")
            print(f"✓ Work directory: {config.get('output.work_directory')}")
        except Exception as e:
            print(f"✗ {e}")
            sys.exit(1)
    else:
        print("Usage: python3 config_utils.py <config_file.yaml>")
        sys.exit(1)
