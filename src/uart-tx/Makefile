# ============================================================================
# Makefile for UART TX Project
# ============================================================================
#
# Uses the open-source iCE40 FPGA toolchain:
#   - Yosys:     Verilog synthesis (converts to logic gates)
#   - nextpnr:   Place and route (assigns physical locations)
#   - icepack:   Bitstream generation (creates programming file)
#   - iceprog:   FPGA programming (uploads to the board)
#
# Usage:
#   make        - Build the project (generates uart_tx.bin)
#   make prog   - Program the iCEBreaker board
#   make clean  - Remove all generated files
#
# ============================================================================

# Project name - must match the top module name in uart_tx.v
PROJ = uart_tx

# FPGA device settings for iCEBreaker
DEVICE = up5k
PACKAGE = sg48

# Default target: build the bitstream
all: $(PROJ).bin

# Step 1: Synthesis with Yosys
# Converts Verilog to a JSON netlist of logic gates
$(PROJ).json: $(PROJ).v
	yosys -p "synth_ice40 -top $(PROJ) -json $(PROJ).json" $(PROJ).v

# Step 2: Place and Route with nextpnr
# Assigns logic to physical FPGA resources and routes connections
$(PROJ).asc: $(PROJ).json icebreaker.pcf
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $(PROJ).json --pcf icebreaker.pcf --asc $(PROJ).asc

# Step 3: Bitstream generation with icepack
# Creates the binary file that configures the FPGA
$(PROJ).bin: $(PROJ).asc
	icepack $(PROJ).asc $(PROJ).bin

# Program the FPGA
# The bitstream is stored in flash, so it persists after power-off
prog: $(PROJ).bin
	iceprog $(PROJ).bin

# Remove all generated files
clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).bin

# Phony targets (not actual files)
.PHONY: all prog clean
