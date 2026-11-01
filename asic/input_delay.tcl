# Give the synchronous inputs a shared hold delay before their fanout trees.
# These are non-inverting physical delay cells, not extra pipeline registers.
set delay_master [[ord::get_db] findMaster sky130_fd_sc_hd__dlygate4sd3_1]
if {$delay_master == "NULL"} { error "Missing SKY130 input delay cell" }
set port_index 0
foreach port [$::block getBTerms] {
    if {[$port getIoType] != "INPUT" || [$port getName] == "clk"} { continue }
    set original_net [$port getNet]
    set sinks [$original_net getITerms]
    if {[llength $sinks] == 0} { continue }
    set anchor [[lindex $sinks 0] getInst]
    set previous_net $original_net
    for {set stage 0} {$stage < 2} {incr stage} {
        set name CORE_INPUT_DELAY_${port_index}_${stage}
        if {[$::block findInst $name] != "NULL"} { error "Input delay already exists: $name" }
        set cell [odb::dbInst_create $::block $delay_master $name]
        set next_net [odb::dbNet_create $::block ${name}_net]
        $cell setOrient [$anchor getOrient]
        $cell setLocation {*}[$anchor getLocation]
        $cell setPlacementStatus PLACED
        [$cell findITerm A] connect $previous_net
        [$cell findITerm X] connect $next_net
        set previous_net $next_net
    }
    foreach sink $sinks { $sink connect $previous_net }
    puts "Added two input delay cells to [$port getName]"
    incr port_index
}
# Connect supplies before protecting these instances from timing optimization.
source $::env(SCRIPTS_DIR)/openroad/common/set_power_nets.tcl
set_global_connections
set_dont_touch [get_cells CORE_INPUT_DELAY_*]
source $::env(SCRIPTS_DIR)/openroad/common/dpl.tcl
