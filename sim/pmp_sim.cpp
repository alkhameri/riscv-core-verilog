#include "Vrv32_pmp.h"
#include "verilated.h"
#include <iostream>
#include <stdexcept>

int main() {
    try {
        Vrv32_pmp p;
        auto check = [&](uint32_t address, unsigned bytes, bool machine, bool execute, bool write,
                         bool expected, const char* description) {
            p.address = address; p.size_bytes = bytes; p.machine_mode = machine;
            p.execute_access = execute; p.write_access = write; p.eval();
            if (bool(p.allowed) != expected) throw std::runtime_error(description);
        };
        p.configuration = 0;
        for (unsigned i = 0; i < 4; ++i) p.region_address[i] = 0;
        check(0x80000000, 4, true, false, true, true, "unmatched machine access");
        check(0x80000000, 4, false, true, false, false, "unmatched user access");
        p.region_address[0] = 0x20001fff;
        p.configuration = 0x1d; // 64 KiB NAPOT, RX
        check(0x80000000, 4, false, true, false, true, "NAPOT first word");
        check(0x8000fffc, 4, false, false, false, true, "NAPOT last word");
        check(0x80010000, 1, false, false, false, false, "NAPOT exclusive upper bound");
        check(0x80000000, 4, false, false, true, false, "user write denied");
        check(0x80000000, 4, true, false, true, true, "machine bypass unlocked permissions");
        p.configuration = 0x9d;
        check(0x80000000, 4, true, false, true, false, "lock applies to machine mode");
        // Earlier entries win, and a partially matching access cannot fall back.
        p.region_address[0] = 0x20000000;
        p.region_address[1] = 0x20001fff;
        p.configuration = 0x1f11; // NA4 R, then overlapping NAPOT RWX
        check(0x80000000, 4, false, false, true, false, "first match priority");
        check(0x80000003, 2, false, false, false, false, "partial match must fail");
        check(0x80000004, 4, false, false, true, true, "next word uses second entry");
        // TOR uses the predecessor address even if that predecessor is disabled.
        p.region_address[0] = 0x20000000;
        p.region_address[1] = 0x20000004;
        p.configuration = 0x0b00;
        check(0x7fffffff, 1, false, false, false, false, "TOR lower bound");
        check(0x80000000, 4, false, false, true, true, "TOR write allowed");
        check(0x8000000c, 4, false, false, false, true, "TOR final word");
        check(0x80000010, 1, false, false, false, false, "TOR upper bound");
        check(0x80000000, 4, false, true, false, false, "TOR execute denied");
        // An empty TOR range must not match a request spanning its boundary.
        p.region_address[1] = p.region_address[0];
        p.region_address[2] = 0xffffffff;
        p.configuration = 0x1f0800;
        check(0x7fffffff, 2, false, false, true, true, "empty TOR must be ignored");
        check(0xfffffffc, 4, false, true, false, true, "whole physical space NAPOT");
        std::cout << "PASS PMP ranges, priority, containment, locks and machine bypass\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}
