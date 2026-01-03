# PWM Breathe

A smooth "breathing" LED effect using Pulse Width Modulation.

## What It Does

The accent LED smoothly fades in and out in a continuous breathing pattern, similar to a sleep indicator light. The full cycle (fade in + fade out) takes approximately 2.8 seconds.

## Concepts Demonstrated

- **PWM (Pulse Width Modulation)** - Controlling perceived brightness by rapidly switching on/off
- **Duty cycle** - The ratio of ON time to total cycle time
- **Multi-counter design** - Separate counters for PWM frequency and brightness ramping
- **Direction flag** - A single bit controlling fade-in vs fade-out
- **Brightness comparison** - LED on when `pwm_counter < brightness`

## How It Works

### PWM Counter (Fast)
An 8-bit counter cycles 0→255 at 46,875 Hz (12 MHz / 256). This is too fast for the eye to see, so we perceive an averaged brightness.

### Brightness Level
An 8-bit value (0-255) that sets the duty cycle. The LED is ON when `pwm_counter < brightness`.

### Breathing Logic (Slow)
A 16-bit counter creates ~2.8 second cycles. When it overflows, brightness increments or decrements based on the direction flag. At the limits (0 or 255), direction reverses.

```
Brightness: 0 ────────── 255 ────────── 0 ────────── 255
            │  fade in   │  fade out   │  fade in   │
```

## Hardware Required

- iCEBreaker FPGA board (main board only)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk    | 35  | 12 MHz clock |
| led    | 37  | Accent LED (PWM controlled) |

## Build and Program

```bash
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Exercises

1. **Change breathing speed** - Modify the breath_counter width (fewer bits = faster)
2. **Non-linear brightness** - Apply gamma correction for more natural fading
3. **Multiple LEDs** - Add RGB LED support with different phase offsets
4. **Button control** - Use a switch to pause/resume the breathing effect
