# FPGA Project Instructions

This is an agentic Verilog coding project for the iCEBreaker FPGA board. We are beginners learning Verilog hardware description.

## Development Guidelines

When writing Verilog code:
- Include detailed comments explaining concepts for learning purposes
- Follow the heavily-commented style shown in existing examples (see README.md)
- Each module should explain what it does and how the hardware works
- Reference the existing projects in Blinky/, Blinky-switches/, and PWM-breathe/ as templates

## Build Process

All projects use Makefiles with the open-source toolchain:
```
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Pin Constraints

Each project needs an `icebreaker.pcf` file mapping Verilog ports to physical FPGA pins. Reference existing .pcf files when creating new projects.

Official PCF reference with all pin definitions (main board LEDs, breakout board LEDs/buttons, PMOD connectors):
https://github.com/icebreaker-fpga/icebreaker-verilog-examples/blob/main/icebreaker/icebreaker.pcf

## Reference Resources

- iCEBreaker hardware docs: https://github.com/icebreaker-fpga/icebreaker
- Official Verilog examples: https://github.com/icebreaker-fpga/icebreaker-verilog-examples
- Board schematic: docs/icebreaker-v1.1a-sch.pdf

## Project Examples

See README.md for descriptions of existing examples and the Verilog concepts they demonstrate.
