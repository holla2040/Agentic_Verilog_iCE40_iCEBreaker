# FPGA Project Instructions

This is an agentic Verilog coding project for the iCEBreaker FPGA board. We are beginners learning Verilog hardware description.

## Git Workflow

**Do not commit or push changes without explicit instructions from the user.** Always wait for the user to explicitly request a commit or push before performing these operations.

## Target Hardware

- **Board**: iCEBreaker v1.0b/v1.1a
- **FPGA**: Lattice iCE40 UP5K (SG48 package)
- **Clock**: 12 MHz oscillator

## Key Specifications

When generating Verilog for this target:

- System clock: 12 MHz
- Logic cells: 5,280
- SPRAM: 1 Mbit (4 x 256Kbit blocks)
- DPRAM: 120 Kbit
- DSP blocks: 8 (16x16 multipliers)
- PLL: 1
- Hard IP: 2x I2C, 2x SPI

## Development Guidelines

When writing Verilog code:
- Include detailed comments explaining concepts for learning purposes
- Follow the heavily-commented style shown in existing examples (see README.md)
- Each module should explain what it does and how the hardware works
- Reference the existing projects in src/ as templates

## Verilog Style Guidelines

- Use lowercase with underscores for signal names
- Prefix clock signals with `clk_`
- Prefix reset signals with `rst_` (active high) or `rst_n_` (active low)
- Use `_i` suffix for inputs, `_o` suffix for outputs
- Include timing constraints in comments for critical paths

## Build Process

All projects use Makefiles with the open-source toolchain:
```
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Pin Constraints

Each project needs an `icebreaker.pcf` file mapping Verilog ports to physical FPGA pins. Reference existing .pcf files when creating new projects.

Reference `docs/icebreaker-v1_0b-legend.jpg` for pin mappings. Common pins:

- `CLK` - Pin 35 (12 MHz clock input)
- `BTN_N` - Pin 10 (active-low user button)
- `LEDR_N` - Pin 11 (active-low red LED)
- `LEDG_N` - Pin 37 (active-low green LED)
- `LED1-5` - Accent LEDs on accent PMOD

Official PCF reference with all pin definitions (main board LEDs, breakout board LEDs/buttons, PMOD connectors):
https://github.com/icebreaker-fpga/icebreaker-verilog-examples/blob/main/icebreaker/icebreaker.pcf

## Toolchain Commands

```bash
# Synthesize
yosys -p "synth_ice40 -top <module> -json <output>.json" <input>.v

# Place and route
nextpnr-ice40 --up5k --package sg48 --json <input>.json --pcf <constraints>.pcf --asc <output>.asc

# Generate bitstream
icepack <input>.asc <output>.bin

# Program
iceprog <input>.bin
```

## Simulation

Use Icarus Verilog for simulation:

```bash
iverilog -o <testbench>.vvp <testbench>.v <module>.v
vvp <testbench>.vvp
gtkwave <waveform>.vcd
```

## Reference Documentation

Datasheets in `docs/` directory:

- `iCE40-UltraPlus-Family-Data-Sheet.pdf` - FPGA specifications
- `icebreaker-v1.1a-sch.pdf` - Board schematic
- `ad7476a.pdf`, `ads1115.pdf` - ADC datasheets
- `dac121s101.pdf` - DAC datasheet

## Reference Resources

- iCEBreaker hardware docs: https://github.com/icebreaker-fpga/icebreaker
- Official Verilog examples: https://github.com/icebreaker-fpga/icebreaker-verilog-examples
- Board schematic: docs/icebreaker-v1.1a-sch.pdf

## Project Examples

See README.md for descriptions of existing examples and the Verilog concepts they demonstrate.
