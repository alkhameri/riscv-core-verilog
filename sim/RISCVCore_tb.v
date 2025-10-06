`timescale 1ns/1ps

module RISCVCore_tb;
    // Clock and reset
    reg clk, rst;

    // Board-level port signals (tie-offs / probes)
    wire ADC_CLK_10 = 1'b0;
    wire MAX10_CLK1_50; // driven by testbench clock
    wire MAX10_CLK2_50 = 1'b0;

    wire [12:0] DRAM_ADDR;
    wire [1:0] DRAM_BA;
    wire DRAM_CAS_N;
    wire DRAM_CKE;
    wire DRAM_CLK;
    wire DRAM_CS_N;
    wire [15:0] DRAM_DQ;
    wire DRAM_LDQM;
    wire DRAM_RAS_N;
    wire DRAM_UDQM;
    wire DRAM_WE_N;

    wire [7:0] HEX0;
    wire [7:0] HEX1;
    wire [7:0] HEX2;
    wire [7:0] HEX3;
    wire [7:0] HEX4;
    wire [7:0] HEX5;

    wire [1:0] KEY = {1'b1, ~rst};
    wire [9:0] LEDR;
    wire [9:0] SW = 10'b0;

    wire [3:0] VGA_B;
    wire [3:0] VGA_G;
    wire VGA_HS;
    wire [3:0] VGA_R;
    wire VGA_VS;

    wire GSENSOR_CS_N;
    wire [2:1] GSENSOR_INT;
    wire GSENSOR_SCLK;
    wire GSENSOR_SDI;
    wire GSENSOR_SDO;

    wire [15:0] ARDUINO_IO;
    wire ARDUINO_RESET_N;
    wire [35:0] GPIO;

    // Drive internal board clock from TB clock
    assign MAX10_CLK1_50 = clk;

    // Instantiate the board-style top module directly (named ports)
    RISCVCore dut (
        .ADC_CLK_10(ADC_CLK_10),
        .MAX10_CLK1_50(MAX10_CLK1_50),
        .MAX10_CLK2_50(MAX10_CLK2_50),
        .DRAM_ADDR(DRAM_ADDR),
        .DRAM_BA(DRAM_BA),
        .DRAM_CAS_N(DRAM_CAS_N),
        .DRAM_CKE(DRAM_CKE),
        .DRAM_CLK(DRAM_CLK),
        .DRAM_CS_N(DRAM_CS_N),
        .DRAM_DQ(DRAM_DQ),
        .DRAM_LDQM(DRAM_LDQM),
        .DRAM_RAS_N(DRAM_RAS_N),
        .DRAM_UDQM(DRAM_UDQM),
        .DRAM_WE_N(DRAM_WE_N),
        .HEX0(HEX0),
        .HEX1(HEX1),
        .HEX2(HEX2),
        .HEX3(HEX3),
        .HEX4(HEX4),
        .HEX5(HEX5),
        .KEY(KEY),
        .LEDR(LEDR),
        .SW(SW),
        .VGA_B(VGA_B),
        .VGA_G(VGA_G),
        .VGA_HS(VGA_HS),
        .VGA_R(VGA_R),
        .VGA_VS(VGA_VS),
        .GSENSOR_CS_N(GSENSOR_CS_N),
        .GSENSOR_INT(GSENSOR_INT),
        .GSENSOR_SCLK(GSENSOR_SCLK),
        .GSENSOR_SDI(GSENSOR_SDI),
        .GSENSOR_SDO(GSENSOR_SDO),
        .ARDUINO_IO(ARDUINO_IO),
        .ARDUINO_RESET_N(ARDUINO_RESET_N),
        .GPIO(GPIO)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end
    
    // Test stimulus
    initial begin
        $display("=== RISC-V Core Testbench Started ===");
        
        // Initialize signals
        rst = 1;
        
        // Reset sequence
        #20 rst = 0;
        #10;
        
        $display("Reset complete, starting tests...");
        
        // test alu
        test_alu_operations();
        
        // test mem
        test_memory_operations();
        
        // test branch
        test_branch_operations();
        
        // test jump
        test_jump_operations();
        
        // test reg
        test_register_operations();
        
        $display("=== All Tests Completed ===");
        $finish;
    end
    
    // Test 1: ALU Operations
    task test_alu_operations;
        begin
            $display("\n--- Testing ALU Operations ---");
            
            // Load test instructions into instruction memory
            // addi x1, x0, 5     (x1 = 5)
            load_instruction(0, 32'h00500093);
            
            // addi x2, x0, 3     (x2 = 3)  
            load_instruction(1, 32'h00300113);
            
            // add x3, x1, x2     (x3 = x1 + x2 = 8)
            load_instruction(2, 32'h002081b3);
            
            // sub x4, x1, x2     (x4 = x1 - x2 = 2)
            load_instruction(3, 32'h40210233);
            
            // or x5, x1, x2      (x5 = x1 | x2)
            load_instruction(4, 32'h0020e2b3);
            
            // and x6, x1, x2     (x6 = x1 & x2)
            load_instruction(5, 32'h0020f333);
            
            // Execute instructions
            run_instructions(6);
            
            $display("ALU operations test completed");
        end
    endtask
    
    // Test 2: Memory Operations
    task test_memory_operations;
        begin
            $display("\n--- Testing Memory Operations ---");
            
            // Load data into memory
            load_data_memory(0, 32'h12345678);
            load_data_memory(4, 32'h9ABCDEF0);
            
            // lw x7, 0(x0)       (load from address 0)
            load_instruction(10, 32'h00002383);
            
            // sw x7, 8(x0)       (store to address 8)
            load_instruction(11, 32'h00702423);
            
            // lw x8, 8(x0)       (load from address 8)
            load_instruction(12, 32'h00802403);
            
            run_instructions(3);
            
            $display("Memory operations test completed");
        end
    endtask
    
    // Test 3: Branch Operations
    task test_branch_operations;
        begin
            $display("\n--- Testing Branch Operations ---");
            
            // beq x0, x0, 4     (branch always taken)
            load_instruction(20, 32'h00000463);
            
            // addi x9, x0, 1     (should be skipped)
            load_instruction(21, 32'h00100493);
            
            // addi x10, x0, 2    (target of branch)
            load_instruction(22, 32'h00200513);
            
            run_instructions(3);
            
            $display("Branch operations test completed");
        end
    endtask
    
    // Test 4: Jump Operations
    task test_jump_operations;
        begin
            $display("\n--- Testing Jump Operations ---");
            
            // jal x11, 8         (jump and link)
            load_instruction(30, 32'h008005ef);
            
            // addi x12, x0, 1    (should be skipped)
            load_instruction(31, 32'h00100613);
            
            // addi x13, x0, 2    (target of jump)
            load_instruction(32, 32'h00200693);
            
            run_instructions(3);
            
            $display("Jump operations test completed");
        end
    endtask
    
    // Test 5: Register File Operations
    task test_register_operations;
        begin
            $display("\n--- Testing Register File Operations ---");
            
            // Test x0 register (always zero)
            // addi x14, x0, 0    (x14 = 0)
            load_instruction(40, 32'h00000713);
            
            // addi x15, x0, 1    (x15 = 1)
            load_instruction(41, 32'h00100793);
            
            // add x16, x14, x15  (x16 = 0 + 1 = 1)
            load_instruction(42, 32'h00f70833);
            
            run_instructions(3);
            
            $display("Register file operations test completed");
        end
    endtask
    
    // Helper task to load instruction into instruction memory
    task load_instruction;
        input [31:0] address;
        input [31:0] instruction;
        begin
            dut.instr_mem.memory[address] = instruction;
            $display("Loaded instruction 0x%08h at address %d", instruction, address);
        end
    endtask
    
    // Helper task to load data into data memory
    task load_data_memory;
        input [31:0] address;
        input [31:0] data;
        begin
            dut.data_mem.memory[address[11:2]] = data;
            $display("Loaded data 0x%08h at address %d", data, address);
        end
    endtask
    
    // Helper task to run instructions
    task run_instructions;
        input [31:0] count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                #10; // Wait one clock cycle
                $display("PC: 0x%08h, Instruction: 0x%08h", dut.PC, dut.Instr);
            end
        end
    endtask
    
    // Monitor key signals
    initial begin
        $monitor("Time: %0t | PC: 0x%08h | Instr: 0x%08h | RegWrite: %b | ALUSrc: %b | MemWrite: %b", 
                 $time, dut.PC, dut.Instr, dut.RegWrite, dut.ALUSrc, dut.MemWrite);
    end

    // vcd file
    initial begin
        $dumpfile("riscv_core.vcd");
        $dumpvars(0, RISCVCore_tb);
    end
    
endmodule
