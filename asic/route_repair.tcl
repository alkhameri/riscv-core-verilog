# Rebuild signal routing after resizing. Incremental routing in the pinned
# OpenROAD version asserts on this design after placement changes.
foreach net [$::block getNets] {
    if {![$net isSpecial] && [$net getWire] != "NULL"} {
        odb::dbWire_destroy [$net getWire]
    }
}
pin_access -bottom_routing_layer $::env(RT_MIN_LAYER) \
    -top_routing_layer $::env(RT_MAX_LAYER)
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl

set diode [lindex [split $::env(DIODE_CELL) /] 0]
repair_antennas $diode -iterations 10 -ratio_margin 20
# Diode legalization can move neighboring cells. Refresh every guide before
# detailed routing, then repair the remaining antennas on actual wires below.
pin_access -bottom_routing_layer $::env(RT_MIN_LAYER) \
    -top_routing_layer $::env(RT_MAX_LAYER)
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl
write_db $::env(STEP_DIR)/before_detailed.odb
detailed_route -bottom_routing_layer $::env(RT_MIN_LAYER) \
    -top_routing_layer $::env(RT_MAX_LAYER) \
    -output_drc $::env(STEP_DIR)/rv32_core.drc -drc_report_iter_step 5 \
    -droute_end_iter 64 -or_seed 42 -verbose 1
write_db $::env(STEP_DIR)/after_detailed.odb
write_verilog $::env(STEP_DIR)/after_detailed.v
for {set iteration 0} {$iteration < 5 && [check_antennas]} {incr iteration} {
    repair_antennas $diode -iterations 1 -ratio_margin 20
    detailed_route -bottom_routing_layer $::env(RT_MIN_LAYER) \
        -top_routing_layer $::env(RT_MAX_LAYER) \
        -output_drc $::env(STEP_DIR)/rv32_core.drc -drc_report_iter_step 5 \
        -droute_end_iter 64 -or_seed 42 -verbose 1
    write_db $::env(STEP_DIR)/after_antenna_${iteration}.odb
}
check_placement -verbose
write_views
