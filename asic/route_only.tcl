# Resume from a saved, legalized timing-repair checkpoint.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
read_current_odb
remove_fillers
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
set_thread_count 6
source /work/asic/route_repair.tcl
