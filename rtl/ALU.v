module ALU (
    input [31:0] SrcA, SrcB,
    input [3:0] ALUControl,
    output reg [31:0] ALUResult,
    output zero
)
always @(*)
begin
    case (ALUControl)
    4'b0001: ALUResult = SrcA & SrcB;
    4'b0010: ALUResult = SrcA | SrcB;
    4'b0100: ALUResult = SrcA + SrcB;
    4'b1000: ALUResult = SrcA - SrcB;
        default: ALUResult = 32'b0;
    endcase
end

assign zero = (ALUResult == 32'b0);

endmodule