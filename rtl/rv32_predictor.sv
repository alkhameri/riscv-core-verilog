// Tournament predictor using resolved history. Train only after EX resolves a
// nonfaulting instruction, so a squash doesn't need to undo history or RAS updates.
module rv32_predictor (
    input logic clk, reset, invalidate, enable,
    input logic [31:0] lookup_pc,
    output logic [31:0] predicted_pc,
    output rv32_pkg::prediction_t prediction,
    input logic update_valid,
    input logic [31:0] update_pc, update_target,
    input logic update_branch, update_jump, update_taken,
    input logic update_push, update_pop,
    input rv32_pkg::prediction_t update_prediction
);
    // 256-entry bimodal and gshare tables, with a per-PC tournament chooser.
    logic [1:0] bimodal [256], gshare [256], chooser [256];
    logic [7:0] history;
    // 32 sets, two ways. Full tags avoid false hits from unrelated addresses.
    logic valid [2][32];
    logic [24:0] tags [2][32];
    logic [31:0] targets [2][32];
    logic conditional [2][32], returns [2][32];
    logic victim [32];
    logic [31:0] return_stack [8];
    logic [2:0] stack_pointer;
    logic [3:0] stack_count;
    logic [4:0] lookup_set, update_set;
    logic hit, hit_way, update_way, direction;

    function automatic logic [1:0] train(input logic [1:0] value, input logic taken);
        if (taken) return value == 3 ? value : value + 2'd1;
        return value == 0 ? value : value - 2'd1;
    endfunction

    always_comb begin
        lookup_set = lookup_pc[6:2];
        update_set = update_pc[6:2];
        prediction.local_index = lookup_pc[9:2];
        prediction.global_index = lookup_pc[9:2] ^ history;
        prediction.local_taken = bimodal[prediction.local_index][1];
        prediction.global_taken = gshare[prediction.global_index][1];
        direction = chooser[prediction.local_index][1] ?
            prediction.global_taken : prediction.local_taken;
        hit = 1'b0;
        hit_way = 1'b0;
        for (int way = 0; way < 2; way++) begin
            if (valid[way][lookup_set] && tags[way][lookup_set] == lookup_pc[31:7]) begin
                hit = 1'b1;
                hit_way = 1'(way);
            end
        end
        predicted_pc = lookup_pc + 32'd4;
        if (enable && hit && (!conditional[hit_way][lookup_set] || direction)) begin
            predicted_pc = targets[hit_way][lookup_set];
            if (returns[hit_way][lookup_set] && stack_count != 0)
                predicted_pc = return_stack[stack_pointer - 3'd1];
        end
        update_way = victim[update_set];
        if (!valid[0][update_set]) update_way = 1'b0;
        else if (!valid[1][update_set]) update_way = 1'b1;
        for (int way = 0; way < 2; way++)
            if (valid[way][update_set] && tags[way][update_set] == update_pc[31:7])
                update_way = 1'(way);
    end

    always_ff @(posedge clk) begin
        if (reset || invalidate) begin
            history <= 0;
            stack_pointer <= 0;
            stack_count <= 0;
            for (int i = 0; i < 256; i++) begin
                bimodal[i] <= 2'b01;
                gshare[i] <= 2'b01;
                chooser[i] <= 2'b01;
            end
            for (int i = 0; i < 32; i++) begin
                valid[0][i] <= 0;
                valid[1][i] <= 0;
                victim[i] <= 0;
            end
        end else if (update_valid && enable) begin
            if (update_branch || update_jump) begin
                valid[update_way][update_set] <= 1'b1;
                tags[update_way][update_set] <= update_pc[31:7];
                targets[update_way][update_set] <= update_target;
                conditional[update_way][update_set] <= update_branch;
                returns[update_way][update_set] <= update_pop;
                victim[update_set] <= ~update_way;
            end else begin
                // This PC may hold different code now. Drop its old target entry.
                for (int way = 0; way < 2; way++)
                    if (valid[way][update_set] && tags[way][update_set] == update_pc[31:7])
                        valid[way][update_set] <= 1'b0;
            end
            if (update_branch) begin
                bimodal[update_prediction.local_index] <=
                    train(bimodal[update_prediction.local_index], update_taken);
                gshare[update_prediction.global_index] <=
                    train(gshare[update_prediction.global_index], update_taken);
                if (update_prediction.local_taken != update_prediction.global_taken)
                    chooser[update_prediction.local_index] <=
                        train(chooser[update_prediction.local_index],
                              update_prediction.global_taken == update_taken);
                history <= {history[6:0], update_taken};
            end
            // Support x1/x5 call hints, including pop-then-push coroutines.
            if (update_push && update_pop && stack_count != 0) begin
                return_stack[stack_pointer - 3'd1] <= update_pc + 32'd4;
            end else if (update_push) begin
                return_stack[stack_pointer] <= update_pc + 32'd4;
                stack_pointer <= stack_pointer + 3'd1;
                if (stack_count < 8) stack_count <= stack_count + 4'd1;
            end else if (update_pop && stack_count != 0) begin
                stack_pointer <= stack_pointer - 3'd1;
                stack_count <= stack_count - 4'd1;
            end
        end
    end
endmodule
