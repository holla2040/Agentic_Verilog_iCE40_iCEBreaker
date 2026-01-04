# DAC Ramp Generator

Generates a triangular ramp waveform on the PMOD DA2 (DAC121S101) output. The voltage ramps smoothly from 0V to 3.3V and back down continuously.

## Hardware Required

- iCEBreaker FPGA board
- PMOD DA2 (Digilent) connected to PMOD1A

## Pin Connections

| Signal | PMOD DA2 | FPGA Pin | Description |
|--------|----------|----------|-------------|
| SYNC | J1-1 | 4 | Chip select (active low) |
| DINA | J1-2 | 2 | Data input for DAC channel A |
| SCLK | J1-4 | 45 | SPI clock |

## Features

- **PLL-based clock**: Uses iCE40 PLL to generate 60 MHz from 12 MHz input
- **30 MHz SPI**: Maximum speed supported by DAC121S101
- **Smooth ramp**: Steps by 1 through all 4096 DAC values
- **Triangle wave**: ~200 Hz output frequency

## Timing

- PLL output: 60 MHz
- SPI clock: 30 MHz
- DAC update rate: ~1.66 million updates/second
- Triangle wave: ~200 Hz (8192 steps per cycle)

## Usage

```bash
make        # Build bitstream
make prog   # Program iCEBreaker
make clean  # Remove build artifacts
```

Connect an oscilloscope to the PMOD DA2 channel A output (J2 pins 1-2) to view the triangle waveform.

## Concepts Demonstrated

- PLL instantiation (SB_PLL40_PAD)
- SPI master interface
- DAC121S101 protocol (16-bit word format)
- State machine design
- Triangle wave generation with direction flag
