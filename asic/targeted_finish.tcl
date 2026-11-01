# Check newly split nets with conservative estimates in a fresh process.
# Restore hold margin after resizing, including changes on clock branches.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(STEP_DIR)/libraries.tcl
read_current_odb
if {[info exists ::core_guarded_electrical]} {
    set_max_transition 0.45 [current_design]
    set_max_capacitance 0.10 [current_design]
}
set_propagated_clock [all_clocks]
remove_fillers
unset_dont_touch [get_cells CORE_INPUT_DELAY_*]
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
set_thread_count 3
foreach corner [sta::corners] {
    set resistance [expr {[rsz::wire_signal_resistance $corner] * 1.3}]
    set capacitance [expr {[rsz::wire_signal_capacitance $corner] * 3.0}]
    rsz::set_h_wire_signal_rc_cmd $corner $resistance $capacitance
    rsz::set_v_wire_signal_rc_cmd $corner $resistance $capacitance
}
set_max_fanout 1000 [current_design]
set ::env(PL_OPTIMIZE_MIRRORING) 0
proc finish_drivers {phase} {
    for {set iteration 0} {$iteration < 16} {incr iteration} {
        estimate_parasitics -placement
        set report $::env(STEP_DIR)/electrical_${phase}_${iteration}.rpt
        report_check_types -max_slew -max_cap -violators -digits 6 > $report
        set stream [open $report r]
        set contents [read $stream]
        close $stream
        set drivers {}
        foreach line [split $contents \n] {
            if {[regexp {^(\S+)\s+[-.0-9]+\s+[-.0-9]+\s+[-.0-9]+\s+\(VIOLATED\)} $line -> name]} {
                set pins [get_pins -quiet [list $name]]
                if {[llength $pins] == 1 && [get_property [lindex $pins 0] direction] == "output"} {
                    lappend drivers $name
                }
            }
        }
        set drivers [lsort -unique $drivers]
        set changed 0
        set before_count [llength [$::block getInsts]]
        foreach name $drivers {
            set pin [get_pins [list $name]]
            set cell [get_cells -of_objects $pin]
            set before [get_property $cell ref_name]
            set replaced 0
            if {[regexp {^(.*)_([0-9]+)$} $before -> base current]} {
                foreach strength {1 2 3 4 6 8 12 16} {
                    set target ${base}_${strength}
                    if {$strength > $current && [[ord::get_db] findMaster $target] != "NULL"} {
                        replace_cell [get_full_name $cell] $target
                        puts "UPSIZED [get_full_name $cell] $before -> $target"
                        incr changed
                        set replaced 1
                        break
                    }
                }
            }
            if {!$replaced} {
                rsz::repair_net_cmd [lindex [get_nets -of_objects $pin] 0] 0.0 20.0 20.0
                # Allow reconnection during buffering, then retain drive strength.
                replace_cell [get_full_name $cell] $before
            }
        }
        set added [expr {[llength [$::block getInsts]] - $before_count}]
        puts "$phase pass $iteration: [llength $drivers] drivers, $changed upsized, $added added cells"
        source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
        if {$changed == 0 && $added == 0} {break}
    }
}
finish_drivers before_hold
estimate_parasitics -placement
repair_timing -hold -verbose -setup_margin 1.0 -hold_margin 0.30 -max_buffer_percent 10
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
finish_drivers after_hold
estimate_parasitics -placement
report_check_types -max_slew -max_cap -violators -digits 6 > $::env(STEP_DIR)/electrical_final.rpt
report_worst_slack -max
report_worst_slack -min
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if {[info exists ::core_guarded_electrical]} {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}
write_db $::env(STEP_DIR)/after_timing.odb
write_verilog $::env(STEP_DIR)/after_timing.v
write_views
