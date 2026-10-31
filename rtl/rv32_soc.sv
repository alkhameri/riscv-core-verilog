// Small single-hart system with a QEMU-virt-compatible polled console and CLINT
// register subset. There are no other bus masters, caches, or speculative data
// accesses. AMO read/write pairs therefore retain exclusive ownership of RAM.
module rv32_soc #(
    parameter string INIT_FILE = "",
    parameter int CLOCK_HZ = 50_000_000,
    parameter int TIMER_HZ = 10_000_000,
    parameter int UART_BAUD = 115200
) (
    input logic clk, reset,
    output logic uart_tx,
    output logic [31:0] retired_pc,
    output logic trap,
    output logic [31:0] trap_cause,
    output logic exit_valid,
    output logic [31:0] exit_code
);
    localparam int TIMER_DIVIDER = CLOCK_HZ / TIMER_HZ;
    logic i_request, i_ready, i_response, i_response_ready, i_error;
    logic [31:0] i_address, i_data;
    logic d_request, d_ready, d_response, d_response_ready, d_error;
    logic [31:0] d_address, d_write_data, d_read_data, ram_read_data, peripheral_data;
    logic [3:0] d_strobe;
    logic d_write, d_atomic, d_lock;
    logic i_ram, d_ram, d_uart, d_timer, d_exit, d_known, d_accept, response_ram;
    logic uart_ready, uart_valid;
    logic [63:0] mtime, mtimecmp;
    logic msip;
    logic [$clog2(TIMER_DIVIDER)-1:0] timer_divider;
    logic [31:0] write_mask;
    logic trace_valid, trace_machine;
    logic [31:0] trace_pc, trace_instruction, trace_next_pc, trace_value, trap_pc, trap_value;
    logic [4:0] trace_rd;
    logic unused_trace;
    assign unused_trace = ^{trace_instruction, trace_next_pc, trace_value, trace_rd,
                            trace_machine, trap_pc, trap_value, d_lock};

    rv32_core core (
        .clk, .reset, .imem_request_valid(i_request), .imem_request_ready(i_ready),
        .imem_request_address(i_address), .imem_response_valid(i_response),
        .imem_response_ready(i_response_ready), .imem_response_data(i_data), .imem_response_error(i_error),
        .dmem_request_valid(d_request), .dmem_request_ready(d_ready), .dmem_request_address(d_address),
        .dmem_request_data(d_write_data), .dmem_request_strobe(d_strobe), .dmem_request_write(d_write),
        .dmem_request_atomic(d_atomic), .dmem_lock(d_lock), .dmem_response_valid(d_response),
        .dmem_response_ready(d_response_ready), .dmem_response_data(d_read_data), .dmem_response_error(d_error),
        .reservation_invalidate(1'b0), .software_interrupt(msip), .timer_interrupt(mtime >= mtimecmp),
        .external_interrupt(1'b0), .time_value(mtime), .trace_valid, .trace_pc,
        .trace_instruction, .trace_next_pc, .trace_value, .trace_rd, .trace_machine_mode(trace_machine),
        .trace_trap(trap), .trace_trap_pc(trap_pc), .trace_cause(trap_cause), .trace_trap_value(trap_value)
    );
    assign i_ram = i_address[31:17] == 15'h4000 && i_address[1:0] == 0;
    assign d_ram = d_address[31:17] == 15'h4000;
    assign d_uart = d_address == 32'h10000000 || d_address == 32'h10000004;
    assign d_timer = d_address == 32'h02000000 || d_address == 32'h02004000 ||
                     d_address == 32'h02004004 || d_address == 32'h0200bff8 || d_address == 32'h0200bffc;
    assign d_exit = d_address == 32'h10000010;
    assign d_known = d_ram || (!d_atomic && (d_uart || d_timer || d_exit));
    assign i_ready = !reset && (!i_response || i_response_ready);
    assign d_ready = !reset && (!d_response || d_response_ready) &&
        !(d_request && d_known && d_write && d_address == 32'h10000000 && d_strobe[0] && !uart_ready);
    assign d_accept = d_request && d_ready;
    assign uart_valid = d_accept && d_known && d_write && d_address == 32'h10000000 && d_strobe[0];
    assign d_read_data = response_ram ? ram_read_data : peripheral_data;
    assign write_mask = {{8{d_strobe[3]}}, {8{d_strobe[2]}}, {8{d_strobe[1]}}, {8{d_strobe[0]}}};
    rv32_ram #(.INIT_FILE(INIT_FILE)) ram (
        .clk, .instruction_enable(i_request && i_ready && i_ram),
        .instruction_address(i_address[16:2]), .instruction_data(i_data),
        .data_enable(d_accept && d_ram), .data_address(d_address[16:2]),
        .write_data(d_write_data), .write_strobe(d_write ? d_strobe : 4'b0), .read_data(ram_read_data)
    );
    rv32_uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(UART_BAUD)) uart (
        .clk, .reset, .valid(uart_valid), .data(d_write_data[7:0]), .ready(uart_ready), .tx(uart_tx)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            i_response <= 0;
            i_error <= 0;
            d_response <= 0;
            d_error <= 0;
            response_ram <= 0;
            peripheral_data <= 0;
            mtime <= 0;
            mtimecmp <= '1;
            msip <= 0;
            timer_divider <= 0;
            retired_pc <= 32'h80000000;
            exit_valid <= 0;
            exit_code <= 0;
        end else begin
            if (trace_valid) retired_pc <= trace_pc;
            if (timer_divider == $clog2(TIMER_DIVIDER)'(TIMER_DIVIDER-1)) begin
                timer_divider <= 0;
                mtime <= mtime + 64'd1;
            end else timer_divider <= timer_divider + 1'b1;
            if (i_ready) begin
                i_response <= i_request;
                if (i_request) i_error <= !i_ram;
            end
            if (d_response_ready) d_response <= 0;
            if (d_accept) begin
                d_response <= 1;
                d_error <= !d_known;
                response_ram <= d_ram;
                peripheral_data <= 0;
                if (d_known) begin
                    case (d_address)
                        32'h02000000: peripheral_data <= {31'b0, msip};
                        32'h02004000: peripheral_data <= mtimecmp[31:0];
                        32'h02004004: peripheral_data <= mtimecmp[63:32];
                        32'h0200bff8: peripheral_data <= mtime[31:0];
                        32'h0200bffc: peripheral_data <= mtime[63:32];
                        32'h10000004: peripheral_data <= uart_ready ? 32'h00006000 : 32'b0;
                        default: ;
                    endcase
                    if (d_write) begin
                        case (d_address)
                            32'h02000000: if (d_strobe[0]) msip <= d_write_data[0];
                            32'h02004000: mtimecmp[31:0] <= (mtimecmp[31:0] & ~write_mask) | (d_write_data & write_mask);
                            32'h02004004: mtimecmp[63:32] <= (mtimecmp[63:32] & ~write_mask) | (d_write_data & write_mask);
                            32'h0200bff8: mtime[31:0] <= (mtime[31:0] & ~write_mask) | (d_write_data & write_mask);
                            32'h0200bffc: mtime[63:32] <= (mtime[63:32] & ~write_mask) | (d_write_data & write_mask);
                            32'h10000010: begin
                                exit_valid <= 1;
                                exit_code <= d_write_data & write_mask;
                            end
                            default: ;
                        endcase
                    end
                end
            end
        end
    end
endmodule
