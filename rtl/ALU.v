module ALU (
    input [31:0] SrcA, SrcB,
    input [3:0] ALUControl,
    output reg [31:0] ALUResult,
    output zero
)
always @(*)
begin
    case (ALUControl)
    4b'0001: ALUResult <= SrcA & SrcB;
    4b'0010: ALUResult <= SrcA | SrcB;
    4b'0100: ALUResult <= SrcA + SrcB;
    4b'1000: ALUResult <= SrcA - SrcB;
        default: ALUResult = SrcA;
    endcase
end
endmodule