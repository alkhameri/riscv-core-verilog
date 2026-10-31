#!/usr/bin/env python3
"""Copy a pinned upstream checkout and apply the explicit DE10-Lite port."""
import argparse
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
if args.destination.exists():
    parser.error("destination already exists; choose a fresh build directory")
shutil.copytree(args.source, args.destination, ignore=shutil.ignore_patterns(".git", "*.o", "kernel.elf"))
patch = Path(__file__).resolve().parents[1] / "ports/rv32-microkernel-de10.patch"
subprocess.run(["patch", "--batch", "-p1", "-i", str(patch)], cwd=args.destination, check=True)
