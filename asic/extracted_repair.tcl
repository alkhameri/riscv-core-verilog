# Optimize all three PVT libraries with maximum extracted wire RC.
# Final static timing still checks all nine RC/PVT combinations.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(STEP_DIR)/libraries.tcl
read_current_odb
set_propagated_clock [all_clocks]
remove_fillers
unset_dont_touch [get_cells CORE_INPUT_DELAY_*]
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_routing_layers.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_layer_adjustments.tcl
set_thread_count 6
# Loading estimated Pi models before SPEF makes this OpenROAD version retain
# those estimates. Read extracted parasitics into a clean timing database.
# Modified nets are routed and extracted again before any signoff decision.
source $::env(STEP_DIR)/parasitics.tcl

report_worst_slack -max
report_worst_slack -min
repair_design -verbose -slew_margin 40 -cap_margin 40
repair_timing -setup -verbose -setup_margin 1.0 -max_buffer_percent 20
repair_timing -hold -verbose -setup_margin 0.1 -hold_margin 0.25 -max_buffer_percent 20
set ::env(PL_OPTIMIZE_MIRRORING) 0
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
source /work/asic/spread_combinational.tcl
write_db $::env(STEP_DIR)/after_timing.odb
write_verilog $::env(STEP_DIR)/after_timing.v

source /work/asic/route_repair.tcl
