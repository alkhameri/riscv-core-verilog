# Keep the closed placement and repair only the remaining extracted loads.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(STEP_DIR)/libraries.tcl
read_current_odb
set_propagated_clock [all_clocks]
remove_fillers
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_routing_layers.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_layer_adjustments.tcl
set_macro_extension $::env(GRT_MACRO_EXTENSION)
set_thread_count 6

# Preserve locked boundary cells as well as the functional placement.
set block [ord::get_db_block]
set old_cells [dict create]
foreach inst [$block getInsts] {
    dict set old_cells [$inst getName] [list [$inst getPlacementStatus] \
        [$inst getLocation] [$inst getOrient] [[$inst getMaster] getName]]
    if {[$inst getPlacementStatus] == "PLACED"} {$inst setPlacementStatus FIRM}
}
set old_wires 0
foreach net [$block getNets] {
    if {![$net isSpecial] && [$net getWire] != "NULL"} {incr old_wires}
}

# Loading existing guides initializes incremental routing without rerouting.
pin_access -bottom_routing_layer $::env(RT_MIN_LAYER) \
    -top_routing_layer $::env(RT_MAX_LAYER)
if {![grt::have_routes]} {error "Local repair needs existing routing guides"}
source $::env(STEP_DIR)/parasitics.tcl
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
puts "LOCAL repairing [llength $drivers] extracted electrical drivers"

global_route -start_incremental
set buffer_master [[ord::get_db] findMaster sky130_fd_sc_hd__buf_8]
if {$buffer_master == "NULL"} {error "Missing local repair buffer"}
set added 0
set repair_index 0
while {[$block findInst LOCAL_REPAIR_${repair_index}] != "NULL" \
    || [$block findNet LOCAL_REPAIR_${repair_index}_net] != "NULL"} {incr repair_index}
foreach name $drivers {
    set split [string last / $name]
    set source [$block findInst [string range $name 0 [expr {$split - 1}]]]
    set pin [$source findITerm [string range $name [expr {$split + 1}] end]]
    set original_net [$pin getNet]
    lassign [$source getLocation] x y
    set sum_x 0
    set sum_y 0
    set sinks 0
    foreach sink [$original_net getITerms] {
        if {$sink == $pin} {continue}
        lassign [[$sink getInst] getLocation] sink_x sink_y
        incr sum_x $sink_x
        incr sum_y $sink_y
        incr sinks
    }
    if {$sinks == 0} {error "No cell sinks on selected net $name"}
    set middle_x [expr {int(($x + $sum_x / $sinks) / 2)}]
    set middle_y [expr {int(($y + $sum_y / $sinks) / 2)}]

    # A nearby buffer unloads the source. A second one splits the long wire.
    # Fixed original cells keep the clock tree and short hold paths intact.
    set previous_net [odb::dbNet_create $block LOCAL_REPAIR_${repair_index}_net]
    $pin connect $previous_net
    foreach stage {0 1} {
        set position [lindex [list [list $x $y] [list $middle_x $middle_y]] $stage]
        set cell_name LOCAL_REPAIR_${repair_index}
        if {[$block findInst $cell_name] != "NULL"} {error "Duplicate repair cell $cell_name"}
        set cell [odb::dbInst_create $block $buffer_master $cell_name]
        $cell setOrient [$source getOrient]
        $cell setLocation {*}$position
        $cell setPlacementStatus PLACED
        [$cell findITerm A] connect $previous_net
        incr added
        incr repair_index
        if {$stage == 1} {
            set next_net $original_net
        } else {
            set next_net [odb::dbNet_create $block LOCAL_REPAIR_${repair_index}_net]
        }
        [$cell findITerm X] connect $next_net
        set previous_net $next_net
    }
}
puts "LOCAL added $added cells; retained every existing cell master and location"
set ::env(PL_OPTIMIZE_MIRRORING) 0
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
pin_access -bottom_routing_layer $::env(RT_MIN_LAYER) \
    -top_routing_layer $::env(RT_MAX_LAYER)
# Existing detailed wires consume reserved global-routing tracks. Let the
# detailed router resolve local overflow; its final DRC must still be zero.
global_route -end_incremental -congestion_iterations $::env(GRT_OVERFLOW_ITERS) \
    -allow_congestion -verbose
set retained_wires 0
foreach net [$block getNets] {
    if {![$net isSpecial] && [$net getWire] != "NULL"} {incr retained_wires}
}
puts "LOCAL retained $retained_wires of $old_wires existing signal routes"
if {$retained_wires < 0.95 * $old_wires} {error "Local repair disturbed too many routes"}
write_db $::env(STEP_DIR)/before_detailed.odb
detailed_route -bottom_routing_layer $::env(RT_MIN_LAYER) \
    -top_routing_layer $::env(RT_MAX_LAYER) \
    -output_drc $::env(STEP_DIR)/rv32_core.drc -drc_report_iter_step 5 \
    -droute_end_iter 64 -or_seed 42 -verbose 1
write_db $::env(STEP_DIR)/after_detailed.odb
set diode [lindex [split $::env(DIODE_CELL) /] 0]
for {set iteration 0} {$iteration < 5 && [check_antennas]} {incr iteration} {
    repair_antennas $diode -iterations 1 -ratio_margin 20
    detailed_route -bottom_routing_layer $::env(RT_MIN_LAYER) \
        -top_routing_layer $::env(RT_MAX_LAYER) \
        -output_drc $::env(STEP_DIR)/rv32_core.drc -drc_report_iter_step 5 \
        -droute_end_iter 64 -or_seed 42 -verbose 1
}
write_db $::env(STEP_DIR)/after_antenna.odb
set block [ord::get_db_block]
dict for {name state} $old_cells {
    set inst [$block findInst $name]
    if {$inst == "NULL"} {error "Missing protected cell $name with state $state"}
    lassign $state status location orientation master
    if {[$inst getLocation] != $location || [$inst getOrient] != $orientation \
        || [[$inst getMaster] getName] != $master} {
        error "Local repair changed protected cell $name"
    }
    $inst setPlacementStatus $status
}
check_placement -verbose
write_views
