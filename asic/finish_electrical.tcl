# Buffer loaded inputs, then increase drive strengths without downsizing.
# Keep the cell function and pin names by selecting a larger variant.
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
estimate_parasitics -placement
buffer_ports -inputs
set ::env(PL_OPTIMIZE_MIRRORING) 0
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
for {set iteration 0} {$iteration < 12} {incr iteration} {
    estimate_parasitics -placement
    set report $::env(STEP_DIR)/electrical_${iteration}.rpt
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
    foreach name $drivers {
        set cell [get_cells -of_objects [get_pins [list $name]]]
        set before [get_property $cell ref_name]
        if {![regexp {^(.*)_([0-9]+)$} $before -> base current]} {continue}
        foreach strength {1 2 3 4 6 8 12 16} {
            set target ${base}_${strength}
            if {$strength > $current && [[ord::get_db] findMaster $target] != "NULL"} {
                replace_cell [get_full_name $cell] $target
                puts "UPSIZED [get_full_name $cell] $before -> $target"
                incr changed
                break
            }
        }
    }
    puts "Pass $iteration: [llength $drivers] violating drivers, $changed upsized"
    source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
    if {$changed == 0} {break}
}
estimate_parasitics -placement
report_check_types -max_slew -max_cap -violators -digits 6 > $::env(STEP_DIR)/electrical_final.rpt
report_worst_slack -max
report_worst_slack -min
write_db $::env(STEP_DIR)/after_timing.odb
write_verilog $::env(STEP_DIR)/after_timing.v
write_views
