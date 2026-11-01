# Keep the incremental routes produced by antenna repair. A fresh global route
# here can reconnect a diode above the layer that needs its protection.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
read_current_odb
source $::env(SCRIPTS_DIR)/openroad/common/dpl_cell_pad.tcl
source $::env(SCRIPTS_DIR)/openroad/common/grt.tcl

set diode [lindex [split $::env(DIODE_CELL) /] 0]
repair_antennas $diode \
    -iterations $::env(GRT_ANTENNA_ITERS) \
    -ratio_margin $::env(GRT_ANTENNA_MARGIN)
check_placement -verbose

puts "%OL_CREATE_REPORT antenna.rpt"
check_antennas -verbose
puts "%OL_END_REPORT"
write_views
