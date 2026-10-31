module rv32_csr (
    input logic clk, reset,
    input logic [11:0] read_address,
    input logic read_write,
    output logic [31:0] read_data,
    output logic illegal_access,
    input logic write_valid,
    input logic [11:0] write_address,
    input logic [31:0] write_data,
    input logic trap_valid,
    input logic [31:0] trap_pc, trap_cause, trap_value,
    input logic return_from_trap,
    output logic [31:0] trap_vector, return_pc,
    output logic machine_mode, data_machine_mode,
    input logic software_interrupt, timer_interrupt, external_interrupt,
    output logic interrupt_pending,
    output logic [31:0] interrupt_cause,
    input logic [63:0] time_value,
    input logic retired, branch_resolved, prediction_missed, memory_stalled,
    output logic prediction_enabled, prediction_clear,
    output logic [31:0] pmp_configuration,
    output logic [31:0] pmp_address [4]
);
    logic [31:0] mstatus, mie, mip, mtvec, mscratch, mepc, mcause, mtval;
    logic [31:0] mcounteren, mcountinhibit;
    logic [63:0] cycle_count, instruction_count;
    logic [31:0] branch_count, miss_count, stall_count;
    logic [31:0] active_interrupts;
    logic known;
    logic unused_trap_alignment;
    assign unused_trap_alignment = ^trap_pc[1:0];

    assign mip = {20'b0, external_interrupt, 3'b0, timer_interrupt,
                  3'b0, software_interrupt, 3'b0};
    assign active_interrupts = mie & mip;
    assign interrupt_pending = (machine_mode ? mstatus[3] : 1'b1) && |active_interrupts;
    assign interrupt_cause = active_interrupts[11] ? 32'h8000000b :
                             active_interrupts[3] ? 32'h80000003 : 32'h80000007;
    assign trap_vector = {mtvec[31:2], 2'b0} +
        ((mtvec[1:0] == 1 && trap_cause[31]) ? {25'b0, trap_cause[4:0], 2'b0} : 32'b0);
    assign return_pc = mepc;
    assign data_machine_mode = machine_mode && (!mstatus[17] || mstatus[12:11] == 3);

    always_comb begin
        read_data = 0;
        known = 1;
        case (read_address)
            12'h300: read_data = mstatus;
            12'h301: read_data = 32'h40101101; // RV32, I, M, A, U
            12'h304: read_data = mie;
            12'h305: read_data = mtvec;
            12'h306: read_data = mcounteren;
            12'h310: read_data = 0; // little endian only
            12'h320: read_data = mcountinhibit;
            12'h340: read_data = mscratch;
            12'h341: read_data = mepc;
            12'h342: read_data = mcause;
            12'h343: read_data = mtval;
            12'h344: read_data = mip;
            12'h3a0: read_data = pmp_configuration;
            12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3: read_data = pmp_address[read_address[1:0]];
            12'hb00, 12'hc00: read_data = cycle_count[31:0];
            12'hb80, 12'hc80: read_data = cycle_count[63:32];
            12'hb02, 12'hc02: read_data = instruction_count[31:0];
            12'hb82, 12'hc82: read_data = instruction_count[63:32];
            12'hc01: read_data = time_value[31:0];
            12'hc81: read_data = time_value[63:32];
            12'h7c0: read_data = {31'b0, prediction_enabled};
            12'h7c1: read_data = branch_count;
            12'h7c2: read_data = miss_count;
            12'h7c3: read_data = stall_count;
            12'hf11, 12'hf12, 12'hf13, 12'hf14, 12'hf15: read_data = 0;
            default: known = 0;
        endcase
        illegal_access = !known || (!machine_mode && read_address[9:8] != 0) ||
                         (read_write && read_address[11:10] == 3);
        if (!machine_mode) begin
            case (read_address)
                12'hc00, 12'hc80: illegal_access = illegal_access || !mcounteren[0];
                12'hc01, 12'hc81: illegal_access = illegal_access || !mcounteren[1];
                12'hc02, 12'hc82: illegal_access = illegal_access || !mcounteren[2];
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            machine_mode <= 1;
            mstatus <= 0;
            mie <= 0;
            mtvec <= 0;
            mscratch <= 0;
            mepc <= 0;
            mcause <= 0;
            mtval <= 0;
            mcounteren <= 0;
            mcountinhibit <= 0;
            cycle_count <= 0;
            instruction_count <= 0;
            branch_count <= 0;
            miss_count <= 0;
            stall_count <= 0;
            prediction_enabled <= 1;
            prediction_clear <= 0;
            pmp_configuration <= 0;
            for (int i = 0; i < 4; i++) pmp_address[i] <= 0;
        end else begin
            prediction_clear <= 0;
            if (!mcountinhibit[0]) cycle_count <= cycle_count + 64'd1;
            if (retired && !mcountinhibit[2]) instruction_count <= instruction_count + 64'd1;
            if (branch_resolved) branch_count <= branch_count + 32'd1;
            if (prediction_missed) miss_count <= miss_count + 32'd1;
            if (memory_stalled) stall_count <= stall_count + 32'd1;
            if (write_valid) begin
                case (write_address)
                    12'h300: begin
                        mstatus <= write_data & 32'h00021888;
                        mstatus[12:11] <= write_data[12:11] == 3 ? 2'b11 : 2'b00;
                    end
                    12'h304: mie <= write_data & 32'h00000888;
                    12'h305: mtvec <= {write_data[31:2], 1'b0, write_data[1:0] == 1};
                    12'h306: mcounteren <= write_data & 32'd7;
                    12'h320: mcountinhibit <= write_data & 32'd5;
                    12'h340: mscratch <= write_data;
                    12'h341: mepc <= {write_data[31:2], 2'b0};
                    12'h342: mcause <= write_data;
                    12'h343: mtval <= write_data;
                    12'h3a0: begin
                        for (int i = 0; i < 4; i++) begin
                            if (!pmp_configuration[i*8+7]) begin
                                pmp_configuration[i*8 +: 8] <= write_data[i*8 +: 8] & 8'h9f;
                                // R=0,W=1 is reserved. Coerce it to R=0,W=0.
                                if (!write_data[i*8]) pmp_configuration[i*8+1] <= 0;
                            end
                        end
                    end
                    12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3: begin
                        for (int i = 0; i < 4; i++) begin
                            if (write_address[1:0] == 2'(i) && !pmp_configuration[i*8+7]) begin
                                if (i == 3) pmp_address[i] <= write_data;
                                else if (!(pmp_configuration[(i+1)*8+7] &&
                                           pmp_configuration[(i+1)*8+3 +: 2] == 1))
                                    pmp_address[i] <= write_data;
                            end
                        end
                    end
                    12'hb00: cycle_count[31:0] <= write_data;
                    12'hb80: cycle_count[63:32] <= write_data;
                    12'hb02: instruction_count[31:0] <= write_data;
                    12'hb82: instruction_count[63:32] <= write_data;
                    12'h7c0: begin
                        prediction_enabled <= write_data[0];
                        prediction_clear <= 1;
                    end
                    12'h7c1: branch_count <= write_data;
                    12'h7c2: miss_count <= write_data;
                    12'h7c3: stall_count <= write_data;
                    default: ; // Known WARL read-only fields ignore legal writes.
                endcase
            end
            if (trap_valid) begin
                mepc <= {trap_pc[31:2], 2'b0};
                mcause <= trap_cause;
                mtval <= trap_value;
                mstatus[7] <= mstatus[3];
                mstatus[3] <= 0;
                mstatus[12:11] <= machine_mode ? 2'b11 : 2'b00;
                machine_mode <= 1;
                prediction_clear <= 1;
            end else if (return_from_trap) begin
                machine_mode <= mstatus[12:11] == 3;
                mstatus[3] <= mstatus[7];
                mstatus[7] <= 1;
                mstatus[12:11] <= 0;
                if (mstatus[12:11] != 3) mstatus[17] <= 0;
                prediction_clear <= 1;
            end
        end
    end
endmodule
