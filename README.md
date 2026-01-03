# FPGA Project

Learning agentic Verilog coding with the iCEBreaker FPGA board. This project explores hardware description using Verilog, with AI-assisted development to accelerate learning and experimentation.

## About

This repository contains beginner-friendly Verilog examples for the iCEBreaker FPGA, a low-cost open-source development board based on the Lattice iCE40UP5K. Each example is heavily commented to explain Verilog concepts and how hardware description differs from software programming.

## Project Structure

```
fpga/
├── src/
│   ├── blinky/          # Basic LED blinker
│   ├── blinky-switches/ # Variable speed blinker with switch control
│   ├── pwm-breathe/     # Smooth LED breathing effect using PWM
│   ├── led-chaser/      # Knight Rider running lights effect
│   ├── uart-tx/         # UART transmitter - sends "Hello" to PC
│   ├── uart-rx/         # UART receiver - LED control from keyboard
│   ├── uart-echo/       # UART echo with case toggle
│   └── freq-counter/    # Frequency counter with selectable generator
├── docs/                # Reference documentation
│   └── icebreaker-v1.1a-sch.pdf
└── README.md
```

## Examples

### Blinky
A simple LED blinker - the "Hello World" of FPGA development. Demonstrates:
- Module declaration and ports
- 24-bit counter register
- Sequential logic with `always @(posedge clk)`
- Combinational logic with `assign`
- Clock division to create visible blinking (~2.86 Hz)

### Blinky-switches
Extends the blinker with switch inputs to control blink speed. Demonstrates:
- Multiple input ports
- Conditional logic with `if/else`
- Different counter bit selection for varying frequencies
- Switch debouncing concepts

### PWM-breathe
Creates a smooth breathing/pulsing LED effect using Pulse Width Modulation. Demonstrates:
- PWM fundamentals (duty cycle control)
- Multi-counter designs
- State machines (direction flag)
- Perceived brightness vs. actual on/off switching

### LED-chaser
A "Knight Rider" running light effect using the 5 breakout board LEDs. Demonstrates:
- Multi-bit outputs (controlling multiple LEDs)
- Position tracking with a counter
- Direction flag for bidirectional movement
- Boundary detection and reversal
- Decoder logic (binary to one-hot conversion)

### UART-TX
Transmits "Hello from iCEBreaker!" to your PC every second over the built-in USB serial port. Demonstrates:
- UART protocol (start bit, 8 data bits LSB-first, stop bit)
- Baud rate generation (115200 bps from 12 MHz clock)
- State machines for serial protocol handling
- ROM initialization for storing message strings
- Bit shifting for serial output

**Testing:** `make prog`, then `screen /dev/ttyUSB1 115200`

### UART-RX
Receives keyboard input from PC and controls the accent LED. Type '1' to turn LED on, '0' to turn it off. Demonstrates:
- Asynchronous input synchronization (metastability prevention)
- Start bit detection (falling edge)
- Middle-of-bit sampling strategy for reliability
- Shift registers for assembling received bytes
- ASCII character comparison

**Testing:** `make prog`, then `screen /dev/ttyUSB1 115200`, type '1' or '0'

### UART-Echo
Echoes received characters back with case toggled (lowercase becomes uppercase and vice versa). Demonstrates:
- Combined RX and TX in a single module
- ASCII manipulation (XOR with 0x20 toggles case for letters)
- Character range detection (checking if byte is a letter)
- Chaining RX completion to TX start

**Testing:** `make prog`, then `screen /dev/ttyUSB1 115200`, type letters

### Freq-Counter
A frequency counter with a selectable frequency generator. The generator outputs on PMOD 1A pin 1, and the counter measures the signal on PMOD 1A pin 7. Connect them with a jumper for loopback testing. Demonstrates:
- Clock dividers for frequency generation (500 kHz, 1 MHz, 2 MHz)
- Reciprocal frequency counting (count edges over 1-second gate time)
- Binary to decimal ASCII conversion for UART output
- Input synchronization for external signals
- Button input for frequency selection

**Maximum measurable frequency:** ~3 MHz (limited by 12 MHz clock and edge detection)

**Testing:** Connect PMOD 1A pin 1 to pin 7 with a jumper, `make prog`, then `screen /dev/ttyUSB1 115200`. Press buttons to change generator frequency.

## Toolchain

These projects use the open-source FPGA toolchain:
- **Yosys** - Synthesis
- **nextpnr** - Place and route
- **icepack** - Bitstream generation
- **iceprog** - FPGA programming

Build any example with:
```bash
cd src/<example-directory>
make        # Build the bitstream (outputs to /tmp)
make prog   # Program the FPGA
make clean  # Remove build artifacts from /tmp
```

Build artifacts (`.json`, `.asc`, `.bin`) are generated in `/tmp` to keep source directories clean.

## Resources

- [iCEBreaker Hardware](https://github.com/icebreaker-fpga/icebreaker) - Board design files and documentation
- [iCEBreaker Verilog Examples](https://github.com/icebreaker-fpga/icebreaker-verilog-examples) - Official example projects
