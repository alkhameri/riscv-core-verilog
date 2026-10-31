#include "Vrv32_core.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr uint32_t ram_base = 0x80000000;
constexpr uint32_t ram_size = 128 * 1024;
constexpr uint32_t uart_base = 0x10000000;
constexpr uint32_t exit_address = 0x10000010;

std::string hex(uint32_t n) {
    std::ostringstream s;
    s << "0x" << std::hex << std::setw(8) << std::setfill('0') << n;
    return s.str();
}
void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}
int32_t sext(uint32_t n, unsigned bits) {
    const uint32_t sign = 1u << (bits - 1);
    return static_cast<int32_t>((n ^ sign) - sign);
}
uint32_t read32(const std::vector<uint8_t>& data, size_t offset) {
    require(offset + 4 <= data.size(), "read outside image");
    return uint32_t(data[offset]) | uint32_t(data[offset+1]) << 8 |
           uint32_t(data[offset+2]) << 16 | uint32_t(data[offset+3]) << 24;
}
void write32(std::vector<uint8_t>& data, size_t offset, uint32_t value, unsigned strobe = 15) {
    require(offset + 4 <= data.size(), "write outside image");
    for (unsigned i = 0; i < 4; ++i)
        if (strobe & (1u << i)) data[offset+i] = uint8_t(value >> (i*8));
}
bool in_ram(uint32_t address) { return address >= ram_base && address - ram_base < ram_size; }

// Independent instruction-level model. It observes architectural retirement,
// never DUT register arrays, decoder outputs, bypasses, or pipeline internals.
struct Reference {
    std::array<uint32_t,32> r{};
    std::vector<uint8_t> memory;
    uint32_t pc = ram_base, reservation = 0;
    bool reserved = false;
    explicit Reference(const std::vector<uint8_t>& image) : memory(image) {}

