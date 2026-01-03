# UART RX

A serial receiver that controls an LED from keyboard input.

## What It Does

Type on your keyboard in a terminal program:
- Press `1` → LED turns **ON**
- Press `0` → LED turns **OFF**
- Other characters are ignored

## Concepts Demonstrated

- **Input synchronization** - Two flip-flop synchronizer to prevent metastability
- **Start bit detection** - Detecting the falling edge when data arrives
- **Middle-of-bit sampling** - Sampling at clock 52 of 104 for reliability
- **Shift register** - Building a byte from individual bits with `{rx_sync, rx_byte[7:1]}`
- **ASCII comparison** - Checking for '0' (0x30) and '1' (0x31)

## How It Works

### UART Frame (Receiving)
```
IDLE   START   D0 D1 D2 D3 D4 D5 D6 D7   STOP   IDLE
HIGH   LOW     <---- 8 data bits ---->   HIGH   HIGH
       ↑
  Detect this falling edge
```

### Sampling Strategy
Sample in the **middle** of each bit period for maximum noise margin:
```
|<-------- 104 clocks -------->|
          ↑
    Sample here (clock 52)
```

### State Machine
1. **IDLE** - Wait for RX line to go LOW (start bit)
2. **START** - Wait half bit (52 clocks) to center, verify still LOW
3. **DATA** - Sample 8 bits at middle of each bit period
4. **STOP** - Sample stop bit, process received byte

### LED Control
The accent LED on pin 37 is **active LOW**:
- Output `0` = LED ON
- Output `1` = LED OFF

## Hardware Required

- iCEBreaker FPGA board (main board only)
- USB cable (for both programming and serial communication)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk    | 35  | 12 MHz clock |
| rx     | 6   | UART RX ← FTDI ← USB ← PC |
| led    | 37  | Accent LED (active LOW) |

## Build and Program

```bash
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker board
make clean  # Remove build artifacts
```

## Testing

```bash
# Open a terminal at 115200 baud
screen /dev/ttyUSB1 115200

# Type '1' to turn LED on
# Type '0' to turn LED off

# Exit screen: Ctrl+A, K, Y
```

## Troubleshooting

- **LED doesn't respond** - Check you're using /dev/ttyUSB1 (not USB0), verify 115200 baud
- **LED responds erratically** - Try different USB cable or port
- **No serial port** - Ensure FPGA is programmed and connected

## Exercises

1. **More controls** - Use '2'-'5' to control breakout board LEDs
2. **Echo back** - Combine with UART TX to echo received characters
3. **Toggle mode** - Make '1' toggle the LED instead of just turning it on
4. **Error detection** - Check stop bit is HIGH, blink rapidly on framing error
