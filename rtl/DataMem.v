module DataMem(
    input clk,
    input MemWrite,
    input [31:0] ALUResult, WriteData,
    output [31:0] ReadData
);
    reg [31:0] memory [0:1023]; // 1KB memory

    // Read operation (asynchronous)
    assign ReadData = memory[ALUResult[11:2]]; 

    // Write operation (synchronous)
    always @(posedge clk) begin
        if (MemWrite) begin
            memory[ALUResult[11:2]] <= WriteData;
        end
    end
endmodule
