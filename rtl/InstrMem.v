module InstrMem(
    input [31:0] PC,
    output [31:0] Instr
);
    // Instruction memory - 4KB (1024 instructions)
    reg [31:0] memory [0:1023];
    
    // Initialize memory to NOP instructions (addi x0, x0, 0)
    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 32'h00000013; // addi x0, x0, 0 (NOP)
        end
    end
    
    // Asynchronous read operation
    // PC is word-aligned, so we use PC[11:2] for word addressing
    assign Instr = memory[PC[11:2]];
    
endmodule
