module PCplus4(
    input [31:0] PC,
    output [31:0] PCplus4
);
assign PCplus4 = PC + 32'b00000000000000000000000000000100;

endmodule