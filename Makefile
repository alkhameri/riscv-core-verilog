VERILATOR ?= verilator
CROSS ?= riscv64-elf-
BUILD ?= build
RTL := $(shell cat rtl/files.f)
SOC_RTL := rtl/rv32_ram.sv rtl/rv32_uart_tx.sv rtl/rv32_soc.sv
ARCH := rv32ima_zicsr_zifencei
FWFLAGS := -march=$(ARCH) -mabi=ilp32 -mno-relax -ffreestanding -nostdlib -nostartfiles

.PHONY: all lint test sim firmware clean
all: test

lint:
	$(VERILATOR) --lint-only --assert -Wall --top-module rv32_core -f rtl/files.f
	$(VERILATOR) --lint-only --assert -Wall --top-module de10_lite_top -f rtl/files.f $(SOC_RTL) rtl/de10_lite_top.sv

$(BUILD)/core/Vrv32_core: $(RTL) sim/core_sim.cpp
	mkdir -p $(BUILD)/core
	$(VERILATOR) --cc --exe --build -j 0 --assert -Wall --top-module rv32_core \
		-f rtl/files.f $(abspath sim/core_sim.cpp) --Mdir $(BUILD)/core \
		-CFLAGS '-std=c++17 -O2'

sim: $(BUILD)/core/Vrv32_core

$(BUILD)/tests.elf: firmware/tests.S firmware/link.ld
	mkdir -p $(BUILD)
	$(CROSS)gcc $(FWFLAGS) -T firmware/link.ld firmware/tests.S -o $@

firmware: $(BUILD)/tests.elf

$(BUILD)/soc/Vrv32_soc: $(RTL) $(SOC_RTL) sim/soc_sim.cpp
	mkdir -p $(BUILD)/soc
	$(VERILATOR) --cc --exe --build -j 0 --assert -Wall --top-module rv32_soc \
		-f rtl/files.f $(SOC_RTL) $(abspath sim/soc_sim.cpp) --Mdir $(BUILD)/soc \
		-CFLAGS '-std=c++17 -O2'

$(BUILD)/tests.hex: $(BUILD)/tests.elf tools/elf2hex.py
	python3 tools/elf2hex.py $< $@

.PHONY: test-soc test-kernel
test-soc: $(BUILD)/soc/Vrv32_soc $(BUILD)/tests.hex
	$(BUILD)/soc/Vrv32_soc +mem=$(BUILD)/tests.hex

# Prepare build/kernel with tools/prepare_kernel.py before invoking this target.
test-kernel: sim $(BUILD)/soc/Vrv32_soc
	$(MAKE) -C $(BUILD)/kernel CROSS=$(CROSS)
	python3 tools/elf2hex.py $(BUILD)/kernel/kernel.elf $(BUILD)/firmware.hex
	$(BUILD)/core/Vrv32_core --elf $(BUILD)/kernel/kernel.elf --kernel
	$(BUILD)/soc/Vrv32_soc +mem=$(BUILD)/firmware.hex --kernel

$(BUILD)/predictor/Vrv32_predictor: rtl/rv32_pkg.sv rtl/rv32_predictor.sv sim/predictor_sim.cpp
	mkdir -p $(BUILD)/predictor
	$(VERILATOR) --cc --exe --build -j 0 -Wall --top-module rv32_predictor \
		rtl/rv32_pkg.sv rtl/rv32_predictor.sv $(abspath sim/predictor_sim.cpp) \
		--Mdir $(BUILD)/predictor -CFLAGS '-std=c++17 -O2'

$(BUILD)/pmp/Vrv32_pmp: rtl/rv32_pmp.sv sim/pmp_sim.cpp
	mkdir -p $(BUILD)/pmp
	$(VERILATOR) --cc --exe --build -j 0 -Wall --top-module rv32_pmp \
		rtl/rv32_pmp.sv $(abspath sim/pmp_sim.cpp) --Mdir $(BUILD)/pmp -CFLAGS '-std=c++17 -O2'

test: lint sim firmware $(BUILD)/predictor/Vrv32_predictor $(BUILD)/pmp/Vrv32_pmp
	$(BUILD)/predictor/Vrv32_predictor
	$(BUILD)/pmp/Vrv32_pmp
	$(BUILD)/core/Vrv32_core --self-test
	$(BUILD)/core/Vrv32_core --elf $(BUILD)/tests.elf --seed 1 --max-cycles 2000000
	$(BUILD)/core/Vrv32_core --elf $(BUILD)/tests.elf --seed 71 --max-cycles 2000000

clean:
	rm -rf $(BUILD)
