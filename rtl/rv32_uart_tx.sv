// 8N1, no FIFO. The peripheral holds a bus write until the transmitter is free.
module rv32_uart_tx #(
    parameter int CLOCK_HZ = 50_000_000,
    parameter int BAUD = 115200,
    parameter int CLOCKS_PER_BIT = CLOCK_HZ / BAUD
) (
    input logic clk, reset, valid,
    input logic [7:0] data,
    output logic ready, tx
);
    logic [9:0] shift_register;
    logic [3:0] bits_remaining;
    logic [$clog2(CLOCKS_PER_BIT)-1:0] divider;
    assign ready = bits_remaining == 0;
    assign tx = ready ? 1'b1 : shift_register[0];
    always_ff @(posedge clk) begin
        if (reset) begin
            shift_register <= '1;
            bits_remaining <= 0;
            divider <= 0;
        end else if (valid && ready) begin
            shift_register <= {1'b1, data, 1'b0};
            bits_remaining <= 10;
            divider <= $clog2(CLOCKS_PER_BIT)'(CLOCKS_PER_BIT - 1);
        end else if (!ready) begin
            if (divider == 0) begin
                shift_register <= {1'b1, shift_register[9:1]};
                bits_remaining <= bits_remaining - 4'd1;
                divider <= $clog2(CLOCKS_PER_BIT)'(CLOCKS_PER_BIT - 1);
            end else divider <= divider - 1'b1;
        end
    end
endmodule
