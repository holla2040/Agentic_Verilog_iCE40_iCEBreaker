# ============================================================================
# Makefile for UART RX Project
# ============================================================================
#
# Uses the open-source iCE40 FPGA toolchain:
#   - Yosys:     Verilog synthesis
#   - nextpnr:   Place and route
#   - icepack:   Bitstream generation
#   - iceprog:   FPGA programming
#
# Usage:
#   make        - Build the project
#   make prog   - Program the iCEBreaker board
#   make clean  - Remove generated files
#
# ============================================================================

PROJ = uart_rx
DEVICE = up5k
PACKAGE = sg48

all: $(PROJ).bin

$(PROJ).json: $(PROJ).v
	yosys -p "synth_ice40 -top $(PROJ) -json $(PROJ).json" $(PROJ).v

$(PROJ).asc: $(PROJ).json icebreaker.pcf
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $(PROJ).json --pcf icebreaker.pcf --asc $(PROJ).asc

$(PROJ).bin: $(PROJ).asc
	icepack $(PROJ).asc $(PROJ).bin

prog: $(PROJ).bin
	iceprog $(PROJ).bin

clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).bin

.PHONY: all prog clean
