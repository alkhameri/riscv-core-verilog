// Just the wiring between stages. Each stage keeps its own state and datapath.
module rv32_core #(
    parameter logic [31:0] RESET_PC = 32'h80000000
) (
    input logic clk, reset,
    output logic imem_request_valid,
    input logic imem_request_ready,
    output logic [31:0] imem_request_address,
    input logic imem_response_valid,
    output logic imem_response_ready,
    input logic [31:0] imem_response_data,
    input logic imem_response_error,
    output logic dmem_request_valid,
    input logic dmem_request_ready,
    output logic [31:0] dmem_request_address, dmem_request_data,
    output logic [3:0] dmem_request_strobe,
    output logic dmem_request_write, dmem_request_atomic, dmem_lock,
    input logic dmem_response_valid,
    output logic dmem_response_ready,
    input logic [31:0] dmem_response_data,
    input logic dmem_response_error,
    input logic reservation_invalidate,
    input logic software_interrupt, timer_interrupt, external_interrupt,
    input logic [63:0] time_value,
    output logic trace_valid,
    output logic [31:0] trace_pc, trace_instruction, trace_next_pc, trace_value,
    output logic [4:0] trace_rd,
    output logic trace_machine_mode,
    output logic trace_trap,
    output logic [31:0] trace_trap_pc, trace_cause, trace_trap_value
);
    import rv32_pkg::*;

    // Pipeline payloads and completion/bypass paths.
    execute_t decoded;
    memory_t execute_result;
    writeback_t completed;
    bypass_t memory_bypass, writeback_bypass;
    trap_t memory_fault;
    logic decode_valid, decode_ready, decode_error;
    logic execute_valid, execute_fire, execute_result_ready, execute_serial_pending;
    logic memory_valid, memory_ready, memory_done, memory_exception, memory_serial_pending;
    logic completion_valid, writeback_serial_pending;
    logic [31:0] decode_pc, decode_instruction, decode_prediction_pc;
    prediction_t decode_prediction;

    // Fetch prediction and recovery.
    logic [31:0] lookup_pc, predicted_pc, redirect_pc, architectural_pc;
    prediction_t prediction;
    predictor_update_t predictor_update;
    logic redirect, execute_redirect, architectural_redirect, fetch_allowed;
    logic prediction_enabled, prediction_clear, memory_predictor_invalidate;

    // Privilege state and serialized commits.
    logic machine_mode, data_machine_mode;
    logic [31:0] pmp_configuration, pmp_address [4];
    logic [11:0] csr_read_address, csr_write_address;
    logic [31:0] csr_read_data, csr_write_data, trap_vector, return_pc;
    logic csr_writes, csr_illegal, csr_commit, mret_commit, serial_commit;
    logic interrupt_pending;
    logic [31:0] interrupt_cause;
    logic reservation_valid;
    logic [31:0] reservation_address;

    // IF: protected fetch, buffering, and prediction.
    rv32_pmp instruction_protection (
        .address(lookup_pc), .size_bytes(3'd4), .machine_mode,
        .execute_access(1'b1), .write_access(1'b0), .configuration(pmp_configuration),
        .region_address(pmp_address), .allowed(fetch_allowed)
    );
    rv32_fetch #(.RESET_PC(RESET_PC)) fetch (
        .clk, .reset, .redirect, .redirect_pc, .lookup_pc, .predicted_pc, .prediction,
        .lookup_allowed(fetch_allowed),
        .request_valid(imem_request_valid), .request_ready(imem_request_ready),
        .request_address(imem_request_address), .response_valid(imem_response_valid),
        .response_ready(imem_response_ready), .response_data(imem_response_data),
        .response_error(imem_response_error), .instruction_valid(decode_valid),
        .instruction_ready(decode_ready), .instruction_pc(decode_pc),
        .instruction(decode_instruction), .instruction_prediction_pc(decode_prediction_pc),
        .instruction_prediction(decode_prediction), .instruction_error(decode_error)
    );
    rv32_predictor predictor (
        .clk, .reset, .invalidate(prediction_clear || memory_predictor_invalidate),
        .enable(prediction_enabled), .lookup_pc, .predicted_pc, .prediction,
        .update_valid(predictor_update.valid), .update_pc(predictor_update.pc),
        .update_target(predictor_update.target), .update_branch(predictor_update.branch),
        .update_jump(predictor_update.jump), .update_taken(predictor_update.taken),
        .update_push(predictor_update.push), .update_pop(predictor_update.pop),
        .update_prediction(predictor_update.prediction)
    );

    // ID: decoder and architectural register file, including WB-to-ID bypass.
    rv32_decode_stage decode_stage (
        .clk, .reset, .instruction_pc(decode_pc), .instruction(decode_instruction),
        .predicted_pc(decode_prediction_pc), .prediction(decode_prediction),
        .fetch_error(decode_error), .machine_mode, .writeback_bypass, .decoded
    );

    // EX: ID/EX state, forwarding, ALU, branch resolution, and fault detection.
    rv32_execute_stage execute_stage (
        .clk, .reset, .decoded, .decode_fire(decode_valid && decode_ready),
        .execute_fire, .flush(redirect), .architectural_redirect,
        .memory_ready, .memory_fault_pending(memory_valid && memory_exception),
        .memory_bypass, .writeback_bypass, .machine_mode, .data_machine_mode,
        .pmp_configuration, .pmp_address, .csr_read_address, .csr_writes,
        .csr_read_data, .return_pc, .csr_illegal,
        .reservation_valid, .reservation_invalidate, .reservation_address,
        .valid(execute_valid), .serial_pending(execute_serial_pending),
        .result_ready(execute_result_ready), .result(execute_result),
        .redirect_valid(execute_redirect), .predictor_update
    );

    // MEM: EX/MEM state, load/store bus, atomics, and precise completion.
    rv32_memory_stage memory_stage (
        .clk, .reset, .execute_fire, .execute_result,
        .trap_taken(trace_trap), .reservation_invalidate,
        .valid(memory_valid), .ready(memory_ready), .done(memory_done),
        .exception(memory_exception), .serial_pending(memory_serial_pending),
        .completion_valid, .completed, .bypass(memory_bypass), .fault(memory_fault),
        .csr_commit, .mret_commit, .serial_commit,
        .predictor_invalidate(memory_predictor_invalidate), .csr_write_address, .csr_write_data,
        .reservation_valid, .reservation_address,
        .request_valid(dmem_request_valid), .request_ready(dmem_request_ready),
        .request_address(dmem_request_address), .request_data(dmem_request_data),
        .request_strobe(dmem_request_strobe), .request_write(dmem_request_write),
        .request_atomic(dmem_request_atomic), .bus_lock(dmem_lock),
        .response_valid(dmem_response_valid), .response_ready(dmem_response_ready),
        .response_data(dmem_response_data), .response_error(dmem_response_error)
    );

    // WB: MEM/WB state, retirement trace, and the architectural resume PC.
    rv32_writeback_stage #(.RESET_PC(RESET_PC)) writeback_stage (
        .clk, .reset, .completion_valid, .completed, .trap_taken(trace_trap), .trap_vector,
        .bypass(writeback_bypass), .serial_pending(writeback_serial_pending), .architectural_pc,
        .trace_valid, .trace_pc, .trace_instruction, .trace_next_pc, .trace_value,
        .trace_rd, .trace_machine_mode
    );

    rv32_pipeline_control pipeline_control (
        .decode_serial(decoded.control.serial), .execute_valid, .execute_serial_pending,
        .execute_result_ready, .execute_redirect, .execute_next_pc(execute_result.next_pc),
        .memory_valid, .memory_ready, .memory_serial_pending, .serial_commit,
        .serial_next_pc(completed.next_pc), .memory_fault,
        .writeback_valid(trace_valid), .writeback_serial_pending,
        .interrupt_pending, .interrupt_cause, .architectural_pc, .trap_vector,
        .decode_ready, .execute_fire, .redirect, .architectural_redirect, .redirect_pc,
        .trap_valid(trace_trap), .trap_pc(trace_trap_pc),
        .trap_cause(trace_cause), .trap_value(trace_trap_value)
    );
    rv32_csr csrs (
        .clk, .reset, .read_address(csr_read_address), .read_write(csr_writes),
        .read_data(csr_read_data), .illegal_access(csr_illegal),
        .write_valid(csr_commit), .write_address(csr_write_address), .write_data(csr_write_data),
        .trap_valid(trace_trap), .trap_pc(trace_trap_pc), .trap_cause(trace_cause),
        .trap_value(trace_trap_value), .return_from_trap(mret_commit),
        .trap_vector, .return_pc, .machine_mode, .data_machine_mode,
        .software_interrupt, .timer_interrupt, .external_interrupt,
        .interrupt_pending, .interrupt_cause, .time_value, .retired(trace_valid),
        .branch_resolved(predictor_update.valid && (predictor_update.branch || predictor_update.jump)),
        .prediction_missed(execute_redirect), .memory_stalled(memory_valid && !memory_done),
        .prediction_enabled, .prediction_clear, .pmp_configuration, .pmp_address
    );
endmodule
