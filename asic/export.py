#!/usr/bin/env python3
"""Export compact layout deliverables and reports only after clean signoff."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
run = args.run.resolve()
output = args.output.resolve()
if output.exists() and any(output.iterdir()):
    raise SystemExit("Output directory is not empty; choose a new directory to preserve its evidence")
output.mkdir(parents=True, exist_ok=True)
subprocess.run([
    sys.executable, str(root / "asic/check_signoff.py"), str(run),
    str(output / "signoff.json"),
], check=True)
validation_path = root / "build/asic" / (run.name + "-gates") / "validation.json"
validation = json.loads(validation_path.read_text())
netlist_hash = hashlib.sha256((run / "final/nl/rv32_core.nl.v").read_bytes()).hexdigest()
if validation["netlist_sha256"] != netlist_hash or not validation["kernel_trace_matches_reference"]:
    raise SystemExit("Final netlist needs a passing gate regression and matching kernel trace")
shutil.copyfile(validation_path, output / "validation.json")


def latest_step(suffix):
    steps = sorted(
        (path for path in run.glob("*-" + suffix)
         if (path / "state_out.json").exists()),
        key=lambda path: int(path.name.split("-", 1)[0]),
    )
    if not steps:
        raise SystemExit(f"Missing completed step: {suffix}")
    return steps[-1]


def compressed(source, destination):
    with source.open("rb") as stream, destination.open("wb") as raw:
        with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as target:
            shutil.copyfileobj(stream, target)


for view in ("gds/rv32_core.gds", "lef/rv32_core.lef", "nl/rv32_core.nl.v",
             "pnl/rv32_core.pnl.v"):
    source = run / "final" / view
    compressed(source, output / (source.name + ".gz"))
shutil.copyfile(root / "asic/constraints.sdc", output / "constraints.sdc")
shutil.copyfile(run / "final/sdc/rv32_core.sdc", output / "rv32_core.sdc")
shutil.copyfile(run / "final/metrics.json", output / "metrics.json")
shutil.copyfile(run / "resolved.json", output / "resolved.json")

sources = json.loads((root / "build/asic/sources.json").read_text())
for name, expected in sources["sources"].items():
    actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit(f"RTL changed since conversion: {name}")
shutil.copyfile(root / "build/asic/sources.json", output / "sources.json")
flow_sources = {}
for pattern in ("*.py", "*.sh", "*.tcl", "*.sdc", "config.json"):
    for path in sorted((root / "asic").glob(pattern)):
        flow_sources[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
(output / "flow-sources.json").write_text(json.dumps(flow_sources, indent=2) + "\n")

reports = output / "reports"
reports.mkdir(exist_ok=True)
regression_log = validation_path.with_name("regression.log")
if hashlib.sha256(regression_log.read_bytes()).hexdigest() != validation["regression_log_sha256"]:
    raise SystemExit("Gate regression log differs from validation evidence")
compressed(regression_log, reports / "gate-regression.txt.gz")
routes = [path for path in run.iterdir() if path.is_dir()
          and (path / "state_out.json").exists()
          and (path / "rv32_core.drc").is_file()]
route = max(routes, key=lambda path: int(path.name.split("-", 1)[0]))
compressed(route / "rv32_core.drc", reports / "detailed-route.drc.gz")
compressed(route / "or_metrics_out.json", reports / "routing-metrics.json.gz")
for log in sorted(route.glob("*.log")):
    compressed(log, reports / (log.stem + ".txt.gz"))
sta = latest_step("openroad-stapostpnr")
config = json.loads((run / "resolved.json").read_text())
timing_models = output / "lib"
timing_models.mkdir()
for corner in config["STA_CORNERS"]:
    compressed(sta / corner / "checks.rpt", reports / (corner + ".txt.gz"))
    model = sta / corner / (config["DESIGN_NAME"] + "__" + corner + ".lib")
    compressed(model, timing_models / (model.name + ".gz"))
for suffix in ("magic-drc", "klayout-drc", "magic-spiceextraction", "netgen-lvs", "openroad-checkantennas",
               "openroad-irdropreport", "odb-reportdisconnectedpins", "klayout-xor"):
    # OpenLane numbers repeated step identifiers with a trailing suffix.
    candidates = [path for path in run.iterdir()
                  if path.is_dir() and path.name.split("-", 1)[-1].startswith(suffix)
                  and (path / "state_out.json").exists()]
    if not candidates:
        raise SystemExit(f"Missing physical check: {suffix}")
    step = max(candidates, key=lambda path: int(path.name.split("-", 1)[0]))
    for log in sorted(step.glob("*.log")):
        compressed(log, reports / (log.stem + ".txt.gz"))
    for report in sorted((step / "reports").glob("*")):
        if report.is_file():
            compressed(report, reports / (suffix + "-" + report.stem + ".txt.gz"))
    for report in sorted(step.glob("*.rpt")):
        compressed(report, reports / (suffix + "-" + report.stem + ".txt.gz"))
extraction = latest_step("magic-spiceextraction")
compressed(extraction / "feedback.txt", reports / "gds-extraction-feedback.txt.gz")

manifest = {}
for path in sorted(output.rglob("*")):
    if path.is_file() and path.name != "SHA256SUMS":
        manifest[str(path.relative_to(output))] = hashlib.sha256(path.read_bytes()).hexdigest()
(output / "SHA256SUMS").write_text("".join(
    f"{digest}  {name}\n" for name, digest in manifest.items()))
print(f"Exported signed-off views and evidence to {output}")
