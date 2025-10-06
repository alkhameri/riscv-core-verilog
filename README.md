# RISC-V Core (Verilog)

A small, educational RISC-V core written in Verilog. This repository contains RTL in `rtl/` and testbenches in `sim/`.

This README tells you how to simulate the design with Verilator and ModelSim, and how to program the DE10-Lite (in Quartus). It also includes troubleshooting tips and how to get Quartus to actually initialize M9K block RAMs.

---

## Table of Contents

- Getting the code
- Quick structure
- Simulating with Verilator
- Simulating with ModelSim (ModelSim/Questa)
  - Waveform commands (copy/paste)
- Running the provided testbenches
- Synthesizing and programming the DE10-Lite with Quartus
  - Forcing/initializing M9K blocks
- Troubleshooting

---

## Getting the code

Clone or download this repository. From the project root you should see `rtl/` and `sim/` directories.

---

## Quick structure

- `rtl/` - Verilog RTL (TopLevel, ALU, RegisterFile, memories, etc.)
- `sim/` - Testbenches and simulation helpers (`simple_tb.v`, `RISCVCore_tb.v`, wrapper)

---

## Simulating with Verilator

Verilator converts Verilog to a cycle-accurate C++ model. This project includes simple testbenches in `sim/`.

1. Install Verilator (see https://www.veripool.org/verilator/).
2. From the project root, run a command like:

```bash
# generate verilated model
verilator -Wall --cc rtl/*.v sim/RISCVCore_tb.v --exe sim/test_driver.cpp
# build
make -C obj_dir -f Vtop.mk
# run
./obj_dir/Vtop
```

Note: The exact build steps depend on your C++ test driver. The above is a template; you can also instantiate the verilated model from your own C++ driver.

---

## Simulating with ModelSim / Questa

ModelSim/Questa can run the provided Verilog testbenches directly.

Compile and run (PowerShell commands):

```powershell
cd C:\projects\riscv-core-verilog
# clean work directory if necessary
if (Test-Path .\work) { Remove-Item -Recurse -Force .\work }
vlib work
# compile RTL and sim files
vlog rtl\*.v
vlog sim\*.v
# run TB
vsim -c RISCVCore_tb -do "run -all; quit"
```

If you prefer the GUI, run `vsim RISCVCore_tb` and then `run -all` from the transcript window.

### Add signals to the wave window (copy these into the transcript)

Below are the exact `add wave` commands to populate the ModelSim waveform with the most useful signals (copy/paste into the transcript or put them in a `.do` file):

```
add wave -position insertpoint sim:/RISCVCore_tb/dut/clk
add wave sim:/RISCVCore_tb/dut/PC
add wave sim:/RISCVCore_tb/dut/Instr
add wave sim:/RISCVCore_tb/dut/RegWrite
add wave sim:/RISCVCore_tb/dut/ALUSrc
add wave sim:/RISCVCore_tb/dut/MemWrite
add wave sim:/RISCVCore_tb/dut/ALUResult
add wave sim:/RISCVCore_tb/dut/WriteData
add wave sim:/RISCVCore_tb/dut/ReadData1
add wave sim:/RISCVCore_tb/dut/ReadData2
add wave sim:/RISCVCore_tb/dut/Imm
```

Paste those into the transcript after you `vsim` the tb

---

### Creating a ModelSim project (step-by-step)

If you'd like to use the ModelSim GUI and create a dedicated project (helpful for coursework), follow these adapted steps:

1. Create a folder for the ModelSim project under `sim/`, for example `sim/ModelSim_RISCV/`.
2. Start ModelSim from the Start menu (do not launch it from within Quartus Prime).
3. Select File → New → Project to open the **Create Project** dialog.
  - Give the project a name (e.g. `RISCV_tb_project`).
  - Set the project location to the folder you created above (e.g. `.../sim/ModelSim_RISCV`).
  - Leave Default Library Name = `work` and Copy Settings From = `Copy Library Mappings`.
  - Click **OK**.
4. In the **Add Items to Project** window, add these files from the repository:
  - `sim/RISCVCore_tb.v` (your testbench)
  - `rtl/TopLevel.v` (the board-style top-level that defines `module RISCVCore`)
  - You may also add other needed RTL files (or add them later); but these two are the minimum.
  - Leave the option as **Reference from current location** (do not copy files).
5. Select **Compile → Compile All**. The files should compile without errors (if ModelSim is pointed to the correct library and files).
6. Click **Simulate → Start Simulation**.
  - In the **Start Simulation** dialog, expand `work` and select `RISCVCore_tb` (ModelSim may show the testbench module as the top-level).
7. Once simulation starts, open the Wave window (View → Wave) and add signals using the `add wave` commands listed above (or use the GUI to drag signals into the wave window).

Notes:
- Make sure you compiled the RTL files from the `rtl/` folder first so ModelSim binds to the correct `RISCVCore` implementation.
- If you get port mismatch errors, re-check that the module in `rtl/TopLevel.v` is the one being compiled (ModelSim shows the file path in compile messages).


## Running the provided testbenches

- `sim/simple_tb.v` — small smoke test to load a program into `InstrMem` and run a few cycles.
- `sim/RISCVCore_tb.v` — a more comprehensive testbench with multiple tests.

Make sure you compile the `rtl/` files first with `vlog rtl\*.v` so the simulator binds to the correct `RISCVCore` implementation in `rtl/TopLevel.v`.

---

## Synthesizing and programming the DE10-Lite (Quartus)

1. Open the Quartus project (quartusproject/RISCVCore.v or create a new one and add the `rtl/TopLevel.v` as the top-level entity.
2. Set the correct device for the DE10-Lite.
3. Important: ensure Quartus will include memory initialization for M9K blocks in the programming file (by default it may not). To enable this:

- Click Assignments → Device...
- Click Device and Pin Options...
- Go to the Configuration tab.
- From the Configuration Mode drop-down, select **Single Uncompressed Image with Memory Initialization** (this tells Quartus to embed M9K initialization data in the bitstream so on-program the on-chip memories get initialized). 

Note: I use Quartus version 19.1, other Quartus versions may have slightly different menu layout; look for the Configuration tab in Device and Pin Options and a configuration mode that mentions memory initialization

4. Compile (Analysis & Elaboration -> Synthesis -> Fitter -> Assembler)
5. Program the device (Programmer -> Auto Detect -> Program).

### Forcing / encouraging M9K inference

If Quartus synthesized your memories into LUTs instead of M9K, try the following:

- In the memory declarations (e.g. `rtl/InstrMem.v` and `rtl/DataMem.v`) add the vendor attribute above the `reg` memory declaration:

```verilog
(* ramstyle = "M9K" *)
reg [31:0] memory [0:1023];
```

This strongly suggests the fitter to implement the array in M9K blocks (when possible).

- Use synchronous read/write patterns (single-clock read/write) — the RTL in this repo already uses synchronous reads/writes which helps inference.
- For initialized memories prefer `$readmemh("instr_init.mem", memory);` and provide a `.mem` or `.mif` file.

---

## Troubleshooting

- If ModelSim complains about port mismatches, ensure you compiled the correct RTL first (`vlog rtl\*.v`) and that you didn't accidentally compile a different `RISCVCore` from another folder.
- If registers are not updating in simulation: probe `RegWrite`, `rd`, and `WriteData` at posedge to confirm writes occur. The testbenches already include debug prints that show these signals.
- If Quartus doesn't infer M9K blocks: clean project, add the `(* ramstyle = "M9K" *)` attribute, and ensure the memory read/write are synchronous.

---

Happy simulating and programming!