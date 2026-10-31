module de10_lite_top (
    input logic MAX10_CLK1_50,
    input logic RESET_N,
    output logic UART_TX,
    output logic [9:0] LEDR
);
    // Pushbutton reset asserts asynchronously and releases on a clock edge.
    (* async_reg = "true" *) logic [1:0] reset_sync;
    logic reset;
    logic [25:0] heartbeat;
    logic [31:0] retired_pc, trap_cause, exit_code;
    logic trap, trap_seen, exit_valid;
    logic unused_debug;
    assign unused_debug = ^{retired_pc[31:10], retired_pc[1:0], trap_cause, exit_code, exit_valid};
    always_ff @(posedge MAX10_CLK1_50 or negedge RESET_N) begin
        if (!RESET_N) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0], 1'b0};
    end
    assign reset = reset_sync[1];
    rv32_soc #(.INIT_FILE("../build/firmware.hex")) soc (
        .clk(MAX10_CLK1_50), .reset, .uart_tx(UART_TX),
        .retired_pc, .trap, .trap_cause, .exit_valid, .exit_code
    );
    always_ff @(posedge MAX10_CLK1_50) begin
        if (reset) begin
            heartbeat <= 0;
            trap_seen <= 0;
        end else begin
            heartbeat <= heartbeat + 26'd1;
            if (trap) trap_seen <= 1;
        end
    end
    assign LEDR = {heartbeat[25], trap_seen, retired_pc[9:2]};
endmodule
