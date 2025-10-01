module reg(
    input [31:0] Instr, result,
    output [4:0] Rd, Rs1, Rs2
);
assign Rd  = Instr[11:7];
assign Rs1 = Instr[19:15];
assign Rs2 = Instr[24:20];

endmodule