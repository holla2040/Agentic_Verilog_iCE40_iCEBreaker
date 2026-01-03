# Blinky with Switches

A variable-speed LED blinker controlled by the breakout board switches.

## What It Does

The accent LED blinks at different speeds depending on which switch is pressed:

| Switch | Blink Rate | Counter Bit |
|--------|------------|-------------|
| None   | ~0.7 Hz (slow) | bit 23 |
| SW1    | ~2.9 Hz (medium) | bit 21 |
| SW2    | ~11.4 Hz (fast) | bit 19 |
| SW3    | ~46 Hz (very fast) | bit 17 |

## Concepts Demonstrated

- **Multiple inputs** - Reading 3 switch signals
- **Combinational multiplexing** - Using `always @(*)` for input-dependent logic
- **Priority encoding** - `if/else if/else` creates priority (SW1 > SW2 > SW3)
- **Different clock divisions** - Selecting different counter bits for different speeds

## How It Works

The same 24-bit counter from the basic Blinky runs continuously. The switches select which bit of the counter drives the LED output. Higher bits toggle slower, lower bits toggle faster.

## Hardware Required

- iCEBreaker FPGA board
- iCEBreaker breakout board (for the 3 switches)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk    | 35  | 12 MHz clock |
| led    | 37  | Accent LED |
| sw1    | 20  | Switch 1 (active HIGH) |
| sw2    | 19  | Switch 2 (active HIGH) |
| sw3    | 18  | Switch 3 (active HIGH) |

## Build and Program

```bash
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Exercises

1. **Add more speeds** - Use additional counter bits for more speed options
2. **Combine switches** - Make combinations (SW1+SW2) select different speeds
3. **Speed display** - Light different LEDs to show current speed setting
