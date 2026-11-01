#!/usr/bin/env python3
"""Build the CPU macro, then close its routed timing and antenna checks."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--run-tag", default="sky130_60ns")
args = parser.parse_args()
if not args.run_tag or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for char in args.run_tag):
    parser.error("run tag must contain only letters, digits, underscores, or hyphens")
root = Path(__file__).resolve().parents[1]
placement_tag = args.run_tag + "_placement"
for tag in (placement_tag, args.run_tag):
    if (root / "asic/runs" / tag).exists():
        parser.error(f"run {tag} already exists; choose a new tag to preserve its evidence")

subprocess.run([sys.executable, str(root / "asic/prepare.py")], cwd=root, check=True)
tool = str(root / "asic/tool.sh")
common = ["--pdk-root", "/pdk", "--jobs", os.environ.get("OPENLANE_JOBS", "6")]

# Map and place at a tighter clock before closing the final interface contract.
subprocess.run([
    tool, "python3", "-m", "openlane", *common,
    "--run-tag", placement_tag, "--to", "OpenROAD.ResizerTimingPostGRT",
    "-c", "CLOCK_PERIOD=40", "-c", "GRT_RESIZER_SETUP_SLACK_MARGIN=1.0",
    "-c", "GRT_ADJUSTMENT=0.3", "-c", "GRT_OVERFLOW_ITERS=50",
    "/work/asic/config.json",
], cwd=root, check=True)
checkpoints = list((root / "asic/runs" / placement_tag).glob(
    "*-openroad-resizertimingpostgrt/state_out.json"))
if len(checkpoints) != 1:
    raise SystemExit("Expected one completed placement/timing checkpoint")
checkpoint = Path("/work") / checkpoints[0].relative_to(root)
subprocess.run([
    tool, "python3", "/work/asic/flow.py", *common, "--flow", "CoreASIC",
    "--run-tag", args.run_tag, "--from", "Core.TimingClosure",
    "--to", "OpenROAD.STAPostPNR",
    "-c", "GRT_ADJUSTMENT=0.3", "-c", "GRT_OVERFLOW_ITERS=50",
    "-i", str(checkpoint), "/work/asic/config.json",
], cwd=root, check=True)
run = root / "asic/runs" / args.run_tag
closure_flows = ("CoreECO", "CoreElectrical", "CoreTargeted", "CoreGuarded",
                 "CoreLocal", "CoreLocal", "CoreLocal")
for attempt, closure_flow in enumerate(closure_flows):
    sta_steps = sorted(run.glob("*-openroad-stapostpnr/state_out.json"),
                       key=lambda path: int(path.parent.name.split("-", 1)[0]))
    checkpoint = Path("/work") / sta_steps[-1].relative_to(root)
    result = subprocess.run([
        tool, "python3", "/work/asic/flow.py", *common, "--flow",
        closure_flow,
        "--run-tag", args.run_tag, "-i", str(checkpoint), "/work/asic/config.json",
    ], cwd=root)
    if result.returncode == 0:
        check = subprocess.run([
            sys.executable, str(root / "asic/check_signoff.py"), str(run),
            str(root / "build/asic" / (args.run_tag + "-signoff.json")),
        ], cwd=root)
        if check.returncode == 0:
            break
    newer_sta = list(run.glob("*-openroad-stapostpnr/state_out.json"))
    if len(newer_sta) == len(sta_steps) or attempt == len(closure_flows) - 1:
        raise SystemExit("Physical closure failed; inspect the retained reports")