    void step(const Vrv32_core& dut) {
        const uint32_t insn = read32(memory, pc - ram_base);
        require(dut.trace_pc == pc, "retirement PC: expected " + hex(pc) + " got " + hex(dut.trace_pc));
        require(dut.trace_instruction == insn, "retired instruction mismatch at " + hex(pc));
        unsigned op = insn & 127, rd = (insn >> 7) & 31, f3 = (insn >> 12) & 7;
        unsigned rs1 = (insn >> 15) & 31, rs2 = (insn >> 20) & 31, f7 = insn >> 25;
        uint32_t a = r[rs1], b = r[rs2], result = 0, next = pc + 4;
        int32_t imm = sext(insn >> 20, 12);
        bool writes = true;
        auto load = [&](uint32_t address, unsigned bytes) {
            require(in_ram(address) && in_ram(address + bytes - 1), "reference load address " + hex(address));
            uint32_t value = 0;
            for (unsigned i = 0; i < bytes; ++i) value |= uint32_t(memory[address - ram_base + i]) << (i*8);
            return value;
        };
        auto store = [&](uint32_t address, unsigned bytes, uint32_t value) {
            if (address == exit_address) return;
            require(in_ram(address) && in_ram(address + bytes - 1), "reference store address " + hex(address));
            for (unsigned i = 0; i < bytes; ++i) memory[address - ram_base + i] = uint8_t(value >> (i*8));
        };
        switch (op) {
        case 0x37: result = insn & 0xfffff000; break;
        case 0x17: result = pc + (insn & 0xfffff000); break;
        case 0x6f:
            result = pc + 4;
            next = pc + sext(((insn >> 31) << 20) | (((insn >> 12) & 255) << 12) |
                             (((insn >> 20) & 1) << 11) | (((insn >> 21) & 1023) << 1), 21);
            break;
        case 0x67: result = pc + 4; next = (a + imm) & ~1u; break;
        case 0x63: {
            const int32_t offset = sext(((insn >> 31) << 12) | (((insn >> 7) & 1) << 11) |
                                       (((insn >> 25) & 63) << 5) | (((insn >> 8) & 15) << 1), 13);
            bool taken = false;
            switch (f3) {
            case 0: taken = a == b; break;
            case 1: taken = a != b; break;
            case 4: taken = int32_t(a) < int32_t(b); break;
            case 5: taken = int32_t(a) >= int32_t(b); break;
            case 6: taken = a < b; break;
            case 7: taken = a >= b; break;
            default: throw std::runtime_error("reference illegal branch");
            }
            if (taken) next = pc + offset;
            writes = false;
            break;
        }
        case 0x03: {
            unsigned bytes = 1u << (f3 & 3);
            result = load(a + imm, bytes);
            if (!(f3 & 4) && bytes < 4) result = uint32_t(sext(result, bytes * 8));
            break;
        }
        case 0x23:
            store(a + sext(((insn >> 25) << 5) | ((insn >> 7) & 31), 12), 1u << f3, b);
            reserved = false;
            writes = false;
            break;
        case 0x13: case 0x33: {
            uint32_t rhs = op == 0x13 ? uint32_t(imm) : b;
            if (op == 0x33 && f7 == 1) {
                switch (f3) {
                case 0: result = uint32_t(uint64_t(a) * b); break;
                case 1: result = uint32_t(uint64_t(int64_t(int32_t(a)) * int64_t(int32_t(b))) >> 32); break;
                case 2: result = uint32_t(uint64_t(int64_t(int32_t(a)) * int64_t(uint64_t(b))) >> 32); break;
                case 3: result = uint32_t((uint64_t(a) * b) >> 32); break;
                case 4: result = b == 0 ? ~0u : (a == 0x80000000 && b == ~0u) ? a : uint32_t(int32_t(a) / int32_t(b)); break;
                case 5: result = b == 0 ? ~0u : a / b; break;
                case 6: result = b == 0 ? a : (a == 0x80000000 && b == ~0u) ? 0 : uint32_t(int32_t(a) % int32_t(b)); break;
                case 7: result = b == 0 ? a : a % b; break;
                }
            } else {
                switch (f3) {
                case 0: result = (op == 0x33 && f7 == 32) ? a - rhs : a + rhs; break;
                case 1: result = a << (rhs & 31); break;
                case 2: result = int32_t(a) < int32_t(rhs); break;
                case 3: result = a < rhs; break;
                case 4: result = a ^ rhs; break;
                case 5: result = (insn & (1u << 30)) ? uint32_t(int32_t(a) >> (rhs & 31)) : a >> (rhs & 31); break;
                case 6: result = a | rhs; break;
                case 7: result = a & rhs; break;
                }
            }
            break;
        }
        case 0x2f: {
            const unsigned fn = insn >> 27;
            result = load(a, 4);
            uint32_t value = b;
            if (fn == 2) { reserved = true; reservation = a; break; }
            if (fn == 3) {
                result = !(reserved && reservation == a);
                if (!result) store(a, 4, b);
                reserved = false;
                break;
            }
            switch (fn) {
            case 0: value = result + b; break;
            case 1: break;
            case 4: value = result ^ b; break;
            case 8: value = result | b; break;
            case 12: value = result & b; break;
            case 16: value = int32_t(result) < int32_t(b) ? result : b; break;
            case 20: value = int32_t(result) > int32_t(b) ? result : b; break;
            case 24: value = result < b ? result : b; break;
            case 28: value = result > b ? result : b; break;
            default: throw std::runtime_error("reference illegal AMO");
            }
            store(a, 4, value);
            reserved = false;
            break;
        }
        case 0x0f: writes = false; break;
        default: throw std::runtime_error("reference unsupported instruction " + hex(insn));
        }
        unsigned expected_rd = writes ? rd : 0;
        require(dut.trace_rd == expected_rd, "destination mismatch at " + hex(pc));
        if (writes && rd) {
            require(dut.trace_value == result, "x" + std::to_string(rd) + " at " + hex(pc) +
                    " instruction " + hex(insn) + ": expected " + hex(result) + " got " + hex(dut.trace_value));
            r[rd] = result;
        }
        require(dut.trace_next_pc == next, "next-PC mismatch at " + hex(pc));
        pc = next;
    }
};

struct Transaction {
    bool valid = false, write = false, error = false, atomic = false;
    uint64_t due = 0;
    uint32_t address = 0, data = 0, response = 0;
    unsigned strobe = 0;
};

