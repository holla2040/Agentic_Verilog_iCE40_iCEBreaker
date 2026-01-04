# Frequency Counter

A frequency counter with a selectable frequency generator for loopback testing.

## What It Does

The project has two sections:

1. **Generator**: Outputs a test signal at one of three selectable frequencies
2. **Counter**: Measures the frequency of an input signal and reports it via UART

Press buttons to select the generator frequency, connect generator output to counter input with a jumper, and watch the measured frequency appear on the serial terminal.

## Hardware Required

- iCEBreaker FPGA board
- iCEBreaker breakout board (for buttons)
- Jumper wire (to connect generator output to counter input)

## Pin Connections

| Signal | Pin | Description |
|--------|-----|-------------|
| clk | 35 | 12 MHz system clock |
| btn1 | 20 | Select 500 kHz |
| btn2 | 19 | Select 1 MHz |
| btn3 | 18 | Select 2 MHz |
| tx | 9 | UART transmit |
| freq_out | 4 | Generator output (PMOD1A pin 1) |
| freq_in | 48 | Counter input (PMOD1A pin 7) |

## Frequency Selection

| Button | Frequency | Divider |
|--------|-----------|---------|
| None | 500 kHz | 12 MHz / 24 |
| BTN1 | 500 kHz | 12 MHz / 24 |
| BTN2 | 1 MHz | 12 MHz / 12 |
| BTN3 | 2 MHz | 12 MHz / 6 |

## Output Format

UART output at 115200 baud shows measured frequency every second:

```
Freq: 500000 Hz
Freq: 1000000 Hz
Freq: 2000000 Hz
```

## Usage

1. Build and program:
   ```bash
   make
   make prog
   ```

2. Connect jumper from PMOD1A pin 1 to PMOD1A pin 7

3. Open serial terminal:
   ```bash
   screen /dev/ttyUSB1 115200
   ```

4. Press buttons to change generator frequency and observe measurements

## Concepts Demonstrated

1. **Clock dividers** - Creating lower frequencies from a master clock
2. **Reciprocal frequency counting** - Counting edges over a fixed time window
3. **Binary to decimal ASCII** - Converting counts to printable numbers
4. **Button synchronization** - Two-stage synchronizer for external inputs
5. **Edge detection** - Detecting rising edges of the input signal
6. **Gate timing** - Precise 1-second measurement window

## How It Works

### Frequency Generation

To create a lower frequency, toggle an output at regular intervals:

```
Output frequency = Input frequency / (2 × toggle_count)
```

For 1 MHz from 12 MHz: toggle every 6 clocks (12M / 2 / 6 = 1M)

### Frequency Measurement

Count rising edges during a 1-second window. The count directly equals frequency in Hz.

- 500,000 edges in 1 second = 500 kHz
- Resolution: 1 Hz (with 1-second gate time)
- Maximum: ~3 MHz (limited by 12 MHz clock and edge detection)

## Files

- `freq_counter.v` - Main Verilog module
- `icebreaker.pcf` - Pin constraints
- `Makefile` - Build rules
