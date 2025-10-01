module DecodeFields(
    input  [31:0] Instr,
    output [6:0]  opcode,
    output [4:0]  rd,
    output [2:0]  funct3,
    output [4:0]  rs1,
    output [4:0]  rs2,
    output [6:0]  funct7
);
    assign opcode = Instr[6:0];
    assign rd     = Instr[11:7];
    assign funct3 = Instr[14:12];
    assign rs1    = Instr[19:15];
    assign rs2    = Instr[24:20];
    assign funct7 = Instr[31:25];
endmodule

module Control(
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,

    output reg       RegWrite,
    output reg       ALUSrc,     
    output reg       MemRead,
    output reg       MemWrite,
    output reg       MemToReg,   
    output reg       Branch,     
    output reg       Jump,     
    output reg       PCSrc,
    output reg [2:0] ImmSel,     // 3'b000 I, 001 S, 010 B, 011 U, 100 J
    output reg [3:0] ALUControl
);
    // opcodes
    localparam [6:0] OP_R     = 7'b0110011;
    localparam [6:0] OP_I     = 7'b0010011; // ALU-immediate (addi, ori, andi, etc.)
    localparam [6:0] OP_LOAD  = 7'b0000011; // lw
    localparam [6:0] OP_STORE = 7'b0100011; // sw
    localparam [6:0] OP_BRANCH= 7'b1100011; // branch
    localparam [6:0] OP_JAL   = 7'b1101111;
    localparam [6:0] OP_JALR  = 7'b1100111;
    localparam [6:0] OP_LUI   = 7'b0110111;
    localparam [6:0] OP_AUIPC = 7'b0010111;

    always @(*) begin
        RegWrite  = 1'b0;
        ALUSrc    = 1'b0;
        MemRead   = 1'b0;
        MemWrite  = 1'b0;
        MemToReg  = 1'b0;
        Branch    = 1'b0;
        Jump      = 1'b0;
        PCSrc     = 1'b0; // default is pc+4, 1 is pc+imm for b/j
        ImmSel    = 3'b000;
        ALUControl= 4'b0100; // default ADD

        case (opcode)
            // R type
            OP_R: begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b0;
                case ({funct7,funct3})
                    {7'b0000000,3'b000}: ALUControl = 4'b0100; // ADD
                    {7'b0100000,3'b000}: ALUControl = 4'b1000; // SUB
                    {7'b0000000,3'b110}: ALUControl = 4'b0010; // OR
                    {7'b0000000,3'b111}: ALUControl = 4'b0001; // AND
                    default: ALUControl = 4'b0100;
                endcase
            end

            // I type
            OP_I: begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ImmSel   = 3'b000; // I
                case (funct3)
                    3'b000: ALUControl = 4'b0100; // ADDI
                    3'b110: ALUControl = 4'b0010; // ORI
                    3'b111: ALUControl = 4'b0001; // ANDI
                    default: ALUControl = 4'b0100; // treat others as ADDI for now
                endcase
            end

            // load
            OP_LOAD: begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                MemRead  = 1'b1;
                MemToReg = 1'b1;
                ImmSel   = 3'b000;  // I
                ALUControl = 4'b0100; // base + offset
            end

            // store
            OP_STORE: begin
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ImmSel   = 3'b001; // S
                ALUControl = 4'b0100; // base + offset
            end

            // branch
            OP_BRANCH: begin
                Branch   = 1'b1;
                ImmSel   = 3'b010; // B
                ALUControl = 4'b1000; // SUB
                PCSrc = 1'b1;
            end

            // jump
            OP_JAL: begin
                Jump     = 1'b1;
                RegWrite = 1'b1; // rd = return address
                ImmSel   = 3'b100; // J
                PCSrc = 1'b1;
            end
            OP_JALR: begin
                Jump     = 1'b1;
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ImmSel   = 3'b000; // I (jalr imm)
                ALUControl = 4'b0100; // rs1 + imm 
                PCSrc = 1'b1;
            end

            // ---------------- U-type
            OP_LUI: begin
                RegWrite = 1'b1;
                ImmSel   = 3'b011; // U
                // datapath usually writes Imm directly; ALUControl not critical here
            end
            OP_AUIPC: begin
                RegWrite = 1'b1;
                ImmSel   = 3'b011; // U
                // ALU does PC + imm
                ALUControl = 4'b0100; // ADD
            end

            default: begin
            end
        endcase
    end
endmodule
