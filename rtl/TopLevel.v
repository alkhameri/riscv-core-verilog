module RISCVCore(
    input clk,
    input rst
);
    // Program Counter
    reg [31:0] PC;
    
    // Instruction signals
    wire [31:0] Instr;
    wire [6:0] opcode;
    wire [4:0] rd, rs1, rs2;
    wire [2:0] funct3;
    wire [6:0] funct7;
    
    // Control signals
    wire RegWrite, ALUSrc, MemRead, MemWrite, MemToReg, Branch, Jump, PCSrc;
    wire [2:0] ImmSel;
    wire [3:0] ALUControl;
    
    // Data paths
    wire [31:0] PCplus4, PCTarget, PCNext;
    wire [31:0] Imm;
    wire [31:0] ReadData1, ReadData2, WriteData;
    wire [31:0] SrcB, ALUResult;
    wire [31:0] ReadData;
    wire zero;
    
    // PC update
    always @(posedge clk or posedge rst) begin
        if (rst)
            PC <= 32'b0;
        else
            PC <= PCNext;
    end
    
    // Instruction Memory
    InstrMem instr_mem(
        .PC(PC),
        .Instr(Instr)
    );
    
    // Instruction Decode
    DecodeFields decode(
        .Instr(Instr),
        .opcode(opcode),
        .rd(rd),
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .funct7(funct7)
    );
    
    // Control Unit
    Control control(
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .RegWrite(RegWrite),
        .ALUSrc(ALUSrc),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .MemToReg(MemToReg),
        .Branch(Branch),
        .Jump(Jump),
        .PCSrc(PCSrc),
        .ImmSel(ImmSel),
        .ALUControl(ALUControl)
    );
    
    // PC+4 Adder
    PCplus4 pc_plus4(
        .PC(PC),
        .PCplus4(PCplus4)
    );
    
    // Immediate Extender
    Extend extend(
        .Instr(Instr[31:7]),
        .ImmSel(ImmSel),
        .Imm(Imm)
    );
    
    // PC + Immediate Adder
    PCplusimm pc_plus_imm(
        .PC(PC),
        .Imm(Imm),
        .PCTarget(PCTarget)
    );
    
    // PC Mux
    PCmux pc_mux(
        .PCplus4(PCplus4),
        .PCTarget(PCTarget),
        .PCSrc(PCSrc),
        .PCNext(PCNext)
    );
    
    // Register File
    RegisterFile reg_file(
        .clk(clk),
        .rst(rst),
        .RegWrite(RegWrite),
        .Rd(rd),
        .Rs1(rs1),
        .Rs2(rs2),
        .WriteData(WriteData),
        .ReadData1(ReadData1),
        .ReadData2(ReadData2)
    );
    
    // ALU Source Mux
    ALUmux alu_mux(
        .Reg2(ReadData2),
        .Imm(Imm),
        .ALUSrc(ALUSrc),
        .SrcB(SrcB)
    );
    
    // ALU
    ALU alu(
        .SrcA(ReadData1),
        .SrcB(SrcB),
        .ALUControl(ALUControl),
        .ALUResult(ALUResult),
        .zero(zero)
    );
    
    // Data Memory
    DataMem data_mem(
        .clk(clk),
        .MemWrite(MemWrite),
        .ALUResult(ALUResult),
        .WriteData(ReadData2),
        .ReadData(ReadData)
    );
    
    // Write-back Mux
    WBmux wb_mux(
        .ALUResult(ALUResult),
        .ReadData(ReadData),
        .ResultSrc(MemToReg),
        .Result(WriteData)
    );
    
endmodule
