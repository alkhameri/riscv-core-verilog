# Magic performs many small filesystem lookups while importing hierarchical GDS.
# Use the container's local disk, then retain the ordinary OpenLane outputs.
if {!$::env(MAGIC_EXT_USE_GDS)} {error "This flow requires extraction from GDS"}
set result_dir $::env(STEP_DIR)
set original_gds $::env(CURRENT_GDS)
set original_directory [pwd]
set scratch [file join /tmp rv32-gds-extraction-[pid]]
file mkdir $scratch
file copy $original_gds [file join $scratch input.gds]
set ::env(CURRENT_GDS) [file join $scratch input.gds]
set ::env(STEP_DIR) $scratch
cd $scratch
try {
    source $::env(SCRIPTS_DIR)/magic/extract_spice.tcl
} finally {
    cd $original_directory
    set ::env(STEP_DIR) $result_dir
    set ::env(CURRENT_GDS) $original_gds
    foreach name [list cif_scale.txt feedback.txt $::env(DESIGN_NAME).spice] {
        if {[file exists [file join $scratch $name]]} {
            file copy -force [file join $scratch $name] [file join $result_dir $name]
        }
    }
    if {[file exists [file join $scratch extraction]]} {
        file copy [file join $scratch extraction] [file join $result_dir native-extraction]
    }
    file delete -force $scratch
}
