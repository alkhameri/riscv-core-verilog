`timescale 1ns/1ps

module simple_tb;
    // Clock and reset
    reg clk, rst;
    
    // Instantiate the processor
    RISCVCore dut (
        .clk(clk),
        .rst(rst)
    );
    
    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        $display("=== Simple RISC-V Core Testbench ===");
        
        // Initialize
        rst = 1;
        #20 rst = 0;
        
        $display("Reset complete, PC starts at 0x%08h", dut.PC);
        
        // Load some test instructions
        load_test_program();
        
        // Run for several clock cycles
        #200;
        
        $display("=== Test Complete ===");
        $finish;
    end
    
    // Load a simple test program
    task load_test_program;
        begin
            // Program: addi x1, x0, 5
            dut.instr_mem.memory[0] = 32'h00500093;
            
            // Program: addi x2, x0, 3  
            dut.instr_mem.memory[1] = 32'h00300113;
            
            // Program: add x3, x1, x2
            dut.instr_mem.memory[2] = 32'h002081b3;
            
            // Program: sw x3, 0(x0)
            dut.instr_mem.memory[3] = 32'h00302023;
            
            // Program: lw x4, 0(x0)
            dut.instr_mem.memory[4] = 32'h00002203;
            
            $display("Test program loaded");
        end
    endtask
    
    // Monitor key signals
    initial begin
        $monitor("Time: %0t | PC: 0x%08h | Instr: 0x%08h | RegWrite: %b | ALUResult: 0x%08h", 
                 $time, dut.PC, dut.Instr, dut.RegWrite, dut.ALUResult);
    end
    
    // Generate VCD file
    initial begin
        $dumpfile("simple_test.vcd");
        $dumpvars(0, simple_tb);
    end
    
endmodule
