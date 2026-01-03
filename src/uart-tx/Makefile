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
#   make        - Build the project (generates uart_tx.bin in /tmp)
#   make prog   - Program the iCEBreaker board
#   make clean  - Remove all generated files
#
# ============================================================================

# Build directory for artifacts
BUILD_DIR = /tmp

# Project name - must match the top module name in uart_tx.v
PROJ = uart_tx

# FPGA device settings for iCEBreaker
DEVICE = up5k
PACKAGE = sg48

# Default target: build the bitstream
all: $(BUILD_DIR)/$(PROJ).bin

# Step 1: Synthesis with Yosys
# Converts Verilog to a JSON netlist of logic gates
$(BUILD_DIR)/$(PROJ).json: $(PROJ).v
	yosys -p "synth_ice40 -top $(PROJ) -json $(BUILD_DIR)/$(PROJ).json" $(PROJ).v

# Step 2: Place and Route with nextpnr
# Assigns logic to physical FPGA resources and routes connections
$(BUILD_DIR)/$(PROJ).asc: $(BUILD_DIR)/$(PROJ).json icebreaker.pcf
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $(BUILD_DIR)/$(PROJ).json --pcf icebreaker.pcf --asc $(BUILD_DIR)/$(PROJ).asc

# Step 3: Bitstream generation with icepack
# Creates the binary file that configures the FPGA
$(BUILD_DIR)/$(PROJ).bin: $(BUILD_DIR)/$(PROJ).asc
	icepack $(BUILD_DIR)/$(PROJ).asc $(BUILD_DIR)/$(PROJ).bin

# Program the FPGA
# The bitstream is stored in flash, so it persists after power-off
prog: $(BUILD_DIR)/$(PROJ).bin
	iceprog $(BUILD_DIR)/$(PROJ).bin

# Remove all generated files
clean:
	rm -f $(BUILD_DIR)/$(PROJ).json $(BUILD_DIR)/$(PROJ).asc $(BUILD_DIR)/$(PROJ).bin

# Phony targets (not actual files)
.PHONY: all prog clean
