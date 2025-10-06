module InstrMem(
    input clk,
    input [31:0] PC,
    output reg [31:0] Instr
);
    // Instruction memory - 4KB (1024 instructions)
    reg [31:0] memory [0:1023];
    
    // Initialize memory to NOP instructions (addi x0, x0, 0)
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 32'h00000013; // addi x0, x0, 0 (NOP)
        end
        // Optionally replace the loop above with a memory file load for synthesis:
        // $readmemh("instr_init.mem", memory);
    end

    // Synchronous read operation (better for block-RAM inference)
    // PC is word-aligned, so we use PC[11:2] for word addressing
    always @(posedge clk) begin
        Instr <= memory[PC[11:2]];
    end

endmodule
