module ALUmux(
    input [31:0] Reg2, Imm,
    input ALUSrc,
    output [31:0] SrcB
);

assign SrcB = ALUSrc ? Imm : Reg2;

endmodule