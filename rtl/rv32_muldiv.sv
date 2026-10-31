// Fixed 32-iteration shift/add multiply and restoring divide. No inferred
// combinational multiplier or divider sits on the single-cycle execute path.
module rv32_muldiv (
    input logic clk, reset, kill, start, consume,
    input logic [2:0] operation,
    input logic [31:0] operand_a, operand_b,
    output logic busy, done,
    output logic [31:0] result
);
    logic [2:0] saved_operation;
    logic [5:0] iteration;
    logic negative_product, negative_quotient, negative_remainder;
    logic [63:0] product, multiplicand, product_step, signed_product;
    logic [31:0] multiplier, divisor, quotient, quotient_step;
    logic [31:0] remainder;
    logic [32:0] remainder_step;
    logic sign_a, sign_b;
    logic [31:0] magnitude_a, magnitude_b;

    always_comb begin
        sign_a = operand_a[31] && (operation == 1 || operation == 2 || operation == 4 || operation == 6);
        sign_b = operand_b[31] && (operation == 1 || operation == 4 || operation == 6);
        magnitude_a = sign_a ? -operand_a : operand_a;
        magnitude_b = sign_b ? -operand_b : operand_b;
        product_step = product + (multiplier[0] ? multiplicand : 64'b0);
        signed_product = negative_product ? -product_step : product_step;
        remainder_step = {remainder[31:0], quotient[31]};
        quotient_step = {quotient[30:0], 1'b0};
        if (remainder_step >= {1'b0, divisor}) begin
            remainder_step = remainder_step - {1'b0, divisor};
            quotient_step[0] = 1;
        end
    end

    always_ff @(posedge clk) begin
        if (reset || kill) begin
            busy <= 0;
            done <= 0;
            result <= 0;
            saved_operation <= 0;
            iteration <= 0;
            negative_product <= 0;
            negative_quotient <= 0;
            negative_remainder <= 0;
            product <= 0;
            multiplicand <= 0;
            multiplier <= 0;
            divisor <= 0;
            quotient <= 0;
            remainder <= 0;
        end else begin
            if (consume) done <= 0;
            if (start && !busy && !done) begin
                saved_operation <= operation;
                iteration <= 0;
                negative_product <= sign_a ^ sign_b;
                negative_quotient <= (sign_a ^ sign_b) && operand_b != 0;
                negative_remainder <= sign_a;
                product <= 0;
                multiplicand <= {32'b0, magnitude_a};
                multiplier <= magnitude_b;
                divisor <= magnitude_b;
                quotient <= magnitude_a;
                remainder <= 0;
                busy <= 1;
            end else if (busy) begin
                iteration <= iteration + 6'd1;
                product <= product_step;
                multiplicand <= multiplicand << 1;
                multiplier <= multiplier >> 1;
                remainder <= remainder_step[31:0];
                quotient <= quotient_step;
                if (iteration == 31) begin
                    busy <= 0;
                    done <= 1;
                    if (!saved_operation[2])
                        result <= saved_operation == 0 ? signed_product[31:0] : signed_product[63:32];
                    else if (saved_operation[1])
                        result <= negative_remainder ? -remainder_step[31:0] : remainder_step[31:0];
                    else
                        result <= negative_quotient ? -quotient_step : quotient_step;
                end
            end
        end
    end
endmodule
