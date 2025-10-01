module PCplusimm(
    input [31:0] PC,
    input [31:0] Imm,
    output [31:0] PCTarget
);
assign PCTarget = PC + Imm;

endmodule