struct Simulation {
    VerilatedContext context;
    Vrv32_core dut{&context};
    std::vector<uint8_t> ram = std::vector<uint8_t>(ram_size, 0);
    std::unique_ptr<Reference> reference;
    std::mt19937 random;
    Transaction instruction, data;
    uint64_t cycles = 0, retired = 0, traps = 0, timer_traps = 0;
    uint64_t mtime = 0, mtimecmp = ~uint64_t(0);
    uint32_t msip = 0;
    int exit_code = -1, exit_countdown = 0;
    bool delays = true, quiet = false;
    std::string uart;
    std::ofstream trace;
    explicit Simulation(unsigned seed) : random(seed) {}

    uint32_t bus_read(uint32_t address, bool& error, bool atomic = false) {
        error = false;
        if (in_ram(address)) return read32(ram, address - ram_base);
        if (atomic) { error = true; return 0; }
        switch (address) {
        case 0x02000000: return msip;
        case 0x02004000: return uint32_t(mtimecmp);
        case 0x02004004: return uint32_t(mtimecmp >> 32);
        case 0x0200bff8: return uint32_t(mtime);
        case 0x0200bffc: return uint32_t(mtime >> 32);
        case uart_base: return 0;
        case uart_base + 4: return 0x00006000; // 16550 LSR bits 5 and 6 at byte 5
        case exit_address: return 0;
        default: error = true; return 0;
        }
    }
    void bus_write(const Transaction& t) {
        if (in_ram(t.address)) { write32(ram, t.address - ram_base, t.data, t.strobe); return; }
        uint32_t mask = 0;
        for (unsigned i = 0; i < 4; ++i) if (t.strobe & (1u << i)) mask |= 255u << (i*8);
        auto merge = [&](uint32_t old) { return (old & ~mask) | (t.data & mask); };
        switch (t.address) {
        case 0x02000000: msip = merge(msip) & 1; break;
        case 0x02004000: mtimecmp = (mtimecmp & 0xffffffff00000000ull) | merge(uint32_t(mtimecmp)); break;
        case 0x02004004: mtimecmp = (mtimecmp & 0xffffffffull) | (uint64_t(merge(uint32_t(mtimecmp >> 32))) << 32); break;
        case 0x0200bff8: mtime = (mtime & 0xffffffff00000000ull) | merge(uint32_t(mtime)); break;
        case 0x0200bffc: mtime = (mtime & 0xffffffffull) | (uint64_t(merge(uint32_t(mtime >> 32))) << 32); break;
        case uart_base:
            if (t.strobe & 1) {
                char c = char(t.data);
                uart += c;
                if (!quiet) std::cout << c << std::flush;
            }
            break;
        case exit_address: exit_code = int(t.data); exit_countdown = 4; break;
        default: break;
        }
    }
    void reset() {
        dut.reset = 1;
        dut.imem_request_ready = 0;
        dut.imem_response_valid = 0;
        dut.dmem_request_ready = 0;
        dut.dmem_response_valid = 0;
        dut.reservation_invalidate = 0;
        dut.software_interrupt = 0;
        dut.timer_interrupt = 0;
        dut.external_interrupt = 0;
        dut.time_value = 0;
        for (int i = 0; i < 5; ++i) {
            dut.clk = 0; dut.eval(); context.timeInc(1);
            dut.clk = 1; dut.eval(); context.timeInc(1);
        }
        dut.clk = 0; dut.reset = 0; dut.eval();
    }
    void tick() {
        dut.clk = 0;
        dut.time_value = mtime;
        dut.timer_interrupt = mtime >= mtimecmp;
        dut.software_interrupt = msip != 0;
        dut.imem_response_valid = instruction.valid && instruction.due <= cycles;
        dut.imem_response_data = instruction.response;
        dut.imem_response_error = instruction.error;
        dut.dmem_response_valid = data.valid && data.due <= cycles;
        dut.dmem_response_data = data.response;
        dut.dmem_response_error = data.error;
        dut.imem_request_ready = 0;
        dut.dmem_request_ready = 0;
        dut.eval();
        dut.imem_request_ready = (!instruction.valid || (dut.imem_response_valid && dut.imem_response_ready)) &&
                                 (!delays || random() % 4 != 0);
        dut.dmem_request_ready = (!data.valid || (dut.dmem_response_valid && dut.dmem_response_ready)) &&
                                 (!delays || random() % 3 != 0);
        dut.eval();
        if (dut.trace_valid) {
            ++retired;
            if (reference) reference->step(dut);
            if (trace) trace << cycles << " " << hex(dut.trace_pc) << " " << hex(dut.trace_instruction)
                             << " x" << unsigned(dut.trace_rd) << "=" << hex(dut.trace_value) << "\n";
        }
        if (dut.trace_trap) {
            ++traps;
            if (dut.trace_cause == 0x80000007) ++timer_traps;
            if (trace) trace << "trap " << hex(dut.trace_trap_pc) << " cause " << hex(dut.trace_cause)
                             << " value " << hex(dut.trace_trap_value) << "\n";
            require(!reference, "unexpected trap at " + hex(dut.trace_trap_pc) + " cause " + hex(dut.trace_cause));
        }
        bool ir = dut.imem_response_valid && dut.imem_response_ready;
        bool dr = dut.dmem_response_valid && dut.dmem_response_ready;
        bool iq = dut.imem_request_valid && dut.imem_request_ready;
        bool dq = dut.dmem_request_valid && dut.dmem_request_ready;
        Transaction next_i, next_d;
        if (iq) {
            next_i.valid = true;
            next_i.address = dut.imem_request_address;
            next_i.error = !in_ram(next_i.address);
            next_i.response = next_i.error ? 0 : read32(ram, next_i.address - ram_base);
            next_i.due = cycles + 1 + (delays ? random() % 7 : 0);
        }
        if (dq) {
            next_d.valid = true;
            next_d.address = dut.dmem_request_address;
            next_d.write = dut.dmem_request_write;
            next_d.atomic = dut.dmem_request_atomic;
            next_d.data = dut.dmem_request_data;
            next_d.strobe = dut.dmem_request_strobe;
            next_d.response = bus_read(next_d.address, next_d.error, next_d.atomic);
            next_d.due = cycles + 1 + (delays ? random() % 11 : 0);
        }
        dut.clk = 1; dut.eval(); context.timeInc(1);
        if (dr && data.write && !data.error) bus_write(data);
        if (ir) instruction.valid = false;
        if (dr) data.valid = false;
        if (iq) instruction = next_i;
        if (dq) data = next_d;
        dut.clk = 0; dut.eval(); context.timeInc(1);
        ++cycles;
        if (cycles % 5 == 0) ++mtime; // 50 MHz core, 10 MHz timer
        if (exit_countdown > 0) --exit_countdown;
    }
    void run(uint64_t limit, bool kernel = false) {
        reset();
        for (; cycles < limit; ) {
            tick();
            if (exit_code >= 0 && exit_countdown == 0) {
                require(exit_code == 1, "firmware failed with code " + std::to_string(exit_code));
                return;
            }
            if (kernel && timer_traps >= 3 && uart.find("[WORK-A]") != std::string::npos &&
                uart.find("[WORK-B]") != std::string::npos && uart.find("[TIMER] Tick 3\n") != std::string::npos) {
                require(uart.find("[TRAP]") == std::string::npos, "kernel reported an unhandled trap");
                return;
            }
        }
        throw std::runtime_error("timeout after " + std::to_string(cycles) + " cycles; last PC " + hex(dut.trace_pc));
    }
    void elf(const std::string& path) {
        std::ifstream file(path, std::ios::binary);
        require(bool(file), "cannot open ELF " + path);
        std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)), {});
        require(bytes.size() >= 52 && read32(bytes, 0) == 0x464c457f && bytes[4] == 1 && bytes[5] == 1,
                "expected little-endian ELF32");
        require(bytes[18] == 243 && bytes[19] == 0, "expected RISC-V ELF");
        require(read32(bytes, 24) == ram_base, "ELF entry must match RESET_PC 0x80000000");
        require((read32(bytes, 36) & 1) == 0, "compressed instructions are unsupported; rebuild without C");
        size_t table = read32(bytes, 28);
        unsigned entry_size = bytes[42] | unsigned(bytes[43]) << 8;
        unsigned entries = bytes[44] | unsigned(bytes[45]) << 8;
        require(entry_size >= 32 && table + size_t(entry_size) * entries <= bytes.size(), "invalid ELF program headers");
        for (unsigned i = 0; i < entries; ++i) {
            size_t p = table + size_t(entry_size) * i;
            if (read32(bytes, p) != 1) continue;
            uint32_t offset = read32(bytes, p+4), address = read32(bytes, p+12);
            uint32_t file_size = read32(bytes, p+16), mem_size = read32(bytes, p+20);
            require(file_size <= mem_size && uint64_t(offset)+file_size <= bytes.size(), "invalid ELF segment");
            require(address >= ram_base && uint64_t(address-ram_base)+mem_size <= ram_size, "ELF exceeds 128 KiB RAM");
            for (uint32_t j = 0; j < mem_size; ++j) ram[address-ram_base+j] = j < file_size ? bytes[offset+j] : 0;
        }
    }
};

