#!/usr/bin/env python3
"""Add models only for configured physical cells with no LEF signal pins."""
import fnmatch
import json
from pathlib import Path
import re
import sys

config_path, models_path, netlist_path = map(Path, sys.argv[1:])
config = json.loads(config_path.read_text())
models = models_path.read_text()
declared = set(re.findall(r"^module\s+(\w+)\s*\(", models, re.M))
used = set(re.findall(r"^\s+(sky130_\w+)\s+\S+\s*\(", netlist_path.read_text(), re.M))
missing = used - declared
patterns = [config["WELLTAP_CELL"], config["ENDCAP_CELL"],
            *config["FILL_CELL"], *config["DECAP_CELL"]]
lef_text = "\n".join(Path(path).read_text() for path in config["CELL_LEFS"])
for cell in sorted(missing):
    if not any(fnmatch.fnmatchcase(cell, pattern) for pattern in patterns):
        raise SystemExit(f"Missing functional model: {cell}")
    match = re.search(r"^MACRO\s+" + re.escape(cell) + r"\s*$\n(.*?)^END\s+"
                      + re.escape(cell) + r"\s*$", lef_text, re.M | re.S)
    if not match:
        raise SystemExit(f"Missing physical-cell LEF: {cell}")
    for pin in re.findall(r"^\s+PIN\s+(\S+)", match[1], re.M):
        block = re.search(r"\bPIN\s+" + re.escape(pin) + r"\s+(.*?)\bEND\s+"
                          + re.escape(pin) + r"\b", match[1], re.S)
        if not block or not re.search(r"\bUSE\s+(POWER|GROUND)\s*;", block[1]):
            raise SystemExit(f"Physical cell unexpectedly has a signal pin: {cell}/{pin}")
    models += f"\n// LEF-checked physical cell with no signal pins.\nmodule {cell}(); endmodule\n"
    print(f"Added power-only physical model: {cell}")
models_path.write_text(models)
