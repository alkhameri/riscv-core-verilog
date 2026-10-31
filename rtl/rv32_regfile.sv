// Two asynchronous read ports and one synchronous write port; x0 stays zero.
// Bypass WB here so ID sees the new value on a same-cycle read and write.
module rv32_regfile (
    input logic clk, reset,
    input logic [4:0] rs1, rs2,
    input rv32_pkg::bypass_t writeback,
    output logic [31:0] read_a, read_b
);
    logic [31:0] registers [32];

    always_comb begin
        read_a = rs1 == 0 ? 32'b0 : registers[rs1];
        read_b = rs2 == 0 ? 32'b0 : registers[rs2];
        if (writeback.valid && writeback.rd != 0) begin
            if (writeback.rd == rs1) read_a = writeback.value;
            if (writeback.rd == rs2) read_b = writeback.value;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < 32; i++) registers[i] <= 0;
        end else if (writeback.valid && writeback.rd != 0) begin
            registers[writeback.rd] <= writeback.value;
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk) disable iff (reset) registers[0] == 0);
`endif
endmodule
