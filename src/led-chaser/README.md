# LED Chaser

A classic "Knight Rider" running light effect using the 5 LEDs on the iCEBreaker breakout board.

## What It Does

A single lit LED sweeps back and forth across the breakout board's 5 LEDs in a bouncing pattern:

```
LED1 LED2 LED3 LED4 LED5
 *    .    .    .    .   →
 .    *    .    .    .   →
 .    .    *    .    .   →
 .    .    .    *    .   →
 .    .    .    .    *   ←
 .    .    .    *    .   ←
 .    .    *    .    .   ←
 ...
```

## Concepts Demonstrated

- **Multi-bit outputs** - Controlling multiple LEDs from a single module
- **Position counter** - Using a register to track which LED is active (0-4)
- **Direction flag** - A single bit that controls left vs right movement
- **Boundary detection** - Reversing direction when reaching either end
- **Edge detection** - Detecting clock transitions to move once per cycle
- **Decoder/one-hot output** - Converting a binary position to individual LED signals

## Hardware Required

- iCEBreaker FPGA board
- iCEBreaker breakout board (snap-off section with 5 LEDs)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk    | 35  | 12 MHz clock |
| LED1   | 26  | Green LED |
| LED2   | 27  | Green LED |
| LED3   | 25  | Green LED |
| LED4   | 23  | Green LED |
| LED5   | 21  | Red LED |

## Build and Program

```bash
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Exercises

1. **Change speed** - Edit `counter[21]` to `counter[20]` (faster) or `counter[22]` (slower)
2. **Reverse start** - Change `direction = 0` to `direction = 1` to start moving left
3. **Wider light** - Modify the decoder to light 2 adjacent LEDs simultaneously
