# Blinky

The "Hello World" of FPGA development - a simple LED blinker.

## What It Does

Blinks the accent LED on the iCEBreaker main board at approximately 2.86 Hz (about 3 times per second).

## Concepts Demonstrated

- **Module declaration** - Defining inputs and outputs with `module`
- **Register declaration** - Using `reg [23:0]` for a 24-bit counter
- **Sequential logic** - Using `always @(posedge clk)` for clock-synchronized updates
- **Combinational logic** - Using `assign` for direct wire connections
- **Clock division** - Using counter bits to divide the 12 MHz clock to visible rates
- **Non-blocking assignment** - Using `<=` in sequential logic

## How It Works

A 24-bit counter increments every clock cycle (12 million times per second). Bit 21 of the counter toggles at:

```
12,000,000 Hz / 2^22 = ~2.86 Hz
```

The LED output is directly connected to this bit, creating a visible blink.

## Hardware Required

- iCEBreaker FPGA board (main board only, no breakout needed)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk    | 35  | 12 MHz clock |
| led    | 37  | Accent LED (active HIGH) |

## Build and Program

```bash
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Exercises

1. **Change blink rate** - Try `counter[23]` (~0.7 Hz) or `counter[19]` (~11 Hz)
2. **Add more LEDs** - Add outputs for breakout board LEDs (pins 26, 27, 25, 23, 21)
3. **Understand timing** - Calculate the exact frequency for each counter bit
