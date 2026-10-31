package rv32_pkg;
    typedef enum logic [3:0] {
        ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
        ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND, ALU_COPY
    } alu_op_t;

    typedef struct packed {
        logic illegal;
        logic uses_rs1, uses_rs2, writes_rd;
        logic immediate_b, pc_a;
        logic load, store, branch, jal, jalr;
        logic csr, mret, ecall, ebreak, fence_i, serial;
        logic muldiv, atomic, load_reserved, store_conditional;
        logic [4:0] atomic_operation;
        logic [2:0] funct3;
        logic [4:0] rs1, rs2, rd;
        logic [11:0] csr_address;
        logic [31:0] immediate;
        alu_op_t alu;
    } decode_t;

    // Preserve the table indices and votes from the actual fetch prediction.
    typedef struct packed {
        logic [7:0] global_index;
        logic [7:0] local_index;
        logic global_taken, local_taken;
    } prediction_t;

    // Pipeline payloads. Valid bits travel separately from instruction data.
    // The receiving stage owns the register: EX owns ID/EX, MEM owns EX/MEM,
    // and WB owns MEM/WB. The core top only connects these interfaces.
    typedef struct packed {
        decode_t control;
        logic [31:0] pc, instruction, predicted_pc, a, b;
        prediction_t prediction;
        logic fetch_error, machine;
    } execute_t;

    typedef struct packed {
        decode_t control;
        logic [31:0] pc, instruction, next_pc, result, store_data;
        logic exception;
        logic [31:0] cause, trap_value, csr_data;
        logic csr_write, machine, sc_success;
    } memory_t;

    typedef struct packed {
        logic [31:0] pc, instruction, next_pc, result;
        logic [4:0] rd;
        logic write_rd, serial, machine;
    } writeback_t;

    // A valid bypass contains a completed, nonfaulting register write.
    typedef struct packed {
        logic valid;
        logic [4:0] rd;
        logic [31:0] value;
    } bypass_t;

    typedef struct packed {
        logic valid;
        logic [31:0] pc, cause, value;
    } trap_t;

    typedef struct packed {
        logic valid;
        logic [31:0] pc, target;
        logic branch, jump, taken, push, pop;
        prediction_t prediction;
    } predictor_update_t;
endpackage