uint32_t r_type(unsigned fn, unsigned f3, unsigned rd, unsigned a, unsigned b) {
    return fn << 25 | b << 20 | a << 15 | f3 << 12 | rd << 7 | 0x33;
}
uint32_t i_type(unsigned op, unsigned f3, unsigned rd, unsigned a, int imm) {
    return (uint32_t(imm) & 4095) << 20 | a << 15 | f3 << 12 | rd << 7 | op;
}
uint32_t s_type(unsigned f3, unsigned a, unsigned b, unsigned imm) {
    return (imm >> 5) << 25 | b << 20 | a << 15 | f3 << 12 | (imm & 31) << 7 | 0x23;
}
uint32_t b_type(unsigned f3, unsigned a, unsigned b, int imm) {
    uint32_t n = uint32_t(imm);
    return ((n >> 12) & 1) << 31 | ((n >> 5) & 63) << 25 | b << 20 | a << 15 |
           f3 << 12 | ((n >> 1) & 15) << 8 | ((n >> 11) & 1) << 7 | 0x63;
}
uint32_t amo(unsigned fn, unsigned rd, unsigned a, unsigned b) {
    return fn << 27 | 3 << 25 | b << 20 | a << 15 | 2 << 12 | rd << 7 | 0x2f;
}
void random_test(unsigned seed, bool delays) {
    Simulation sim(seed);
    sim.delays = delays;
    sim.quiet = true;
    std::mt19937 gen(seed + 100);
    std::vector<uint32_t> code;
    auto emit = [&](uint32_t insn) { code.push_back(insn); };
    emit(0x80010a37); // x20 = data base
    for (unsigned reg = 1; reg < 20; ++reg) {
        emit((gen() & 0xfffff000) | reg << 7 | 0x37);
        emit(i_type(0x13, 0, reg, reg, int(gen() & 4095)));
    }
    // Corner cases for signed division, zero divisors, and multiply high.
    emit(0x800000b7); // x1 = INT_MIN
    emit(i_type(0x13, 0, 2, 0, -1));
    for (unsigned f = 0; f < 8; ++f) {
        emit(r_type(1, f, 3, 1, 2));
        emit(r_type(1, f, 4, 1, 0));
    }
    emit(amo(2, 1, 20, 0));
    emit(amo(3, 2, 20, 3));
    emit(amo(3, 4, 20, 5)); // second SC must fail
    emit(i_type(0x13, 0, 21, 0, 80));
    size_t loop = code.size();
    emit(i_type(0x13, 0, 1, 1, 1));
    emit(s_type(2, 20, 1, 4));
    emit(i_type(0x03, 2, 2, 20, 4));
    emit(r_type(0, 0, 3, 2, 1)); // load-to-ALU dependency
    emit(i_type(0x13, 0, 21, 21, -1));
    emit(b_type(1, 21, 0, int(loop - code.size()) * 4));
    const unsigned branches[] = {0,1,4,5,6,7};
    const unsigned atomics[] = {0,1,4,8,12,16,20,24,28};
    for (unsigned n = 0; n < 4000; ++n) {
        unsigned rd = gen() % 20, a = gen() % 20, b = gen() % 20, f = gen() % 8;
        unsigned off = gen() % 256;
        switch (gen() % 10) {
        case 0: case 1: emit(r_type((f == 0 || f == 5) && (gen() & 1) ? 32 : 0, f, rd, a, b)); break;
        case 2: {
            unsigned imm = gen() & 4095;
            if (f == 1 || f == 5) imm = (gen() & 31) | (f == 5 && (gen() & 1) ? 1024 : 0);
            emit(i_type(0x13, f, rd, a, imm)); break;
        }
        case 3: emit(r_type(1, f, rd, a, b)); break;
        case 4: f = gen() % 3; emit(s_type(f, 20, b, off & ~((1u << f)-1))); break;
        case 5: f = gen() % 3; emit(i_type(0x03, f < 2 && (gen() & 1) ? f+4 : f, rd, 20, off & ~((1u << f)-1))); break;
        case 6: emit(b_type(branches[gen()%6], a, b, 8)); emit(i_type(0x13, 0, rd, rd, 1)); break;
        case 7: emit(amo(atomics[gen()%9], rd, 20, b)); break;
        case 8: emit((gen() & 0xfffff000) | rd << 7 | ((gen() & 1) ? 0x37 : 0x17)); break;
        case 9: emit(0x008000ef); emit(s_type(2, 20, b, 8)); break; // taken JAL kills store
        }
    }
    emit(0x10000ab7); // x21 = exit MMIO base
    emit(i_type(0x13, 0, 22, 0, 1));
    emit(s_type(2, 21, 22, 16));
    emit(0x0000006f);
    for (size_t i = 0; i < code.size(); ++i) write32(sim.ram, i*4, code[i]);
    for (unsigned i = 0x10000; i < ram_size; i += 4) write32(sim.ram, i, gen());
    sim.reference = std::make_unique<Reference>(sim.ram);
    sim.run(1000000);
    for (unsigned i = 0x10000; i < ram_size; ++i)
        require(sim.ram[i] == sim.reference->memory[i], "final memory mismatch at " + hex(ram_base+i));
    std::cout << "PASS differential seed=" << seed << " delays=" << delays << " retired=" << sim.retired
              << " cycles=" << sim.cycles << "\n";
}

