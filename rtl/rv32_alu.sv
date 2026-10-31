// Combinational integer datapath. Multiply/divide has its own iterative unit.
module rv32_alu (
    input rv32_pkg::alu_op_t operation,
    input logic [31:0] operand_a, operand_b,
    output logic [31:0] result
);
    import rv32_pkg::*;

    always_comb begin
        case (operation)
            ALU_ADD:  result = operand_a + operand_b;
            ALU_SUB:  result = operand_a - operand_b;
            ALU_SLL:  result = operand_a << operand_b[4:0];
            ALU_SLT:  result = {31'b0, $signed(operand_a) < $signed(operand_b)};
            ALU_SLTU: result = {31'b0, operand_a < operand_b};
            ALU_XOR:  result = operand_a ^ operand_b;
            ALU_SRL:  result = operand_a >> operand_b[4:0];
            ALU_SRA:  result = $unsigned($signed(operand_a) >>> operand_b[4:0]);
            ALU_OR:   result = operand_a | operand_b;
            ALU_AND:  result = operand_a & operand_b;
            ALU_COPY: result = operand_b;
            default:  result = 32'b0;
        endcase
    end
endmodule
