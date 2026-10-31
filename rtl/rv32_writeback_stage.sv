// WB owns the MEM/WB register and next architectural PC used for interrupts.
// Trap redirection takes priority over retirement when updating that PC.
module rv32_writeback_stage #(
    parameter logic [31:0] RESET_PC = 32'h80000000
) (
    input logic clk, reset,
    input logic completion_valid,
    input rv32_pkg::writeback_t completed,
    input logic trap_taken,
    input logic [31:0] trap_vector,
    output rv32_pkg::bypass_t bypass,
    output logic serial_pending,
    output logic [31:0] architectural_pc,
    output logic trace_valid,
    output logic [31:0] trace_pc, trace_instruction, trace_next_pc, trace_value,
    output logic [4:0] trace_rd,
    output logic trace_machine_mode
);
    import rv32_pkg::*;
    writeback_t w;
    logic valid;

    assign bypass = '{valid: valid && w.write_rd && w.rd != 0, rd: w.rd, value: w.result};
    assign serial_pending = valid && w.serial;
    assign trace_valid = valid;
    assign trace_pc = w.pc;
    assign trace_instruction = w.instruction;
    assign trace_next_pc = w.next_pc;
    assign trace_value = w.result;
    assign trace_rd = w.write_rd ? w.rd : 5'b0;
    assign trace_machine_mode = w.machine;

    always_ff @(posedge clk) begin
        if (reset) begin
            w <= '0;
            valid <= 0;
            architectural_pc <= RESET_PC;
        end else begin
            valid <= completion_valid;
            if (completion_valid) w <= completed;
            if (valid) architectural_pc <= w.next_pc;
            if (trap_taken) architectural_pc <= trap_vector;
        end
    end
endmodule
