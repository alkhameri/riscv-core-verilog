// MEM owns the EX/MEM register, data bus, AMO sequencer, and LR/SC reservation.
// Only this stage issues data transactions or commits CSR/privilege changes.
// A fault completes here without producing a register write or WB instruction.
module rv32_memory_stage (
    input logic clk, reset,
    input logic execute_fire,
    input rv32_pkg::memory_t execute_result,
    input logic trap_taken, reservation_invalidate,
    output logic valid, ready, done, exception, serial_pending,
    output logic completion_valid,
    output rv32_pkg::writeback_t completed,
    output rv32_pkg::bypass_t bypass,
    output rv32_pkg::trap_t fault,
    output logic csr_commit, mret_commit, serial_commit, predictor_invalidate,
    output logic [11:0] csr_write_address,
    output logic [31:0] csr_write_data,
    output logic reservation_valid,
    output logic [31:0] reservation_address,
    output logic request_valid,
    input logic request_ready,
    output logic [31:0] request_address, request_data,
    output logic [3:0] request_strobe,
    output logic request_write, request_atomic, bus_lock,
    input logic response_valid,
    output logic response_ready,
    input logic [31:0] response_data,
    input logic response_error
);
    import rv32_pkg::*;
    memory_t m;
    logic memory_operation, memory_issued, response_fire, sc_failed;
    logic atomic_write_phase;
    logic [31:0] atomic_old, atomic_new, shifted_load, memory_value;

    assign memory_operation = m.control.load || m.control.store || m.control.atomic;
    assign sc_failed = m.control.store_conditional &&
        (!m.sc_success || (!memory_issued && reservation_invalidate));
    assign request_valid = valid && memory_operation && !m.exception && !memory_issued && !sc_failed;
    assign request_address = {m.result[31:2], 2'b0};
    assign request_write = m.control.store || m.control.store_conditional || atomic_write_phase;
    assign request_atomic = m.control.atomic;
    assign bus_lock = valid && m.control.atomic && !m.exception && !sc_failed;
    assign request_data = atomic_write_phase ? atomic_new : m.store_data << {m.result[1:0], 3'b0};
    assign request_strobe = (m.control.funct3[1:0] == 0 ? 4'b0001 :
                            m.control.funct3[1:0] == 1 ? 4'b0011 : 4'b1111) << m.result[1:0];
    assign response_ready = valid && memory_issued;
    assign response_fire = response_ready && response_valid;
    assign done = valid && (!memory_operation || m.exception || sc_failed ||
        (response_fire && (!m.control.atomic || m.control.load_reserved ||
         m.control.store_conditional || atomic_write_phase || response_error)));
    assign exception = m.exception || (response_fire && response_error);
    assign ready = !valid || done;
    assign serial_pending = valid && m.control.serial;

    // Nonfaulting completion drives WB and same-cycle MEM-to-EX forwarding.
    assign completion_valid = done && !exception;
    assign completed = '{
        pc: m.pc, instruction: m.instruction, next_pc: m.next_pc,
        result: memory_value, rd: m.control.rd, write_rd: m.control.writes_rd,
        serial: m.control.serial, machine: m.machine
    };
    assign bypass = '{
        valid: completion_valid && m.control.writes_rd && m.control.rd != 0,
        rd: m.control.rd, value: memory_value
    };
    assign fault.valid = done && exception;
    assign fault.pc = m.pc;
    assign fault.cause = m.exception ? m.cause :
                        (m.control.load || m.control.load_reserved ? 32'd5 : 32'd7);
    assign fault.value = m.exception ? m.trap_value : m.result;
    assign csr_commit = completion_valid && m.csr_write;
    assign csr_write_address = m.control.csr_address;
    assign csr_write_data = m.csr_data;
    assign mret_commit = completion_valid && m.control.mret;
    assign serial_commit = completion_valid && m.control.serial && !m.control.atomic;
    assign predictor_invalidate = serial_commit && (m.control.fence_i || m.csr_write);

    always_comb begin
        shifted_load = response_data >> {m.result[1:0], 3'b0};
        memory_value = m.result;
        if (m.control.load) begin
            case (m.control.funct3)
                0: memory_value = {{24{shifted_load[7]}}, shifted_load[7:0]};
                1: memory_value = {{16{shifted_load[15]}}, shifted_load[15:0]};
                4: memory_value = {24'b0, shifted_load[7:0]};
                5: memory_value = {16'b0, shifted_load[15:0]};
                default: memory_value = shifted_load;
            endcase
        end
        if (m.control.atomic)
            memory_value = m.control.store_conditional ? {31'b0, sc_failed} :
                           m.control.load_reserved ? response_data : atomic_old;
        case (m.control.atomic_operation)
            5'h00: atomic_new = atomic_old + m.store_data;
            5'h01: atomic_new = m.store_data;
            5'h04: atomic_new = atomic_old ^ m.store_data;
            5'h08: atomic_new = atomic_old | m.store_data;
            5'h0c: atomic_new = atomic_old & m.store_data;
            5'h10: atomic_new = $signed(atomic_old) < $signed(m.store_data) ? atomic_old : m.store_data;
            5'h14: atomic_new = $signed(atomic_old) > $signed(m.store_data) ? atomic_old : m.store_data;
            5'h18: atomic_new = atomic_old < m.store_data ? atomic_old : m.store_data;
            default: atomic_new = atomic_old > m.store_data ? atomic_old : m.store_data;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            m <= '0;
            valid <= 0;
            memory_issued <= 0;
            atomic_write_phase <= 0;
            atomic_old <= 0;
            reservation_valid <= 0;
            reservation_address <= 0;
        end else begin
            if (request_valid && request_ready) memory_issued <= 1;
            if (response_fire && m.control.atomic && !done) begin
                atomic_old <= response_data;
                atomic_write_phase <= 1;
                memory_issued <= 0;
            end
            if (done) begin
                valid <= 0;
                memory_issued <= 0;
                atomic_write_phase <= 0;
            end
            // MEM can finish the old instruction and take the next one on this edge.
            if (execute_fire) begin
                m <= execute_result;
                valid <= 1;
                memory_issued <= 0;
                atomic_write_phase <= 0;
            end
            if (completion_valid && m.control.load_reserved) begin
                reservation_valid <= 1;
                reservation_address <= m.result;
            end
            if (reservation_invalidate || trap_taken || mret_commit ||
                (done && (m.control.store || (m.control.atomic && !m.control.load_reserved))))
                reservation_valid <= 0;
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk) disable iff (reset)
        request_valid && !request_ready |=> reset ||
        (request_valid && $stable({request_address, request_data, request_strobe, request_write})));
`endif
endmodule
