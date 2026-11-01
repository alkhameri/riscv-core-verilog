#!/usr/bin/env python3
"""OpenLane Classic with antenna repair after the last full global route."""

from pathlib import Path
import fnmatch

from openlane.flows import Flow
from openlane.flows.classic import Classic
from openlane.state import DesignFormat
from openlane.steps import OpenROAD, Step, Odb, Checker, Magic
from openlane.common import TclUtils


@Step.factory.register()
class TimingClosure(OpenROAD.ResizerTimingPostGRT):
    id = "Core.TimingClosure"
    name = "Electrical and interface timing repair with routing margin"

    def get_script_path(self):
        return str(Path(__file__).with_name("timing_repair.tcl"))


@Step.factory.register()
class FinalAntennaRepair(OpenROAD.GlobalRouting):
    id = "Core.FinalAntennaRepair"
    name = "Preserve antenna repairs before detailed routing"
    outputs = [DesignFormat.ODB, DesignFormat.DEF, DesignFormat.NETLIST,
               DesignFormat.POWERED_NETLIST, DesignFormat.SDC]

    def get_script_path(self):
        return str(Path(__file__).with_name("antenna_repair.tcl"))


@Step.factory.register()
class ConnectInputPower(FinalAntennaRepair):
    id = "Core.ConnectInputPower"
    name = "Connect supplies on protected input delay cells"

    def get_script_path(self):
        return str(Path(__file__).with_name("connect_input_power.tcl"))


@Step.factory.register()
class ExtractedRepair(OpenROAD.ResizerTimingPostGRT):
    id = "Core.ExtractedRepair"
    name = "Repair extracted electrical, timing, and antenna violations"
    inputs = OpenROAD.ResizerTimingPostGRT.inputs + [DesignFormat.SPEF]

    def get_script_path(self):
        return str(Path(__file__).with_name("extracted_repair.tcl"))

    def run(self, state_in, **kwargs):
        # This OpenSTA version cannot reread the same named Liberty library for
        # different RC corners. Optimize the three unique PVT libraries using
        # maximum extracted RC; final STA still checks all nine combinations.
        corners = [corner for corner in self.config["STA_CORNERS"]
                   if corner.startswith("max_")]
        libraries = ["define_corners " + TclUtils.join(corners)]
        parasitics = []
        for corner in corners:
            _, libs, _, _ = self.toolbox.get_timing_files_categorized(self.config, corner)
            for lib in libs:
                libraries.append(TclUtils.join(["read_liberty", "-corner", corner, str(lib)]))
            matches = [path for pattern, path in state_in[DesignFormat.SPEF].items()
                       if fnmatch.fnmatchcase(corner, pattern)]
            if len(matches) != 1:
                raise ValueError(f"Expected one extracted SPEF for {corner}")
            parasitics.append(TclUtils.join(["read_spef", "-corner", corner, str(matches[0])]))
        Path(self.step_dir, "libraries.tcl").write_text("\n".join(libraries) + "\n")
        Path(self.step_dir, "parasitics.tcl").write_text("\n".join(parasitics) + "\n")
        return super().run(state_in, **kwargs)


class LocalGDSExtraction(Magic.SpiceExtraction):
    # Keep the standard step identifier and reports for OpenLane's checkers.
    name = "Extract delivered GDS using local scratch storage"

    def get_script_path(self):
        return str(Path(__file__).with_name("extract_gds.tcl"))


@Flow.factory.register()
class CoreASIC(Classic):
    Steps = []
    for step in Classic.Steps:
        if step is OpenROAD.RepairAntennas:
            continue
        if step is OpenROAD.ResizerTimingPostGRT:
            step = TimingClosure
        if step is Magic.SpiceExtraction:
            step = LocalGDSExtraction
        if step is OpenROAD.DetailedRouting:
            Steps.extend([FinalAntennaRepair, OpenROAD.CheckAntennas])
        Steps.append(step)
        if step is OpenROAD.DetailedRouting:
            Steps.append(ConnectInputPower)


