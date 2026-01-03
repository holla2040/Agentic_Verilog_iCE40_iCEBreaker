# UART TX

A serial transmitter that sends "Hello from iCEBreaker!" to your PC.

## What It Does

Every second, the FPGA transmits the message "Hello from iCEBreaker!" over the built-in USB serial port. The accent LED blinks during transmission.

## Concepts Demonstrated

- **UART protocol** - Start bit, 8 data bits (LSB first), stop bit
- **Baud rate generation** - Dividing 12 MHz clock to get 115200 bps timing
- **State machines** - IDLE → START → DATA → STOP cycle
- **ROM initialization** - Storing a message string in hardware
- **Bit shifting** - Sending bits one at a time with `tx_byte >> 1`

## How It Works

### UART Frame Format
```
IDLE   START   D0 D1 D2 D3 D4 D5 D6 D7   STOP   IDLE
HIGH   LOW     <---- 8 data bits ---->   HIGH   HIGH
```

### Timing
- Baud rate: 115200 bps
- Clocks per bit: 12,000,000 / 115,200 ≈ 104
- Each bit lasts ~8.68 microseconds

### State Machine
1. **IDLE** - Wait for 1-second trigger, TX line HIGH
2. **START** - Send start bit (LOW) for 104 clocks
3. **DATA** - Send 8 data bits, LSB first, 104 clocks each
4. **STOP** - Send stop bit (HIGH) for 104 clocks
5. Repeat for next character or return to IDLE

## Hardware Required

- iCEBreaker FPGA board (main board only)
- USB cable (for both programming and serial communication)

## Pin Assignments

| Signal | Pin | Description |
|--------|-----|-------------|
| clk    | 35  | 12 MHz clock |
| tx     | 9   | UART TX → FTDI → USB → PC |
| led    | 37  | Activity LED |

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

# Or use picocom
picocom -b 115200 /dev/ttyUSB1

# Exit screen: Ctrl+A, K, Y
# Exit picocom: Ctrl+A, Ctrl+X
```

You should see "Hello from iCEBreaker!" appearing every second.

## Exercises

1. **Change the message** - Modify the `message[]` array and `MSG_LEN`
2. **Change baud rate** - Try 9600 baud (CLOCKS_PER_BIT = 1250)
3. **Send faster** - Reduce delay between messages
4. **Add a counter** - Send incrementing numbers (requires binary-to-ASCII conversion)
