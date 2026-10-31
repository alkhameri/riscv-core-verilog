// MEM is newer than WB, so it wins if both have a value for the same register.
// EX saves the selected operands while stalled. Otherwise a WB value could
// disappear before the waiting instruction gets to use it.
module rv32_forwarding (
    input logic [4:0] rs1, rs2,
    input logic uses_rs1, uses_rs2,
    input logic [31:0] saved_a, saved_b,
    input rv32_pkg::bypass_t memory_bypass, writeback_bypass,
    output logic [31:0] operand_a, operand_b
);
    always_comb begin
        operand_a = saved_a;
        operand_b = saved_b;
        if (writeback_bypass.valid && writeback_bypass.rd != 0) begin
            if (writeback_bypass.rd == rs1) operand_a = writeback_bypass.value;
            if (writeback_bypass.rd == rs2) operand_b = writeback_bypass.value;
        end
        if (memory_bypass.valid && memory_bypass.rd != 0) begin
            if (memory_bypass.rd == rs1) operand_a = memory_bypass.value;
            if (memory_bypass.rd == rs2) operand_b = memory_bypass.value;
        end
        if (!uses_rs1 || rs1 == 0) operand_a = 0;
        if (!uses_rs2 || rs2 == 0) operand_b = 0;
    end
endmodule
