module DataMem(
    input clk,
    input MemWrite,
    input [31:0] ALUResult, WriteData,
    output reg [31:0] ReadData
);
    reg [31:0] memory [0:1023]; // 1KB memory

    // Synchronous read and write to aid block-RAM inference
    always @(posedge clk) begin
        // Read (registered output)
        ReadData <= memory[ALUResult[11:2]];

        // Write
        if (MemWrite) begin
            memory[ALUResult[11:2]] <= WriteData;
        end
    end
endmodule
