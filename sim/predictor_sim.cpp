#include "Vrv32_predictor.h"
#include "verilated.h"
#include <iostream>
#include <stdexcept>

int main() {
    try {
        VerilatedContext context;
        Vrv32_predictor p{&context};
        auto tick = [&]() { p.clk = 0; p.eval(); p.clk = 1; p.eval(); p.clk = 0; p.eval(); };
        auto check = [](bool value, const char* reason) { if (!value) throw std::runtime_error(reason); };
        auto predict = [&](uint32_t pc) { p.lookup_pc = pc; p.eval(); return p.predicted_pc; };
        auto resolve = [&](uint32_t pc, uint32_t target, bool branch, bool taken, bool push, bool pop) {
            predict(pc);
            p.update_prediction = p.prediction;
            p.update_pc = pc;
            p.update_target = target;
            p.update_branch = branch;
            p.update_jump = !branch;
            p.update_taken = taken;
            p.update_push = push;
            p.update_pop = pop;
            p.update_valid = 1;
            tick();
            p.update_valid = 0;
        };
        p.reset = 1; p.enable = 1; tick(); p.reset = 0;
        check(predict(0x80000000) == 0x80000004, "cold lookup must fall through");
        unsigned correct = 0, baseline_correct = 0, baseline = 1;
        for (unsigned i = 0; i < 1024; ++i) {
            bool taken = (i & 1) == 0;
            bool prediction = predict(0x80000040) == 0x80000100;
            if (i >= 128) {
                correct += prediction == taken;
                baseline_correct += (baseline >= 2) == taken;
            }
            baseline = taken ? (baseline < 3 ? baseline+1 : 3) : (baseline ? baseline-1 : 0);
            resolve(0x80000040, 0x80000100, true, taken, false, false);
        }
        check(correct > 850, "gshare/chooser failed alternating correlation");
        check(correct > baseline_correct + 700, "tournament did not outperform bimodal baseline");
        std::cout << "PASS predictor alternating pattern: tournament " << correct << "/896, bimodal "
                  << baseline_correct << "/896\n";
        // Two distinct tags in one set must coexist.
        resolve(0x80000200, 0x80000500, false, true, false, false);
        resolve(0x80000280, 0x80000600, false, true, false, false);
        check(predict(0x80000200) == 0x80000500, "BTB way zero lost");
        check(predict(0x80000280) == 0x80000600, "BTB way one lost");
        // A return entry uses the newest resolved call, not its previous target.
        resolve(0x80000300, 0x80000800, false, true, true, false);
        resolve(0x80000800, 0x80000304, false, true, false, true);
        resolve(0x80000320, 0x80000800, false, true, true, false);
        check(predict(0x80000800) == 0x80000324, "return stack target not selected");
        resolve(0x80000800, 0x80000324, false, true, true, true);
        check(predict(0x80000800) == 0x80000804, "coroutine pop/push failed");
        p.enable = 0;
        check(predict(0x80000280) == 0x80000284, "disable must predict sequentially");
        p.enable = 1; p.invalidate = 1; tick(); p.invalidate = 0;
        check(predict(0x80000280) == 0x80000284, "invalidate left a valid BTB tag");
        std::cout << "PASS predictor tags, return stack, coroutine, disable and invalidation\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}
