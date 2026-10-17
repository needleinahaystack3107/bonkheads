"""Shared helpers for the Bonkheads static analysis.

Every script under tools/ imports from here so each format is parsed in one
place only:
  pe       - PE32 resource directory reader (no execution, bytes only)
  levels   - original BKMP/ENDT/BOSS/MLST level resources
  sprites  - original bitmap resources in Data.exe
"""
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEMO = REPO / "original-demo"  # git-ignored; the user's own copy


def demo_file(name: str) -> Path:
    path = DEMO / name
    if not path.exists():
        raise SystemExit(f"missing {path} (original files are not in the repo)")
    return path
