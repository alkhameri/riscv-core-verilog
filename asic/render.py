#!/usr/bin/env python3
"""Render the actual final GDS with KLayout's layout viewer, inside tool.sh."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import pya

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run", type=Path, help="Completed OpenLane run directory")
parser.add_argument("output", type=Path, help="PNG output path")
parser.add_argument("--size", type=int, default=2400)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
subprocess.run([
    sys.executable, str(root / "asic/check_signoff.py"), str(args.run),
    str(root / "build/asic" / (args.run.name + "-signoff.json")),
], check=True)
config = json.loads((args.run / "resolved.json").read_text())
gds = args.run / "final/gds" / (config["DESIGN_NAME"] + ".gds")
view = pya.LayoutView()
view.set_config("background-color", "#ffffff")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
view.load_layout(str(gds))
view.load_layer_props(config["KLAYOUT_PROPERTIES"])
# Show actual interconnect drawing layers with a subdued palette. Pin markers,
# labels, and cell-boundary overlays obscure the full-macro view.
colors = {67: 0xE6E8EB, 68: 0xBBC8D4, 69: 0x93A8BD,
          70: 0x278D94, 71: 0xB18145, 72: 0x55477D}
for layer in view.each_layer():
    layer.visible = layer.source_datatype == 20 and layer.source_layer in colors
    if layer.visible:
        layer.fill_color = colors[layer.source_layer]
        layer.frame_color = colors[layer.source_layer]
        layer.dither_pattern = 0
view.max_hier()
view.zoom_fit()
args.output.parent.mkdir(parents=True, exist_ok=True)
pixels = view.get_pixels_with_options(args.size, args.size, 0, 3, 0, pya.DBox())
args.output.write_bytes(pixels.to_png_data())
print(f"Rendered {gds} with KLayout {pya.__version__}: {args.output}")
