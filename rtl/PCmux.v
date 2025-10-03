module PCmux(
    input [31:0] PCplus4, PCTarget,
    input PCSrc,
    output [31:0] PCNext
);

assign PCNext = PCSrc ? PCTarget : PCplus4;

endmodule