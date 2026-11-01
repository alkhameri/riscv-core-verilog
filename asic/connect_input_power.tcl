# Timing optimization is complete. Release the protected input delay cells so
# the standard global-connection rules can verify their supply assignments.
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
read_current_odb
unset_dont_touch [get_cells CORE_INPUT_DELAY_*]
write_views
