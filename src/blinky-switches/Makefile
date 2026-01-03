# Build directory for artifacts
BUILD_DIR = /tmp

PROJ = blinky_switches
DEVICE = up5k
PACKAGE = sg48

all: $(BUILD_DIR)/$(PROJ).bin

$(BUILD_DIR)/$(PROJ).json: $(PROJ).v
	yosys -p "synth_ice40 -top $(PROJ) -json $(BUILD_DIR)/$(PROJ).json" $(PROJ).v

$(BUILD_DIR)/$(PROJ).asc: $(BUILD_DIR)/$(PROJ).json icebreaker.pcf
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --json $(BUILD_DIR)/$(PROJ).json --pcf icebreaker.pcf --asc $(BUILD_DIR)/$(PROJ).asc

$(BUILD_DIR)/$(PROJ).bin: $(BUILD_DIR)/$(PROJ).asc
	icepack $(BUILD_DIR)/$(PROJ).asc $(BUILD_DIR)/$(PROJ).bin

prog: $(BUILD_DIR)/$(PROJ).bin
	iceprog $(BUILD_DIR)/$(PROJ).bin

clean:
	rm -f $(BUILD_DIR)/$(PROJ).json $(BUILD_DIR)/$(PROJ).asc $(BUILD_DIR)/$(PROJ).bin

.PHONY: all prog clean
