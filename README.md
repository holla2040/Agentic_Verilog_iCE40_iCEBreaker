# Agentic Verilog for iCE40 iCEBreaker

Using Claude Code to generate Verilog HDL for the iCEBreaker FPGA development board featuring the Lattice iCE40 UP5K.

## Overview

This repository demonstrates an agentic approach to FPGA development where Claude Code assists in generating, reviewing, and iterating on Verilog designs targeting the iCEBreaker board. By providing Claude Code with component datasheets and design requirements, you can rapidly prototype digital logic designs.

## Hardware

### iCEBreaker Board

The [iCEBreaker](https://1bitsquared.com/products/icebreaker) is an open-source FPGA development board designed for learning and prototyping. The official repository with schematics, examples, and documentation is available at [github.com/icebreaker-fpga/icebreaker](https://github.com/icebreaker-fpga/icebreaker).

Reference materials included in `docs/`:
- <a href="docs/icebreaker-v1.1a-sch.pdf" target="_blank">icebreaker-v1.1a-sch.pdf</a> - Full board schematic
- <a href="docs/icebreaker-v1_0b-legend-jumpers.jpg" target="_blank">icebreaker-v1_0b-legend-jumpers.jpg</a> - Jumper configuration guide

### Block Diagram

<a href="docs/icebreaker-block-diagram.jpg" target="_blank">
  <img src="docs/icebreaker-block-diagram.jpg" alt="iCEBreaker Block Diagram">
</a>

### Board Pin Legend

<a href="docs/icebreaker-v1_0b-legend.jpg" target="_blank">
  <img src="docs/icebreaker-v1_0b-legend.jpg" alt="iCEBreaker Pin Legend">
</a>

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

### PMOD Modules

#### PMOD AD1 - Two-Channel 12-bit ADC

The <a href="https://digilent.com/reference/pmod/pmodad1/reference-manual" target="_blank">PMOD AD1</a> features two Analog Devices AD7476A 12-bit ADCs with a 1 MSPS sampling rate. It uses an SPI interface and is ideal for analog signal acquisition.

Reference materials in `docs/`:
- <a href="docs/pmodad1_sch.pdf" target="_blank">pmodad1_sch.pdf</a> - PMOD AD1 schematic
- <a href="docs/ad7476a.pdf" target="_blank">ad7476a.pdf</a> - AD7476A ADC datasheet

#### PMOD DA2 - Two-Channel 12-bit DAC

The <a href="https://digilent.com/reference/pmod/pmodda2/reference-manual" target="_blank">PMOD DA2</a> features two Texas Instruments DAC121S101 12-bit DACs with an SPI interface. It provides dual analog outputs for signal generation applications.

Reference materials in `docs/`:
- <a href="docs/pmodda2_sch.pdf" target="_blank">pmodda2_sch.pdf</a> - PMOD DA2 schematic
- <a href="docs/dac121s101.pdf" target="_blank">dac121s101.pdf</a> - DAC121S101 DAC datasheet

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
│   ├── icebreaker-v1_0b-legend-jumpers.jpg  # Jumper configuration
│   ├── pmodad1_sch.pdf         # PMOD AD1 schematic
│   └── pmodda2_sch.pdf         # PMOD DA2 schematic
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
