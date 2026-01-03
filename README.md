# Agentic Verilog for iCE40 iCEBreaker

Using Claude Code to generate Verilog HDL for the iCEBreaker FPGA development board featuring the Lattice iCE40 UP5K.

## Overview

This repository demonstrates an agentic approach to FPGA development where Claude Code assists in generating, reviewing, and iterating on Verilog designs targeting the iCEBreaker board. By providing Claude Code with component datasheets and design requirements, you can rapidly prototype digital logic designs.

## Hardware

### iCEBreaker Board

The [iCEBreaker](https://1bitsquared.com/products/icebreaker) is an open-source FPGA development board designed for learning and prototyping. The official repository with schematics, examples, and documentation is available at [github.com/icebreaker-fpga/icebreaker](https://github.com/icebreaker-fpga/icebreaker).

Reference materials included in `docs/`:
- `icebreaker-v1.1a-sch.pdf` - Full board schematic
- `icebreaker-v1_0b-legend-jumpers.jpg` - Jumper configuration guide

### Block Diagram

![iCEBreaker Block Diagram](docs/icebreaker-block-diagram.jpg)

### Board Pin Legend

![iCEBreaker Pin Legend](docs/icebreaker-v1_0b-legend.jpg)

*Note: We are using the iCEBreaker v1.1A board. The pin legend above is from v1.0b, but the pinout is expected to be the same.*

### Features

- Lattice iCE40 UP5K FPGA
- USB programming via FTDI FT2232H
- PMOD connectors for expansion
- RGB LED and user buttons
- Open-source toolchain support

### Lattice iCE40 UP5K FPGA

The iCE40 UltraPlus 5K is a low-power FPGA well-suited for edge applications:

- 5,280 logic cells
- 1 Mbit SPRAM (Single-Port RAM)
- 120 Kbit DPRAM (Dual-Port RAM)
- 8 multiplier blocks (16x16)
- 1 PLL, 2 I2C, 2 SPI hard IP blocks
- Up to 39 GPIO pins
- Ultra-low power operation (as low as 75 uA in standby)

## Using Claude Code for Verilog Generation

### Workflow

1. **Describe your design requirements** - Tell Claude Code what you want to build (e.g., "Create an SPI controller to interface with the AD7476A ADC")

2. **Reference datasheets** - Point Claude Code to the relevant datasheets in the `docs/` directory for timing diagrams, register maps, and protocol specifications

3. **Iterate on the design** - Review generated Verilog, request modifications, and refine the implementation

4. **Simulate and test** - Use the open-source toolchain to simulate and verify the design

5. **Synthesize and program** - Build the bitstream and program the iCEBreaker

### Example Prompts

```
Generate a Verilog module for an SPI master that can read from the AD7476A ADC.
Use the timing specifications from docs/ad7476a.pdf.
```

```
Create a PWM controller with configurable duty cycle for driving an LED,
targeting 1kHz at the 12MHz iCEBreaker clock.
```

```
Review this Verilog module for timing issues and suggest improvements
for the iCE40 UP5K target.
```

### Best Practices

- **Provide context** - Share relevant datasheets and constraints with Claude Code
- **Be specific** - Include clock frequencies, interface requirements, and target specifications
- **Iterate** - Start with a basic implementation and refine it through conversation
- **Verify** - Always simulate designs before programming the FPGA
- **Review timing** - Ask Claude Code to check for clock domain crossings and timing issues

## Project Structure

```
.
├── docs/               # Component datasheets and reference materials
│   ├── ad7476a.pdf             # AD7476A 12-bit ADC datasheet
│   ├── ads1115.pdf             # ADS1115 16-bit ADC datasheet
│   ├── dac121s101.pdf          # DAC121S101 12-bit DAC datasheet
│   ├── iCE40-UltraPlus-Family-Data-Sheet.pdf
│   ├── icebreaker-v1.1a-sch.pdf        # iCEBreaker schematic
│   ├── icebreaker-block-diagram.jpg    # iCEBreaker block diagram
│   ├── icebreaker-v1_0b-legend.jpg     # Board pin legend
│   └── icebreaker-v1_0b-legend-jumpers.jpg  # Jumper configuration
├── src/                # Verilog source files
├── LICENSE
└── README.md
```

## Toolchain

This project uses the open-source FPGA toolchain:

- **Yosys** - Verilog synthesis
- **nextpnr-ice40** - Place and route
- **icepack** - Bitstream generation
- **iceprog** - FPGA programming

### Installation (Ubuntu/Debian)

```bash
sudo apt install fpga-icestorm yosys nextpnr-ice40
```

### Installation (macOS)

```bash
brew install icestorm yosys nextpnr
```

## License

MIT License - See [LICENSE](LICENSE) for details.
