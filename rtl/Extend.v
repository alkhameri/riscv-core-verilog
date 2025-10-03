module Extend(
    input  [31:7] Instr,
    input  [2:0]  ImmSel,
    output reg [31:0] Imm
);

always @(*) begin
    case (ImmSel)
        3'b000: // i-type
        Imm = {{20{Instr[31]}}, Instr[31:20]};
        3'b001:  // s-type
        Imm = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};
        3'b010:  // b-type
        Imm = {{19{Instr[31]}}, Instr[31], Instr[7], Instr[30:25], Instr[11:8], 1'b0};
        3'b011:  // u-type
        Imm = {{11{Instr[31]}}, Instr[31], Instr[19:12], Instr[20], Instr[30:21], 1'b0};
        3'b100:  // j-type
        Imm = {{11{Instr[31]}}, Instr[31], Instr[19:12], Instr[20], Instr[30:21], 1'b0};
        default: Imm = 32'b0;
    endcase
end

endmodule