void throughput_test() {
    Simulation sim(0);
    sim.delays = false;
    for (unsigned i = 0; i < 512; ++i) write32(sim.ram, i*4, i_type(0x13, 0, 1, 1, 1));
    write32(sim.ram, 512*4, 0x10000ab7);
    write32(sim.ram, 513*4, i_type(0x13, 0, 22, 0, 1));
    write32(sim.ram, 514*4, s_type(2, 21, 22, 16));
    write32(sim.ram, 515*4, 0x0000006f);
    sim.reference = std::make_unique<Reference>(sim.ram);
    sim.run(2000);
    require(sim.reference->r[1] == 512, "dependent ALU throughput result");
    require(sim.cycles < 540, "pipeline failed near-one-IPC ALU stream");
    std::cout << "PASS dependent ALU stream retired=" << sim.retired << " cycles=" << sim.cycles << "\n";
}
} // namespace

int main(int argc, char** argv) {
    try {
        unsigned seed = 1;
        uint64_t limit = 20000000;
        bool self_test = false, kernel = false, delays = true;
        std::string elf, trace;
        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            auto value = [&]() { require(i+1 < argc, "missing option value"); return std::string(argv[++i]); };
            if (arg == "--self-test") self_test = true;
            else if (arg == "--elf") elf = value();
            else if (arg == "--seed") seed = unsigned(std::stoul(value()));
            else if (arg == "--max-cycles") limit = std::stoull(value());
            else if (arg == "--trace") trace = value();
            else if (arg == "--kernel") kernel = true;
            else if (arg == "--no-delays") delays = false;
            else throw std::runtime_error("unknown option " + arg);
        }
        if (self_test) {
            for (unsigned s : {1u, 17u, 71u, 193u, 65537u}) random_test(s, true);
            random_test(99, false);
            throughput_test();
            return 0;
        }
        require(!elf.empty(), "use --self-test or --elf path [--kernel] [--trace path]");
        Simulation sim(seed);
        sim.delays = delays;
        if (!trace.empty()) { sim.trace.open(trace); require(bool(sim.trace), "cannot open trace"); }
        sim.elf(elf);
        sim.run(limit, kernel);
        std::cout << "PASS " << (kernel ? "kernel boot and timer scheduling" : "firmware")
                  << " retired=" << sim.retired << " cycles=" << sim.cycles << " traps=" << sim.traps
                  << " timer_interrupts=" << sim.timer_traps << "\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}
