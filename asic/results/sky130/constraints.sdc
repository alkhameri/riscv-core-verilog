# This is a synchronous CPU macro. The surrounding system must register its
# bus responses, interrupts, reset, and time_value against this same clock.
create_clock -name clk -period $::env(CLOCK_PERIOD) [get_ports clk]
set data_inputs [all_inputs]
set clock_index [lsearch $data_inputs [get_ports clk]]
set data_inputs [lreplace $data_inputs $clock_index $clock_index]

# Reserve 20 percent of the cycle for logic outside the macro. Specify both
# bounds: using the setup delay as the minimum would hide interface hold paths.
set io_max [expr {$::env(CLOCK_PERIOD) * 0.20}]
set_input_delay -clock clk -max $io_max $data_inputs
set_input_delay -clock clk -min 0.50 $data_inputs
set_output_delay -clock clk -max $io_max [all_outputs]
set_output_delay -clock clk -min 0.50 [all_outputs]

set drive_cell [lindex [split $::env(SYNTH_DRIVING_CELL) /] 0]
set drive_pin [lindex [split $::env(SYNTH_DRIVING_CELL) /] 1]
set_driving_cell -lib_cell $drive_cell -pin $drive_pin $data_inputs
set_input_transition $::env(CLOCK_TRANSITION_CONSTRAINT) [get_ports clk]
set_load [expr {$::env(OUTPUT_CAP_LOAD) / 1000.0}] [all_outputs]
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) [get_clocks clk]
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) [get_clocks clk]
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if {[info exists ::env(MAX_TRANSITION_CONSTRAINT)]} {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if {[info exists ::env(MAX_CAPACITANCE_CONSTRAINT)]} {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}
set_timing_derate -early [expr {1 - $::env(TIME_DERATING_CONSTRAINT) / 100.0}]
set_timing_derate -late [expr {1 + $::env(TIME_DERATING_CONSTRAINT) / 100.0}]
if {[info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS)} {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
