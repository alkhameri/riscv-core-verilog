# Size existing drivers against actual wire capacitance without changing nets.
# Newly inserted buffers need a later pass once their loads are available.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(STEP_DIR)/libraries.tcl
read_current_odb
set_propagated_clock [all_clocks]
remove_fillers
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
set_thread_count 2
source $::env(STEP_DIR)/parasitics.tcl
for {set iteration 0} {$iteration < 6} {incr iteration} {
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
    puts "Pass $iteration has [llength $drivers] violating output drivers"
    set changed 0
    foreach name $drivers {
        set pin [get_pins [list $name]]
        set cell [get_cells -of_objects $pin]
        set before [get_property $cell ref_name]
        rsz::resize_to_target_slew [lindex $pin 0]
        set after [get_property $cell ref_name]
        if {$before != $after} {
            puts "RESIZE [get_full_name $cell] $before -> $after"
            incr changed
        }
    }
    puts "Pass $iteration resized $changed drivers"
    report_worst_slack -max
    report_worst_slack -min
    if {$changed == 0} {break}
}
report_check_types -max_slew -max_cap -violators -digits 6 > $::env(STEP_DIR)/electrical_final.rpt
write_db $::env(STEP_DIR)/resized.odb
write_verilog $::env(STEP_DIR)/resized.v
write_views
