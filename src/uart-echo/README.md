# UART Echo with Case Toggle

Echoes received characters back with case toggled - lowercase becomes uppercase and vice versa.

## What It Does

Type on your keyboard in a terminal:
- Type `h` → receive `H`
- Type `H` → receive `h`
- Type `5` → receive `5` (non-letters unchanged)

The accent LED blinks each time a character is echoed.

## Concepts Demonstrated

1. **Combined RX and TX** - Full duplex UART in a single module
2. **ASCII bit manipulation** - XOR with 0x20 toggles case
3. **Character range detection** - Checking if byte is a letter (A-Z or a-z)
4. **RX-to-TX handshaking** - RX completion triggers TX start
5. **Input synchronization** - Two-stage synchronizer for RX input

## How Case Toggling Works

In ASCII, uppercase and lowercase letters differ only in bit 5:

```
'A' = 0x41 = 0100_0001     'a' = 0x61 = 0110_0001
'B' = 0x42 = 0100_0010     'b' = 0x62 = 0110_0010
'Z' = 0x5A = 0101_1010     'z' = 0x7A = 0111_1010
              ↑                          ↑
           bit 5 = 0               bit 5 = 1
```

XOR with 0x20 (bit 5 only) toggles the case:
- `'A' ^ 0x20 = 'a'`
- `'a' ^ 0x20 = 'A'`

## Hardware Required

- iCEBreaker FPGA board (main board only)
- USB cable (for programming and serial communication)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk | 35 | 12 MHz clock |
| rx | 6 | UART RX (from PC) |
| tx | 9 | UART TX (to PC) |
| led | 37 | Activity LED |

## Usage

1. Build and program:
   ```bash
   make
   make prog
   ```

2. Open serial terminal at 115200 baud:
   ```bash
   screen /dev/ttyUSB1 115200
   ```

3. Type letters and watch them echo back with toggled case

4. Exit screen: `Ctrl+A`, `K`, `Y`

## Architecture

```
RX pin → [Receiver] → rx_byte → [Case Toggle] → tx_byte → [Transmitter] → TX pin
                          ↓
                    rx_ready pulse
                          ↓
                    triggers TX
```

## Timing

- Baud rate: 115200 bps
- Clocks per bit: 104 (12 MHz / 115200)
- Half bit: 52 clocks (for middle-of-bit sampling)

## Files

- `uart_echo.v` - Main Verilog module with RX, TX, and case toggle
- `icebreaker.pcf` - Pin constraints
- `Makefile` - Build rules

## Exercises

1. **Add more transformations** - ROT13, uppercase only, lowercase only
2. **Add echo counter** - Display count of echoed characters
3. **Add line buffering** - Echo entire lines instead of single characters
4. **Add command mode** - Special commands like `\n` to toggle LED
