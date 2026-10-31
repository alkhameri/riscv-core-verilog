// One outstanding memory transaction plus a held request and a two-entry FIFO.
// Once we offer a request, keep it there until the bus accepts it, even if we
// redirect. Let the old reply come back, then discard it if it's stale.
module rv32_fetch #(
    parameter logic [31:0] RESET_PC = 0
) (
    input logic clk, reset,
    input logic redirect,
    input logic [31:0] redirect_pc,
    output logic [31:0] lookup_pc,
    input logic [31:0] predicted_pc,
    input rv32_pkg::prediction_t prediction,
    input logic lookup_allowed,
    output logic request_valid,
    input logic request_ready,
    output logic [31:0] request_address,
    input logic response_valid,
    output logic response_ready,
    input logic [31:0] response_data,
    input logic response_error,
    output logic instruction_valid,
    input logic instruction_ready,
    output logic [31:0] instruction_pc, instruction, instruction_prediction_pc,
    output rv32_pkg::prediction_t instruction_prediction,
    output logic instruction_error
);
    import rv32_pkg::*;
    typedef struct packed {
        logic [31:0] pc, next_pc;
        prediction_t prediction;
        logic fault;
    } request_t;
    typedef struct packed {
        request_t request;
        logic [31:0] instruction;
        logic fault;
    } entry_t;
    request_t offer, pending;
    logic offer_valid, offer_stale, pending_valid, pending_stale;
    entry_t queue [2];
    logic read_pointer, write_pointer;
    logic [1:0] count;
    logic request_fire, response_fire, enqueue, dequeue, pending_ready;

    assign instruction_valid = count != 0;
    assign instruction_pc = queue[read_pointer].request.pc;
    assign instruction_prediction_pc = queue[read_pointer].request.next_pc;
    assign instruction_prediction = queue[read_pointer].request.prediction;
    assign instruction = queue[read_pointer].instruction;
    assign instruction_error = queue[read_pointer].fault;
    assign dequeue = instruction_valid && instruction_ready;
    assign response_ready = pending_valid && !pending.fault &&
        (pending_stale || redirect || count < 2 || dequeue);
    assign response_fire = pending_valid && (pending.fault || response_valid) &&
        (pending_stale || redirect || count < 2 || dequeue);
    assign pending_ready = !pending_valid || response_fire;
    assign request_valid = offer_valid && !offer.fault && pending_ready;
    assign request_address = offer.pc;
    assign request_fire = offer_valid && pending_ready && (offer.fault || request_ready);
    assign enqueue = response_fire && !pending_stale && !redirect;

    always_ff @(posedge clk) begin
        if (reset) begin
            lookup_pc <= RESET_PC;
            offer_valid <= 0;
            offer_stale <= 0;
            pending_valid <= 0;
            pending_stale <= 0;
            offer <= '0;
            pending <= '0;
            count <= 0;
            read_pointer <= 0;
            write_pointer <= 0;
        end else begin
            if (response_fire) pending_valid <= 0;
            if (request_fire) begin
                pending <= offer;
                pending_valid <= 1;
                pending_stale <= offer_stale || redirect;
                offer_valid <= 0;
            end
            if (redirect) begin
                lookup_pc <= redirect_pc;
                if (pending_valid && !request_fire) pending_stale <= 1;
                if (offer_valid && !request_fire) offer_stale <= 1;
                count <= 0;
                read_pointer <= 0;
                write_pointer <= 0;
            end else begin
                if (!offer_valid || request_fire) begin
                    offer <= '{pc: lookup_pc, next_pc: predicted_pc,
                        prediction: prediction, fault: !lookup_allowed};
                    offer_valid <= 1;
                    offer_stale <= 0;
                    lookup_pc <= predicted_pc;
                end
                case ({enqueue, dequeue})
                    2'b10: count <= count + 2'd1;
                    2'b01: count <= count - 2'd1;
                    default: ;
                endcase
                if (enqueue) begin
                    queue[write_pointer] <= '{request: pending,
                        instruction: pending.fault ? 32'b0 : response_data,
                        fault: pending.fault || response_error};
                    write_pointer <= ~write_pointer;
                end
                if (dequeue) read_pointer <= ~read_pointer;
            end
        end
    end

`ifndef SYNTHESIS
    assert property (@(posedge clk) disable iff (reset)
        request_valid && !request_ready |=> reset ||
        (request_valid && $stable(request_address)));
`endif
endmodule
