// Four PMP entries, 4-byte granularity, TOR/NA4/NAPOT and first-match priority.
// The entire access must fit in its first overlapping region.
module rv32_pmp (
    input logic [31:0] address,
    input logic [2:0] size_bytes,
    input logic machine_mode, execute_access, write_access,
    input logic [31:0] configuration,
    input logic [31:0] region_address [4],
    output logic allowed
);
    logic matched;
    logic [7:0] cfg;
    logic unused_reserved_configuration;
    assign unused_reserved_configuration = ^cfg[6:5];
    logic [33:0] first_byte, last_byte, lower, upper, mask;
    always_comb begin
        first_byte = {2'b0, address};
        last_byte = first_byte + {31'b0, size_bytes} - 34'd1;
        allowed = machine_mode;
        matched = 0;
        cfg = 0;
        lower = 0;
        upper = 0;
        mask = 0;
        for (int i = 0; i < 4; i++) begin
            cfg = configuration[i*8 +: 8];
            lower = 0;
            upper = 0;
            mask = 0;
            case (cfg[4:3])
                2'b01: begin
                    if (i != 0) lower = {region_address[i-1], 2'b0};
                    upper = {region_address[i], 2'b0}; // exclusive bound
                end
                2'b10: begin
                    lower = {region_address[i], 2'b0};
                    upper = lower + 34'd4;
                end
                2'b11: begin
                    mask = {region_address[i] ^ (region_address[i] + 32'd1), 2'b11};
                    lower = {region_address[i], 2'b0} & ~mask;
                    // Compare inclusively for NAPOT, including the whole space.
                    upper = lower | mask;
                end
                default: ;
            endcase
            if (!matched && cfg[4:3] != 0 && (cfg[4:3] != 1 || upper > lower) && last_byte >= lower &&
                (cfg[4:3] == 3 ? first_byte <= upper : first_byte < upper)) begin
                matched = 1;
                allowed = first_byte >= lower &&
                    (cfg[4:3] == 3 ? last_byte <= upper : last_byte < upper) &&
                    ((machine_mode && !cfg[7]) ||
                     (execute_access ? cfg[2] : (write_access ? cfg[1] : cfg[0])));
            end
        end
    end
endmodule
