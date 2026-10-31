module rv32_decode (
    input  logic [31:0] instruction,
    output rv32_pkg::decode_t decoded
);
    import rv32_pkg::*;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    always_comb begin
        decoded = '0;
        decoded.alu = ALU_ADD;
        decoded.rs1 = instruction[19:15];
        decoded.rs2 = instruction[24:20];
        decoded.rd = instruction[11:7];
        decoded.funct3 = funct3;
        decoded.csr_address = instruction[31:20];
        decoded.immediate = {{20{instruction[31]}}, instruction[31:20]};
        case (opcode)
            7'h37, 7'h17: begin // LUI, AUIPC
                decoded.writes_rd = 1'b1;
                decoded.immediate_b = 1'b1;
                decoded.pc_a = opcode == 7'h17;
                decoded.alu = opcode == 7'h37 ? ALU_COPY : ALU_ADD;
                decoded.immediate = {instruction[31:12], 12'b0};
            end
            7'h6f: begin // JAL
                decoded.jal = 1'b1;
                decoded.writes_rd = 1'b1;
                decoded.immediate = {{11{instruction[31]}}, instruction[31],
                    instruction[19:12], instruction[20], instruction[30:21], 1'b0};
            end
            7'h67: begin // JALR
                decoded.jalr = 1'b1;
                decoded.uses_rs1 = 1'b1;
                decoded.writes_rd = 1'b1;
                decoded.illegal = funct3 != 0;
            end
            7'h63: begin
                decoded.branch = 1'b1;
                decoded.uses_rs1 = 1'b1;
                decoded.uses_rs2 = 1'b1;
                decoded.illegal = funct3 == 3'b010 || funct3 == 3'b011;
                decoded.immediate = {{19{instruction[31]}}, instruction[31],
                    instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            end
            7'h03: begin
                decoded.load = 1'b1;
                decoded.uses_rs1 = 1'b1;
                decoded.writes_rd = 1'b1;
                decoded.immediate_b = 1'b1;
                decoded.illegal = !(funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101});
            end
            7'h23: begin
                decoded.store = 1'b1;
                decoded.uses_rs1 = 1'b1;
                decoded.uses_rs2 = 1'b1;
                decoded.immediate_b = 1'b1;
                decoded.illegal = funct3 > 3'b010;
                decoded.immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end
            7'h2f: begin
                decoded.atomic = 1'b1;
                decoded.atomic_operation = instruction[31:27];
                decoded.load_reserved = instruction[31:27] == 5'b00010;
                decoded.store_conditional = instruction[31:27] == 5'b00011;
                decoded.uses_rs1 = 1'b1;
                decoded.uses_rs2 = !decoded.load_reserved;
                decoded.writes_rd = 1'b1;
                decoded.immediate_b = 1'b1;
                decoded.immediate = 0;
                decoded.serial = 1'b1;
                decoded.illegal = funct3 != 2 ||
                    !(instruction[31:27] inside {5'h00, 5'h01, 5'h02, 5'h03,
                        5'h04, 5'h08, 5'h0c, 5'h10, 5'h14, 5'h18, 5'h1c}) ||
                    (decoded.load_reserved && instruction[24:20] != 0);
            end
            7'h13, 7'h33: begin
                decoded.uses_rs1 = 1'b1;
                decoded.uses_rs2 = opcode == 7'h33;
                decoded.writes_rd = 1'b1;
                decoded.immediate_b = opcode == 7'h13;
                decoded.muldiv = opcode == 7'h33 && funct7 == 7'h01;
                case (funct3)
                    3'b000: decoded.alu = opcode == 7'h33 && instruction[30] ? ALU_SUB : ALU_ADD;
                    3'b001: decoded.alu = ALU_SLL;
                    3'b010: decoded.alu = ALU_SLT;
                    3'b011: decoded.alu = ALU_SLTU;
                    3'b100: decoded.alu = ALU_XOR;
                    3'b101: decoded.alu = instruction[30] ? ALU_SRA : ALU_SRL;
                    3'b110: decoded.alu = ALU_OR;
                    3'b111: decoded.alu = ALU_AND;
                endcase
                if (opcode == 7'h33 && !decoded.muldiv)
                    decoded.illegal = !(funct7 == 0 ||
                        (funct7 == 7'h20 && (funct3 == 0 || funct3 == 5)));
                if (opcode == 7'h13 && funct3 == 1)
                    decoded.illegal = funct7 != 0;
                if (opcode == 7'h13 && funct3 == 5)
                    decoded.illegal = !(funct7 == 0 || funct7 == 7'h20);
            end
            7'h0f: begin
                decoded.serial = 1'b1;
                decoded.fence_i = funct3 == 1;
                decoded.illegal = funct3 > 1;
            end
            7'h73: begin
                decoded.serial = 1'b1;
                if (funct3 != 0) begin
                    decoded.csr = 1'b1;
                    decoded.uses_rs1 = !funct3[2];
                    decoded.writes_rd = 1'b1;
                    decoded.illegal = funct3 == 4;
                end else begin
                    case (instruction)
                        32'h00000073: decoded.ecall = 1'b1;
                        32'h00100073: decoded.ebreak = 1'b1;
                        32'h30200073: decoded.mret = 1'b1;
                        32'h10500073: ; // WFI is a legal hint in machine mode.
                        default: decoded.illegal = 1'b1;
                    endcase
                end
            end
            default: decoded.illegal = 1'b1;
        endcase
    end
endmodule
