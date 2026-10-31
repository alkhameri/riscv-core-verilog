// EX owns the ID/EX register, operand forwarding, ALU, and iterative arithmetic.
// It resolves branches and detects faults but never issues a data transaction.
module rv32_execute_stage (
    input logic clk, reset,
    input rv32_pkg::execute_t decoded,
    input logic decode_fire, execute_fire, flush, architectural_redirect,
    input logic memory_ready, memory_fault_pending,
    input rv32_pkg::bypass_t memory_bypass, writeback_bypass,
    input logic machine_mode, data_machine_mode,
    input logic [31:0] pmp_configuration,
    input logic [31:0] pmp_address [4],
    output logic [11:0] csr_read_address,
    output logic csr_writes,
    input logic [31:0] csr_read_data, return_pc,
    input logic csr_illegal,
    input logic reservation_valid, reservation_invalidate,
    input logic [31:0] reservation_address,
    output logic valid, serial_pending, result_ready,
    output rv32_pkg::memory_t result,
    output logic redirect_valid,
    output rv32_pkg::predictor_update_t predictor_update
);
    import rv32_pkg::*;
    execute_t x;
    logic [31:0] operand_a, operand_b, alu_a, alu_b, alu_value;
    logic [31:0] effective_address, target_pc;
    logic [2:0] access_size;
    logic data_allowed, data_read_allowed;
    logic branch_taken, call_push, return_pop;
    logic execute_exception;
    logic [31:0] execute_cause, execute_trap_value;
    logic [31:0] csr_source, csr_write_data;
    logic muldiv_start, muldiv_busy, muldiv_done;
    logic [31:0] muldiv_result;

    rv32_forwarding forwarding (
        .rs1(x.control.rs1), .rs2(x.control.rs2),
        .uses_rs1(x.control.uses_rs1), .uses_rs2(x.control.uses_rs2),
        .saved_a(x.a), .saved_b(x.b), .memory_bypass, .writeback_bypass,
        .operand_a, .operand_b
    );
    rv32_alu alu (
        .operation(x.control.alu), .operand_a(alu_a), .operand_b(alu_b), .result(alu_value)
    );
    rv32_muldiv multiply_divide (
        .clk, .reset, .kill(architectural_redirect), .start(muldiv_start),
        .consume(execute_fire && x.control.muldiv), .operation(x.control.funct3),
        .operand_a, .operand_b, .busy(muldiv_busy), .done(muldiv_done), .result(muldiv_result)
    );
    rv32_pmp data_protection (
        .address(effective_address), .size_bytes(access_size), .machine_mode(data_machine_mode),
        .execute_access(1'b0),
        .write_access(x.control.store || (x.control.atomic && !x.control.load_reserved)),
        .configuration(pmp_configuration), .region_address(pmp_address), .allowed(data_allowed)
    );
    rv32_pmp atomic_read_protection (
        .address(effective_address), .size_bytes(3'd4), .machine_mode(data_machine_mode),
        .execute_access(1'b0), .write_access(1'b0), .configuration(pmp_configuration),
        .region_address(pmp_address), .allowed(data_read_allowed)
    );

    assign serial_pending = valid && x.control.serial;
    assign result_ready = !x.control.muldiv || muldiv_done;
    assign muldiv_start = valid && x.control.muldiv && memory_ready && !memory_fault_pending &&
                          !muldiv_busy && !muldiv_done && !architectural_redirect;
    assign csr_read_address = x.control.csr_address;
    assign redirect_valid = execute_fire && !execute_exception &&
        !(x.control.serial && !x.control.atomic) && result.next_pc != x.predicted_pc;
    assign predictor_update = '{
        valid: execute_fire && !execute_exception, pc: x.pc, target: target_pc,
        branch: x.control.branch, jump: x.control.jal || x.control.jalr,
        taken: branch_taken, push: call_push, pop: return_pop, prediction: x.prediction
    };

    always_comb begin
        alu_a = x.control.pc_a ? x.pc : operand_a;
        alu_b = x.control.immediate_b ? x.control.immediate : operand_b;
        effective_address = operand_a + x.control.immediate;
        access_size = x.control.funct3[1:0] == 0 ? 3'd1 :
                      x.control.funct3[1:0] == 1 ? 3'd2 : 3'd4;
        branch_taken = 0;
        case (x.control.funct3)
            0: branch_taken = operand_a == operand_b;
            1: branch_taken = operand_a != operand_b;
            4: branch_taken = $signed(operand_a) < $signed(operand_b);
            5: branch_taken = $signed(operand_a) >= $signed(operand_b);
            6: branch_taken = operand_a < operand_b;
            7: branch_taken = operand_a >= operand_b;
            default: ;
        endcase
        target_pc = x.control.jalr ? ((operand_a + x.control.immediate) & 32'hfffffffe) :
                    x.pc + x.control.immediate;
        call_push = (x.control.jal || x.control.jalr) && (x.control.rd == 1 || x.control.rd == 5);
        return_pop = x.control.jalr && (x.control.rs1 == 1 || x.control.rs1 == 5) &&
                     (!call_push || x.control.rd != x.control.rs1);
        csr_source = x.control.funct3[2] ? {27'b0, x.control.rs1} : operand_a;
        csr_writes = x.control.csr && (x.control.funct3[1:0] == 1 || x.control.rs1 != 0);
        case (x.control.funct3[1:0])
            1: csr_write_data = csr_source;
            2: csr_write_data = csr_read_data | csr_source;
            default: csr_write_data = csr_read_data & ~csr_source;
        endcase
    end

    // Check faults in priority order, then carry the winner into MEM.
    always_comb begin
        execute_exception = 0;
        execute_cause = 0;
        execute_trap_value = 0;
        if (x.fetch_error) begin
            execute_exception = 1;
            execute_cause = 1;
            execute_trap_value = x.pc;
        end else if (x.control.illegal || (x.control.csr && csr_illegal) ||
                     ((x.control.mret || x.instruction == 32'h10500073) && !machine_mode)) begin
            execute_exception = 1;
            execute_cause = 2;
            // For a 16-bit encoding, don't report the following halfword in mtval.
            execute_trap_value = x.instruction[1:0] == 3 ? x.instruction : {16'b0, x.instruction[15:0]};
        end else if (x.control.ecall || x.control.ebreak) begin
            execute_exception = 1;
            execute_cause = x.control.ebreak ? 32'd3 : (machine_mode ? 32'd11 : 32'd8);
            execute_trap_value = x.control.ebreak ? x.pc : 32'b0;
        end else if ((x.control.jal || x.control.jalr || (x.control.branch && branch_taken)) &&
                     target_pc[1:0] != 0) begin
            execute_exception = 1;
            execute_trap_value = target_pc;
        end else if (x.control.load || x.control.store || x.control.atomic) begin
            if ((access_size == 4 && effective_address[1:0] != 0) ||
                (access_size == 2 && effective_address[0])) begin
                execute_exception = 1;
                execute_cause = x.control.load || x.control.load_reserved ? 32'd4 : 32'd6;
            end else if (!data_allowed || (x.control.atomic && !x.control.store_conditional && !data_read_allowed)) begin
                execute_exception = 1;
                execute_cause = x.control.load || x.control.load_reserved ? 32'd5 : 32'd7;
            end
            execute_trap_value = effective_address;
        end

        result = '0;
        result.control = x.control;
        result.pc = x.pc;
        result.instruction = x.instruction;
        result.machine = x.machine;
        result.next_pc = x.pc + 32'd4;
        if (x.control.jal || x.control.jalr || (x.control.branch && branch_taken))
            result.next_pc = target_pc;
        if (x.control.mret) result.next_pc = return_pc;
        result.result = alu_value;
        if (x.control.jal || x.control.jalr) result.result = x.pc + 32'd4;
        if (x.control.csr) result.result = csr_read_data;
        if (x.control.muldiv) result.result = muldiv_result;
        result.store_data = operand_b;
        result.exception = execute_exception;
        result.cause = execute_cause;
        result.trap_value = execute_trap_value;
        result.csr_write = csr_writes;
        result.csr_data = csr_write_data;
        result.sc_success = reservation_valid && reservation_address == effective_address &&
                            !reservation_invalidate;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            x <= '0;
            valid <= 0;
        end else begin
            if (execute_fire) valid <= 0;
            if (valid) begin
                x.a <= operand_a;
                x.b <= operand_b;
            end
            if (decode_fire) begin
                x <= decoded;
                valid <= 1;
            end
            if (flush) valid <= 0;
        end
    end
endmodule
