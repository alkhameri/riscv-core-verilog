#include "Vrv32_soc.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

// Decode the actual serial pin. The board test does not use a simulation-only
// UART shortcut, so baud timing, status polling and transmit backpressure run.
int main(int argc, char** argv) {
    try {
        bool kernel = false;
        uint64_t limit = 20000000;
        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            if (arg == "--kernel") kernel = true;
            else if (arg == "--max-cycles" && i+1 < argc) limit = std::stoull(argv[++i]);
            else if (arg.rfind("+mem=", 0) != 0) throw std::runtime_error("unknown option " + arg);
        }
        VerilatedContext context;
        context.commandArgs(argc, argv);
        Vrv32_soc soc{&context};
        auto tick = [&]() {
            soc.clk = 0; soc.eval(); context.timeInc(1);
            soc.clk = 1; soc.eval(); context.timeInc(1);
        };
        soc.reset = 1;
        for (int i = 0; i < 5; ++i) tick();
        soc.reset = 0;
        std::string uart;
        bool receiving = false;
        uint64_t sample_at = 0, timer_traps = 0;
        unsigned bit = 0, character = 0;
        constexpr unsigned clocks_per_bit = 50000000 / 115200;
        for (uint64_t cycle = 0; cycle < limit; ++cycle) {
            tick();
            if (soc.trap) {
                if (soc.trap_cause == 0x80000007) ++timer_traps;
                if (kernel && soc.trap_cause != 11 && soc.trap_cause != 0x80000007)
                    throw std::runtime_error("unexpected kernel trap " + std::to_string(soc.trap_cause));
            }
            if (!receiving && !soc.uart_tx) {
                receiving = true;
                sample_at = cycle + clocks_per_bit + clocks_per_bit / 2;
                bit = 0;
                character = 0;
            } else if (receiving && cycle == sample_at) {
                if (bit < 8) {
                    character |= unsigned(soc.uart_tx) << bit++;
                    sample_at += clocks_per_bit;
                } else {
                    if (!soc.uart_tx) throw std::runtime_error("UART framing error");
                    if (character != '\r') uart += char(character);
                    std::cout << char(character) << std::flush;
                    receiving = false;
                }
            }
            if (soc.exit_valid) {
                if (soc.exit_code != 1) throw std::runtime_error("firmware test " + std::to_string(soc.exit_code));
                std::cout << "PASS SoC firmware cycles=" << cycle << "\n";
                return 0;
            }
            if (kernel && timer_traps >= 3 && uart.find("[TIMER] Tick 3\n") != std::string::npos &&
                uart.find("[WORK-A]") != std::string::npos && uart.find("[WORK-B]") != std::string::npos) {
                if (uart.find("[TRAP]") != std::string::npos) throw std::runtime_error("unhandled kernel trap");
                std::cout << "PASS SoC kernel, serial UART and timer scheduling cycles=" << cycle << "\n";
                return 0;
            }
        }
        throw std::runtime_error("SoC simulation timeout, retired PC=" + std::to_string(soc.retired_pc));
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}
