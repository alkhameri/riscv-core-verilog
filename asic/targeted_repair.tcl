# Limit the final repair to drivers that fail extracted electrical checks.
# A larger wire-capacitance estimate gives new buffer segments routing margin.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(STEP_DIR)/libraries.tcl
read_current_odb
set_propagated_clock [all_clocks]
remove_fillers
unset_dont_touch [get_cells CORE_INPUT_DELAY_*]
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
set_thread_count 3
source $::env(STEP_DIR)/parasitics.tcl
if {[info exists ::core_guarded_electrical]} {
    set_max_transition 0.45 [current_design]
    set_max_capacitance 0.10 [current_design]
}
foreach corner [sta::corners] {
    set resistance [expr {[rsz::wire_signal_resistance $corner] * 1.3}]
    set capacitance [expr {[rsz::wire_signal_capacitance $corner] * 3.0}]
    rsz::set_h_wire_signal_rc_cmd $corner $resistance $capacitance
    rsz::set_v_wire_signal_rc_cmd $corner $resistance $capacitance
}
set_max_fanout 1000 [current_design]
report_check_types -max_slew -max_cap -violators -digits 6 > $::env(STEP_DIR)/before.rpt
set stream [open $::env(STEP_DIR)/before.rpt r]
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
puts "Repairing [llength $drivers] extracted electrical drivers"
set clock_drivers {}
foreach name $drivers {
    set pin [get_pins [list $name]]
    set cell [get_cells -of_objects $pin]
    set before [get_property $cell ref_name]
    if {[regexp {^(.*)_([0-9]+)$} $before -> base current]} {
        foreach strength {1 2 3 4 6 8 12 16} {
            set target ${base}_${strength}
            if {$strength > $current && [[ord::get_db] findMaster $target] != "NULL"} {
                replace_cell [get_full_name $cell] $target
                puts "UPSIZED [get_full_name $cell] $before -> $target"
                break
            }
        }
    }
    if {[info exists ::core_bulk_electrical]} {
        if {[sta::is_clock [lindex $pin 0]]} {lappend clock_drivers $name}
    } else {
        set net [lindex [get_nets -of_objects $pin] 0]
        rsz::repair_net_cmd $net 0.0 20.0 20.0
    }
}
if {[info exists ::core_bulk_electrical]} {
    # Batch data-net repairs to avoid rebuilding timing state for every net.
    # repair_design skips clocks, so handle those selected branches explicitly.
    repair_design -verbose -slew_margin 20 -cap_margin 20
    puts "Repairing [llength $clock_drivers] selected clock drivers"
    foreach name $clock_drivers {
        set pin [get_pins [list $name]]
        rsz::repair_net_cmd [lindex [get_nets -of_objects $pin] 0] 0.0 20.0 20.0
    }
}
set ::env(PL_OPTIMIZE_MIRRORING) 0
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if {[info exists ::core_guarded_electrical]} {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}
write_db $::env(STEP_DIR)/after_timing.odb
write_verilog $::env(STEP_DIR)/after_timing.v
write_views