@Flow.factory.register()
class CoreECO(Classic):
    Steps = [ExtractedRepair, OpenROAD.CheckAntennas, Checker.TrDRC,
             Odb.ReportDisconnectedPins, Checker.DisconnectedPins,
             OpenROAD.FillInsertion, OpenROAD.RCX, OpenROAD.STAPostPNR]
    Steps += [LocalGDSExtraction if step is Magic.SpiceExtraction else step
              for step in Classic.Steps[Classic.Steps.index(OpenROAD.IRDropReport):]]


@Step.factory.register()
class RouteRepair(FinalAntennaRepair):
    id = "Core.RouteRepair"
    name = "Route a saved timing-repair checkpoint"

    def get_script_path(self):
        return str(Path(__file__).with_name("route_only.tcl"))


@Flow.factory.register()
class CoreRoute(CoreECO):
    Steps = [RouteRepair, *CoreECO.Steps[1:]]


@Step.factory.register()
class ExtractedSizing(ExtractedRepair):
    id = "Core.ExtractedSizing"
    name = "Size overloaded drivers using extracted capacitance"

    def get_script_path(self):
        return str(Path(__file__).with_name("resize_extracted.tcl"))


@Step.factory.register()
class EstimatedRepair(ExtractedRepair):
    id = "Core.EstimatedRepair"
    name = "Buffer long nets with conservative placement estimates"

    def get_script_path(self):
        return str(Path(__file__).with_name("repair_estimated.tcl"))


@Step.factory.register()
class ElectricalFinish(ExtractedRepair):
    id = "Core.ElectricalFinish"
    name = "Finish input buffering and electrical sizing"

    def get_script_path(self):
        return str(Path(__file__).with_name("finish_electrical.tcl"))


@Flow.factory.register()
class CoreElectrical(CoreECO):
    # Separate processes keep estimated Pi models out of extracted analysis.
    Steps = [ExtractedSizing, EstimatedRepair, ElectricalFinish, RouteRepair,
             *CoreECO.Steps[1:]]


@Step.factory.register()
class TargetedRepair(ExtractedRepair):
    id = "Core.TargetedRepair"
    name = "Repair the remaining extracted electrical drivers"

    def get_script_path(self):
        return str(Path(__file__).with_name("targeted_repair.tcl"))


@Step.factory.register()
class TargetedFinish(ExtractedRepair):
    id = "Core.TargetedFinish"
    name = "Size repaired nets and restore hold margin"

    def get_script_path(self):
        return str(Path(__file__).with_name("targeted_finish.tcl"))


@Flow.factory.register()
class CoreTargeted(CoreECO):
    Steps = [TargetedRepair, TargetedFinish, RouteRepair, *CoreECO.Steps[1:]]


@Step.factory.register()
class GuardedRepair(TargetedRepair):
    id = "Core.GuardedRepair"
    name = "Add electrical margin for routing variation"

    def get_script_path(self):
        return str(Path(__file__).with_name("guarded_repair.tcl"))


@Step.factory.register()
class GuardedFinish(TargetedFinish):
    id = "Core.GuardedFinish"
    name = "Finish buffering with electrical routing margin"

    def get_script_path(self):
        return str(Path(__file__).with_name("guarded_finish.tcl"))


@Flow.factory.register()
class CoreGuarded(CoreECO):
    Steps = [GuardedRepair, GuardedFinish, RouteRepair, *CoreECO.Steps[1:]]


@Step.factory.register()
class LocalRepair(ExtractedRepair):
    id = "Core.LocalRepair"
    name = "Repair remaining electrical nets without disturbing placed cells"

    def get_script_path(self):
        return str(Path(__file__).with_name("local_repair.tcl"))


@Flow.factory.register()
class CoreLocal(CoreECO):
    Steps = [LocalRepair, *CoreECO.Steps[1:]]


if __name__ == "__main__":
    from openlane.__main__ import cli

    cli()
