create_clock -name core_clock -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Reset assertion is asynchronous. Deassertion is synchronized in the top level.
set_false_path -from [get_ports RESET_N]
# LEDs and the self-timed UART are not synchronous interfaces to another clock.
set_false_path -to [get_ports {LEDR[*] UART_TX}]
