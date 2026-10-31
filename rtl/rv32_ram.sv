// Shared instruction/data RAM, with two registered read ports and byte writes.
// There is no reset loop on the memory ports, preserving block-RAM inference.
module rv32_ram #(
    parameter int WORDS = 32768,
    parameter string INIT_FILE = ""
) (
    input logic clk,
    input logic instruction_enable,
    input logic [$clog2(WORDS)-1:0] instruction_address,
    output logic [31:0] instruction_data,
    input logic data_enable,
    input logic [$clog2(WORDS)-1:0] data_address,
    input logic [31:0] write_data,
    input logic [3:0] write_strobe,
    output logic [31:0] read_data
);
    (* ramstyle = "M9K, no_rw_check" *) logic [31:0] memory [WORDS];
`ifndef SYNTHESIS
    string simulation_image;
`endif
    initial begin
        for (int i = 0; i < WORDS; i++) memory[i] = 0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, memory);
`ifndef SYNTHESIS
        if ($value$plusargs("mem=%s", simulation_image)) $readmemh(simulation_image, memory);
`endif
    end
    always_ff @(posedge clk) begin
        if (instruction_enable) instruction_data <= memory[instruction_address];
    end
    always_ff @(posedge clk) begin
        if (data_enable) begin
            read_data <= memory[data_address];
            for (int lane = 0; lane < 4; lane++)
                if (write_strobe[lane]) memory[data_address][lane*8 +: 8] <= write_data[lane*8 +: 8];
        end
    end
endmodule
