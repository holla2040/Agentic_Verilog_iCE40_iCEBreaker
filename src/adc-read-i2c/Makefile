# ============================================================================
# ADS1115 I2C ADC Reader - Makefile
# ============================================================================
#
# Build process for iCEBreaker FPGA using open-source toolchain:
#   1. yosys    - Synthesis (Verilog -> JSON netlist)
#   2. nextpnr  - Place and route (JSON -> ASC bitstream)
#   3. icepack  - Binary generation (ASC -> BIN)
#   4. iceprog  - Programming (BIN -> FPGA)
#
# Usage:
#   make       - Build the bitstream
#   make prog  - Program the iCEBreaker
#   make clean - Remove build artifacts
#
# ============================================================================

PROJ = adc_read_i2c
TOP = top

# Source files - add modules as they are implemented
SOURCES = top.v uart_tx.v i2c_master.v
PCF = icebreaker.pcf

# Build targets
all: $(PROJ).bin

# Synthesis: Verilog -> JSON netlist
$(PROJ).json: $(SOURCES)
	yosys -p "synth_ice40 -top $(TOP) -json $@" $(SOURCES)

# Place and route: JSON -> ASC
$(PROJ).asc: $(PROJ).json $(PCF)
	nextpnr-ice40 --up5k --package sg48 --json $< --pcf $(PCF) --asc $@

# Binary generation: ASC -> BIN
$(PROJ).bin: $(PROJ).asc
	icepack $< $@

# Program the FPGA
prog: $(PROJ).bin
	iceprog $<

# Clean build artifacts
clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).bin

.PHONY: all prog clean
