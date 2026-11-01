#!/usr/bin/env python3
"""Run the independent instruction model and firmware against a mapped netlist."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run", type=Path, help="OpenLane run directory")
parser.add_argument("--netlist", type=Path, help="Check a specific stage netlist before export")
parser.add_argument("--kernel", action="store_true", help="Also boot build/kernel/kernel.elf")
parser.add_argument("--reference-trace", type=Path, help="Require an identical kernel retirement trace")
args = parser.parse_args()
if args.reference_trace and not args.kernel:
    parser.error("--reference-trace requires --kernel")
root = Path(__file__).resolve().parents[1]
run = args.run.resolve()
config = json.loads((run / "resolved.json").read_text())
netlist = args.netlist.resolve() if args.netlist else run / "final/nl/rv32_core.nl.v"
build = root / "build/asic" / (run.name + "-gates")
build.mkdir(parents=True, exist_ok=True)
validation = build / "validation.json"
validation.unlink(missing_ok=True)
models = build / "cells.v"
container_models = Path("/work") / models.relative_to(root)
libraries = config["LIB"]["*_tt_025C_1v80"]
# Use the same cell functions as synthesis and STA. The PDK UDP models give
# incorrect sequential results in Verilator 5.052; Liberty-derived flops use
# ordinary nonblocking assignments. This checks functionality, not SDF delays.
commands = [f"read_liberty -ignore_miss_func -ignore_miss_dir {json.dumps(p)}" for p in libraries]
commands.append(f"write_verilog -noattr {json.dumps(str(container_models))}")
subprocess.run([
    str(root / "asic/tool.sh"), "yosys", "-Q", "-p", "; ".join(commands),
], cwd=root, check=True)
subprocess.run([
    str(root / "asic/tool.sh"), "python3", "/work/asic/physical_models.py",
    str(Path("/work") / (run / "resolved.json").relative_to(root)),
    str(container_models), str(Path("/work") / netlist.relative_to(root)),
], cwd=root, check=True)
subprocess.run([
    "verilator", "--cc", "--exe", "--build", "-j", "4",
    # Yosys leaves the unused output of each two-output tie cell disconnected.
    "-Wno-PINMISSING", "--top-module", "rv32_core",
    str(models), str(netlist), str(root / "sim/core_sim.cpp"),
    "--Mdir", str(build), "-CFLAGS", "-std=c++17 -O2",
], cwd=root, check=True)
simulator = str(build / "Vrv32_core")
regression_log = build / "regression.log"
regression_log.write_text("Netlist SHA-256: " + hashlib.sha256(netlist.read_bytes()).hexdigest() + "\n")


def run_check(arguments):
    result = subprocess.run(arguments, cwd=root, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    with regression_log.open("a") as stream:
        command = " ".join(str(arg).replace(str(root) + "/", "") for arg in arguments)
        stream.write("\nCommand: " + command + "\n" + result.stdout)
    print(result.stdout, end="", flush=True)
    result.check_returncode()


run_check([simulator, "--self-test"])
for seed in (1, 71):
    run_check([
        simulator, "--elf", "build/tests.elf", "--seed", str(seed),
        "--max-cycles", "2000000",
    ])
if args.kernel:
    run_check([
        simulator, "--elf", "build/kernel/kernel.elf", "--kernel",
        "--trace", str(build / "kernel.trace"),
    ])
    if args.reference_trace:
        if args.reference_trace.read_bytes() != (build / "kernel.trace").read_bytes():
            raise SystemExit("FAIL: kernel retirement trace differs from reference")
        print("PASS: kernel retirement trace matches reference exactly")
        with regression_log.open("a") as stream:
            stream.write("PASS: kernel retirement trace matches reference exactly\n")

evidence = {
    "netlist_sha256": hashlib.sha256(netlist.read_bytes()).hexdigest(),
    "cell_models_sha256": hashlib.sha256(models.read_bytes()).hexdigest(),
    "regression_log_sha256": hashlib.sha256(regression_log.read_bytes()).hexdigest(),
    "instruction_model_sha256": hashlib.sha256((root / "sim/core_sim.cpp").read_bytes()).hexdigest(),
    "verilator": subprocess.check_output(["verilator", "--version"], text=True).strip(),
    "instruction_model_self_tests_passed": True,
    "firmware_seeds_passed": [1, 71],
    "firmware_elf_sha256": hashlib.sha256((root / "build/tests.elf").read_bytes()).hexdigest(),
    "kernel_passed": args.kernel,
    "kernel_trace_matches_reference": bool(args.kernel and args.reference_trace),
}
if args.kernel:
    evidence["kernel_elf_sha256"] = hashlib.sha256((root / "build/kernel/kernel.elf").read_bytes()).hexdigest()
    evidence["kernel_trace_sha256"] = hashlib.sha256((build / "kernel.trace").read_bytes()).hexdigest()
validation.write_text(json.dumps(evidence, indent=2) + "\n")
print(f"Wrote functional validation evidence: {validation}")
