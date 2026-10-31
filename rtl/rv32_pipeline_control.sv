// Keep stall and flush decisions together. A trap or serial commit wins over EX.
// Drain older work before taking an interrupt or letting a serial instruction in.
module rv32_pipeline_control (
    input logic decode_serial,
    input logic execute_valid, execute_serial_pending, execute_result_ready,
    input logic execute_redirect,
    input logic [31:0] execute_next_pc,
    input logic memory_valid, memory_ready, memory_serial_pending,
    input logic serial_commit,
    input logic [31:0] serial_next_pc,
    input rv32_pkg::trap_t memory_fault,
    input logic writeback_valid, writeback_serial_pending,
    input logic interrupt_pending,
    input logic [31:0] interrupt_cause, architectural_pc, trap_vector,
    output logic decode_ready, execute_fire,
    output logic redirect, architectural_redirect,
    output logic [31:0] redirect_pc,
    output logic trap_valid,
    output logic [31:0] trap_pc, trap_cause, trap_value
);
    logic interrupt_take;

    assign interrupt_take = interrupt_pending && !execute_valid && !memory_valid && !writeback_valid;
    assign trap_valid = memory_fault.valid || interrupt_take;
    assign trap_pc = interrupt_take ? architectural_pc : memory_fault.pc;
    assign trap_cause = interrupt_take ? interrupt_cause : memory_fault.cause;
    assign trap_value = interrupt_take ? 32'b0 : memory_fault.value;
    assign architectural_redirect = trap_valid || serial_commit;
    assign execute_fire = execute_valid && memory_ready && !architectural_redirect && execute_result_ready;
    assign redirect = architectural_redirect || execute_redirect;
    assign redirect_pc = trap_valid ? trap_vector : serial_commit ? serial_next_pc : execute_next_pc;
    assign decode_ready = (!execute_valid || execute_fire) && !redirect && !interrupt_pending &&
        !execute_serial_pending && !memory_serial_pending && !writeback_serial_pending &&
        (!decode_serial || (!execute_valid && !memory_valid && !writeback_valid));
endmodule
