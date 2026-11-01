# The first extracted layout exposed capacitance and interface hold violations.
# Use pessimistic routing estimates for optimization; signoff still uses the
# original PDK extraction decks and the interface contract in constraints.sdc.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/resizer.tcl
load_rsz_corners
read_current_odb
set_propagated_clock [all_clocks]
set_dont_touch_objects
source /work/asic/input_delay.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl

# Set per-corner RC values without changing the technology in the saved ODB.
foreach layer [$::tech getLayers] {
    if {[$layer getRoutingLevel] == 0} { continue }
    lassign [rsz::dblayer_wire_rc $layer] resistance capacitance
    foreach corner [sta::corners] {
        rsz::set_layer_rc_cmd $layer $corner \
            [expr {$resistance * 1.3}] [expr {$capacitance * 2.0}]
    }
}
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl
estimate_parasitics -global_routing
repair_design -verbose -slew_margin 20 -cap_margin 20

repair_timing -setup -verbose \
    -setup_margin $::env(GRT_RESIZER_SETUP_SLACK_MARGIN) \
    -max_buffer_percent $::env(GRT_RESIZER_SETUP_MAX_BUFFER_PCT)

# The input delay chains provide shared hold margin. Repair any remaining
# individual paths using the same input delays as signoff.
repair_timing -hold -verbose \
    -setup_margin $::env(GRT_RESIZER_SETUP_SLACK_MARGIN) \
    -hold_margin $::env(GRT_RESIZER_HOLD_SLACK_MARGIN) \
    -max_buffer_percent $::env(GRT_RESIZER_HOLD_MAX_BUFFER_PCT)

source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
unset_dont_touch_objects
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl
unset_dont_touch [get_cells CORE_INPUT_DELAY_*]
write_views
