// ID reads the architectural register file and packages the instruction for EX.
// Fetch retains the instruction until the pipeline controller accepts it.
module rv32_decode_stage (
    input logic clk, reset,
    input logic [31:0] instruction_pc, instruction, predicted_pc,
    input rv32_pkg::prediction_t prediction,
    input logic fetch_error, machine_mode,
    input rv32_pkg::bypass_t writeback_bypass,
    output rv32_pkg::execute_t decoded
);
    import rv32_pkg::*;
    decode_t control;
    logic [31:0] operand_a, operand_b;

    rv32_decode decoder (.instruction, .decoded(control));
    rv32_regfile register_file (
        .clk, .reset, .rs1(control.rs1), .rs2(control.rs2),
        .writeback(writeback_bypass), .read_a(operand_a), .read_b(operand_b)
    );

    assign decoded = '{
        control: control, pc: instruction_pc, instruction: instruction,
        predicted_pc: predicted_pc, a: operand_a, b: operand_b,
        prediction: prediction, fetch_error: fetch_error, machine: machine_mode
    };
endmodule
