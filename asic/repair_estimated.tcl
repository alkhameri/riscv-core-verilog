# Start in a fresh process so placement estimates cannot contaminate the
# preceding extracted analysis. Final signoff uses freshly extracted SPEFs.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(STEP_DIR)/libraries.tcl
read_current_odb
set_propagated_clock [all_clocks]
remove_fillers
unset_dont_touch [get_cells CORE_INPUT_DELAY_*]
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
set_thread_count 3
foreach corner [sta::corners] {
    set resistance [expr {[rsz::wire_signal_resistance $corner] * 1.3}]
    set capacitance [expr {[rsz::wire_signal_capacitance $corner] * 2.0}]
    rsz::set_h_wire_signal_rc_cmd $corner $resistance $capacitance
    rsz::set_v_wire_signal_rc_cmd $corner $resistance $capacitance
}
# Antenna diodes add capacitive loads but do not justify fanout-only buffers.
# The original fanout target is restored after electrical optimization.
set_max_fanout 1000 [current_design]
for {set iteration 0} {$iteration < 4} {incr iteration} {
    estimate_parasitics -placement
    repair_design -verbose -slew_margin 30 -cap_margin 30
    report_check_types -max_slew -max_cap -violators -digits 6 > $::env(STEP_DIR)/electrical_${iteration}.rpt
    report_worst_slack -max
    report_worst_slack -min
}
repair_timing -setup -verbose -setup_margin 2.0 -max_buffer_percent 10
repair_timing -hold -verbose -setup_margin 1.0 -hold_margin 0.25 -max_buffer_percent 10
set ::env(PL_OPTIMIZE_MIRRORING) 0
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
estimate_parasitics -placement
repair_design -verbose -slew_margin 30 -cap_margin 30
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
estimate_parasitics -placement
report_check_types -max_slew -max_cap -violators -digits 6 > $::env(STEP_DIR)/electrical_final.rpt
report_worst_slack -max
report_worst_slack -min
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
write_db $::env(STEP_DIR)/after_timing.odb
write_verilog $::env(STEP_DIR)/after_timing.v
write_views
