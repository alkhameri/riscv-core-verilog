# RISC-V Core Simulation Makefile

# Compiler and flags
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Source files
RTL_DIR = ../rtl
RTL_FILES = $(RTL_DIR)/ALU.v \
            $(RTL_DIR)/ALUmux.v \
            $(RTL_DIR)/Control.v \
            $(RTL_DIR)/DataMem.v \
            $(RTL_DIR)/Extend.v \
            $(RTL_DIR)/PCmux.v \
            $(RTL_DIR)/PCplus4.v \
            $(RTL_DIR)/PCplusimm.v \
            $(RTL_DIR)/Reg.v \
            $(RTL_DIR)/WBmux.v \
            $(RTL_DIR)/InstrMem.v \
            $(RTL_DIR)/TopLevel.v

# Testbench files
TB_FILES = RISCVCore_tb.v simple_tb.v

# Default target
all: compile run

# Compile the design
compile:
	@echo "Compiling RISC-V Core..."
	$(IVERILOG) -o riscv_core.vvp $(RTL_FILES) RISCVCore_tb.v
	$(IVERILOG) -o simple_test.vvp $(RTL_FILES) simple_tb.v
	@echo "Compilation complete!"

# Run comprehensive testbench
run: compile
	@echo "Running comprehensive testbench..."
	$(VVP) riscv_core.vvp

# Run simple testbench
simple: compile
	@echo "Running simple testbench..."
	$(VVP) simple_test.vvp

# View waveforms
view:
	@echo "Opening GTKWave..."
	$(GTKWAVE) riscv_core.vcd &

# View simple waveforms
view-simple:
	@echo "Opening GTKWave for simple test..."
	$(GTKWAVE) simple_test.vcd &

# Clean up
clean:
	@echo "Cleaning up..."
	rm -f *.vvp *.vcd
	@echo "Clean complete!"

# Help
help:
	@echo "Available targets:"
	@echo "  all        - Compile and run comprehensive testbench"
	@echo "  compile    - Compile all testbenches"
	@echo "  run        - Run comprehensive testbench"
	@echo "  simple     - Run simple testbench"
	@echo "  view       - View comprehensive waveforms"
	@echo "  view-simple- View simple waveforms"
	@echo "  clean      - Clean up generated files"
	@echo "  help       - Show this help"

.PHONY: all compile run simple view view-simple clean help
