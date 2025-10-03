module RegisterFile(
    input clk,
    input rst,
    input RegWrite,
    input [4:0] Rd, Rs1, Rs2,
    input [31:0] WriteData,
    output [31:0] ReadData1, ReadData2
);
    // 32 registers (x0-x31)
    reg [31:0] registers [0:31];
    
    integer i; // initialize all registers to zero
    initial begin
        for (i = 0; i < 32; i = i + 1) begin 
            registers[i] = 32'b0;
        end
    end
    
    // Reset all registers to zero
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'b0;
            end
        end else if (RegWrite && (Rd != 5'b0)) begin
            // Write to register (x0 is always zero, so don't write to it)
            registers[Rd] <= WriteData;
        end
    end
    
    // Asynchronous read operations
    assign ReadData1 = (Rs1 == 5'b0) ? 32'b0 : registers[Rs1];
    assign ReadData2 = (Rs2 == 5'b0) ? 32'b0 : registers[Rs2];
    
endmodule