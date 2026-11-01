#!/usr/bin/env python3
"""Check final OpenLane metrics and retain a compact, auditable summary."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
repo_root = Path(__file__).resolve().parents[1]
config = json.loads((args.run / "resolved.json").read_text())
metrics = json.loads((args.run / "final/metrics.json").read_text())
errors = []
if config.get("MAGIC_EXT_USE_GDS") is not True:
    errors.append("LVS must extract from the delivered GDS")

checks = (
    "design__instance_unmapped__count",
    "synthesis__check_error__count",
    "design__lint_error__count",
    "design__lint_warning__count",
    "route__drc_errors",
    "magic__drc_error__count",
    "klayout__drc_error__count",
    "magic__illegal_overlap__count",
    "design__critical_disconnected_pin__count",
    "design__power_grid_violation__count",
    "design__xor_difference__count",
    "design__lvs_error__count",
    "route__antenna_violation__count",
    "timing__unannotated_net_filtered__count",
)
for key in checks:
    if metrics.get(key) != 0:
        errors.append(f"{key}: expected 0, got {metrics.get(key)!r}")

ir_drop = {}
for net in config["VDD_NETS"] + config["GND_NETS"]:
    value = metrics.get(f"design_powergrid__drop__worst__net:{net}")
    ir_drop[net] = value
    if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        errors.append(f"Missing or invalid static IR-drop estimate for {net}")
if all(isinstance(value, (int, float)) and math.isfinite(value)
       for value in ir_drop.values()):
    if sum(ir_drop.values()) > 0.05 * float(config["VDD_PIN_VOLTAGE"]):
        errors.append("Combined static supply and ground drop exceeds 5 percent")

# Read the router's own output as well as the accumulated flow metrics.
route_steps = sorted(
    (path for path in args.run.iterdir() if path.is_dir()
     and (path / "state_out.json").exists()
     and (path / "rv32_core.drc").is_file()),
    key=lambda path: int(path.name.split("-", 1)[0]),
)
if not route_steps:
    errors.append("Missing completed detailed-routing report")
else:
    route = route_steps[-1]
    route_metrics = json.loads((route / "or_metrics_out.json").read_text())
    if route_metrics.get("route__drc_errors") != 0:
        errors.append("Latest detailed route did not report zero DRC errors")
    if (route / "rv32_core.drc").read_text().strip():
        errors.append("Latest detailed-routing DRC report is not empty")

sta_runs = sorted(
    (path for path in args.run.glob("*-openroad-stapostpnr")
     if (path / "state_out.json").exists()),
    key=lambda path: int(path.name.split("-", 1)[0]),
)
if not sta_runs:
    raise SystemExit("Missing completed extracted STA step")
sta_run = sta_runs[-1]
sta_metrics = json.loads((sta_run / "state_out.json").read_text())["metrics"]
for view in ("gds/rv32_core.gds", "lef/rv32_core.lef", "nl/rv32_core.nl.v",
             "sdc/rv32_core.sdc"):
    if not (args.run / "final" / view).is_file():
        errors.append(f"Missing final view: {view}")
extractions = sorted(
    (path for path in args.run.glob("*-magic-spiceextraction")
     if (path / "state_out.json").exists()),
    key=lambda path: int(path.name.split("-", 1)[0]),
)
if not extractions:
    errors.append("Missing completed GDS extraction")
else:
    extraction = extractions[-1]
    extraction_config = json.loads((extraction / "config.json").read_text())
    if extraction_config.get("MAGIC_EXT_USE_GDS") is not True:
        errors.append("The completed LVS extraction used DEF instead of GDS")
    input_gds = json.loads((extraction / "state_in.json").read_text())["gds"]
    input_gds = repo_root / Path(input_gds).relative_to("/work")
    final_gds = args.run / "final/gds/rv32_core.gds"
    if final_gds.is_file() and hashlib.sha256(input_gds.read_bytes()).digest() != hashlib.sha256(final_gds.read_bytes()).digest():
        errors.append("Delivered GDS differs from the LVS extraction input")
    lvs_steps = sorted(
        (path for path in args.run.glob("*-netgen-lvs") if (path / "state_out.json").exists()),
        key=lambda path: int(path.name.split("-", 1)[0]),
    )
    if not lvs_steps:
        errors.append("Missing completed Netgen LVS")
    else:
        lvs_input = json.loads((lvs_steps[-1] / "state_in.json").read_text())
        extracted_spice = json.loads((extraction / "state_out.json").read_text())["spice"]
        if lvs_input["spice"] != extracted_spice:
            errors.append("LVS did not use the latest GDS extraction")
        lvs_netlist = repo_root / Path(lvs_input["pnl"]).relative_to("/work")
        final_netlist = args.run / "final/pnl/rv32_core.pnl.v"
        if not final_netlist.is_file() or hashlib.sha256(lvs_netlist.read_bytes()).digest() != hashlib.sha256(final_netlist.read_bytes()).digest():
            errors.append("Delivered powered netlist differs from the LVS input")
constant_outputs = {f"trace_cause[{bit}]" for bit in range(4, 31)}
constant_outputs.update(("dmem_request_address[0]", "dmem_request_address[1]"))
corners = {}
for corner in config["STA_CORNERS"]:
    result = {}
    for key in (
        "timing__setup_vio__count", "timing__hold_vio__count",
        "design__max_slew_violation__count", "design__max_cap_violation__count",
    ):
        value = metrics.get(f"{key}__corner:{corner}")
        if value != sta_metrics.get(f"{key}__corner:{corner}"):
            errors.append(f"{corner}: final metrics differ from extracted STA")
        result[key] = value
        if value != 0:
            errors.append(f"{corner}: {key} is {value!r}")
    for key in ("timing__setup__ws", "timing__hold__ws"):
        value = metrics.get(f"{key}__corner:{corner}")
        result[key] = value
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            errors.append(f"{corner}: invalid slack {key}={value!r}")

    report = (sta_run / corner / "checks.rpt").read_text()
    if "check_setup -verbose" not in report:
        errors.append(f"{corner}: missing timing-constraint checks")
    setup_checks = report.split("check_setup -verbose", 1)[-1]
    warnings = [line for line in setup_checks.splitlines() if line.startswith("Warning:")]
    allowed_warning = r"Warning: There are (\d+) unconstrained endpoints\."
    for warning in warnings:
        if not re.fullmatch(allowed_warning, warning):
            errors.append(f"{corner}: {warning}")
    match = re.search(allowed_warning + r"\n((?:  [^\n]+\n)*)", setup_checks)
    endpoints = set(match[2].split()) if match else set()
    if match and len(endpoints) != int(match[1]):
        errors.append(f"{corner}: could not parse every unconstrained endpoint")
    if endpoints - constant_outputs:
        errors.append(f"{corner}: unexpected unconstrained endpoints {sorted(endpoints - constant_outputs)}")
    result["constant_output_warnings"] = sorted(endpoints)
    corners[corner] = result

if errors:
    raise SystemExit("Signoff check failed:\n" + "\n".join(errors))
summary = {
    "design": config["DESIGN_NAME"],
    "pdk": config["PDK"],
    "standard_cell_library": config["STD_CELL_LIBRARY"],
    "clock_period_ns": config["CLOCK_PERIOD"],
    "clock_frequency_mhz": 1000 / config["CLOCK_PERIOD"],
    "die_area_um2": metrics["design__die__area"],
    "worst_setup_slack_ns": min(c["timing__setup__ws"] for c in corners.values()),
    "worst_hold_slack_ns": min(c["timing__hold__ws"] for c in corners.values()),
    "estimated_static_ir_drop_v": ir_drop,
    "checks": {key: metrics[key] for key in checks},
    "corners": corners,
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n")
print(f"PASS: physical checks and timing at all {len(corners)} corners; wrote {args.output}")
