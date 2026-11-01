# Large electrical repairs can leave dense pockets of wider cells. Spread the
# combinational logic while keeping every register and clock-tree cell in place.
set_thread_count 2
array set saved_status {}
array set saved_location {}
array set saved_orientation {}
set registers [all_registers -cells]
if {[llength $registers] == 0} {error "Cannot spread logic without register protection"}
foreach cell $registers {
    set name [get_full_name $cell]
    set inst [$::block findInst $name]
    if {$inst == "NULL"} {error "Missing register instance $name"}
    set saved_status($name) [$inst getPlacementStatus]
    set saved_location($name) [$inst getLocation]
    set saved_orientation($name) [$inst getOrient]
    $inst setPlacementStatus FIRM
}
set clock_cells 0
foreach inst [$::block getInsts] {
    set name [$inst getName]
    if {[string match clkbuf* $name] || [string match clkroot* $name] || [string match clk_inv* $name]} {
        set saved_status($name) [$inst getPlacementStatus]
        set saved_location($name) [$inst getLocation]
        set saved_orientation($name) [$inst getOrient]
        $inst setPlacementStatus FIRM
        incr clock_cells
    }
}
if {$clock_cells == 0} {error "Cannot spread logic without clock-tree protection"}
puts "Fixed [array size saved_status] register and clock-tree instances"
foreach net [$::block getNets] {
    if {![$net isSpecial] && [$net getWire] != "NULL"} {odb::dbWire_destroy [$net getWire]}
}
global_placement -incremental -density 0.60 -disable_timing_driven -disable_routability_driven -skip_io
detailed_placement
check_placement -verbose
foreach name [array names saved_status] {
    set inst [$::block findInst $name]
    if {[$inst getLocation] != $saved_location($name) || [$inst getOrient] != $saved_orientation($name)} {
        error "Protected register or clock-tree instance moved: $name"
    }
    $inst setPlacementStatus $saved_status($name)
}
set_thread_count 6
