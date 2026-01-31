# FPGA Video Series - Future Topics

A roadmap for additional agentic Verilog tutorials, organized by priority and complexity.

**Target Hardware**: iCEBreaker v1.0b/v1.1a with Lattice iCE40 UP5K
- Note: Unlike boards like the Nandland Go Board, iCEBreaker does NOT have built-in 7-segment displays or multiple user buttons. It has minimal onboard I/O (1 button, 2 LEDs) - most I/O comes via PMODs.

---

## Future Projects (A-Z)

### A. I2C for ADS1115 Breakout Board (Soft Implementation) ✓ COMPLETED

**Location**: `src/adc-read-i2c/`

Implemented I2C master in pure Verilog to read from the 16-bit ADS1115 ADC:
- Complete I2C protocol: START, STOP, ACK/NACK, byte read/write
- Open-drain emulation using SB_IO tristate primitives
- Timeout detection for stuck bus conditions
- UART output at 115200 baud (hex format, 5 readings/sec)
- Comprehensive README with I2C protocol documentation

**Concepts demonstrated**:
- I2C protocol fundamentals (START/STOP conditions, ACK/NACK, 7-bit addressing)
- Bidirectional signals (`inout` ports)
- Tristate buffers (SB_IO primitive for open-drain)
- Multi-byte transactions with register addressing

---

### A.2 Shared Module Library

**Why**: Establish canonical, reusable IP blocks for future projects. Existing projects are published and will not be modified.

**Note**: Existing projects (`uart-tx/`, `dac-adc-loopback/`, `adc-read-i2c/`) each have their own implementations and are fixed. The library is for new projects going forward.

**Proposed structure**:
```
src/
├── lib/                          # Shared reusable modules for NEW projects
│   ├── uart_tx.v                 # Canonical UART transmitter
│   ├── uart_rx.v                 # UART receiver (future)
│   ├── i2c_master.v              # Generic I2C master (future)
│   ├── spi_master.v              # Generic SPI master (future)
│   └── debounce.v                # Button debouncer (after Project B)
```

**Future candidates**: `i2c_master.v` and `spi_master.v` are natural additions since I2C and SPI are the most common protocols for interfacing FPGAs with external devices (sensors, ADCs, DACs, EEPROMs, displays, etc.).

**What to do**:
1. Create `src/lib/` directory
2. Create canonical `uart_tx.v` with consistent interface conventions
3. Document library usage in `src/lib/README.md`
4. Future projects reference `../lib/` in their Makefiles

**Canonical uart_tx.v interface**:
```verilog
module uart_tx #(
    parameter CLOCKS_PER_BIT = 104   // Default: 115200 @ 12MHz
) (
    input  wire       clk_i,
    input  wire [7:0] data_i,
    input  wire       start_i,
    output wire       ready_o,       // HIGH when idle
    output reg        tx_o
);
```

**New concepts**:
- IP reuse and library management
- Consistent module interfaces (`_i`/`_o` suffixes)
- Parameterization for flexibility
- Makefile include paths

**Priority**: Create before starting new projects.

---

### B. Button Debouncing (HIGH PRIORITY)

**Why**: Practical necessity, teaches important timing concepts

**Note**: iCEBreaker only has one user button (BTN_N). Consider using PMOD buttons or explaining concept with that single button.

**What to cover**:
- Why buttons bounce (mechanical explanation)
- Metastability and synchronization
- Debounce timing requirements
- Edge detection (rising/falling)
- Creating a reusable debounce module

**New concepts**:
- Input synchronization (2-FF synchronizer)
- Debounce counters
- Clean edge detection

**Demo**: Counter that increments reliably with button press, displayed via UART

**References**:
- [FPGA4student - Debouncing Verilog Code](https://www.fpga4student.com/2017/04/simple-debouncing-verilog-code-for.html)
- [Nandland - Switch Debouncing](https://nandland.com/project-4-debounce-a-switch/)

---

### C. STM32 & MCU Integration

**Concept**: FPGA as peripheral to microcontrollers using Arduino ecosystem

**Why it fits**:
- Bridges FPGA learning to familiar MCU development
- Shows real-world FPGA use cases (offloading, co-processing)
- Arduino codebase makes MCU side accessible
- Demonstrates FPGA as I2C/SPI slave (vs master in other projects)
- STM32 Blue Pill is cheap (~$2) and widely available

#### Part 1: SPI Slave Interface with STM32
**What it does**: FPGA acts as SPI peripheral, STM32 reads/writes FPGA registers
**Video concept**: "Give your STM32 superpowers with an FPGA co-processor"

#### Part 2: I2C Slave Interface with STM32
**What it does**: FPGA appears as I2C device on the bus using iCE40 hard IP

#### Part 3: DMA Streaming with STM32 (Advanced)
**What it does**: High-speed continuous data transfer using DMA
**Use case**: Stream ADC samples from FPGA to STM32 at high rates

#### Part 4: ESP32 OTA FPGA Bitstream Programming (HIGH VALUE)
**What it does**: Wirelessly reprogram the FPGA over WiFi using ESP32
**Why this is awesome**:
- No USB cable needed after initial setup
- Remote FPGA updates (IoT applications)
- Teaches SPI flash programming protocol

---

### D. I2C vs SPI Deep Dive: Soft vs Hard IP Comparison

**Concept**: Compare I2C and SPI protocols side-by-side, implementing both in pure Verilog AND using iCE40's hardened cores

**Why this is valuable**:
- Directly compares two most common serial protocols
- Shows trade-offs of soft (Verilog) vs hard (primitive) implementations
- Teaches when to use each approach
- Demonstrates iCE40's unique hard IP features

**Demo**:
- Side-by-side EEPROM access (e.g., 24LC256 for I2C, 25LC256 for SPI)
- Benchmark throughput and resource usage

---

### E. Mermaid Diagrams for Documentation

**Concept**: Add state machine visualization to existing projects (e.g., UART-Echo) using Mermaid.js in READMEs.

**Deliverable**: Visual state diagrams, timing diagrams, and data flow graphs to improve project documentation.

---

### F. Digital Filters

**Concept**: DSP fundamentals using the iCE40's 8 DSP blocks

#### Part 1: Signal Source (DDS - Direct Digital Synthesis)
**What it does**: Generate two sine waves at different frequencies
**New concepts**: NCOs, Phase accumulators, Sine LUTs

#### Part 2: FIR Low-Pass Filter
**What it does**: Filter out high-frequency components
**New concepts**: Convolution, Tap coefficients, MAC operations, Fixed-point math

---

### G. Verilog Learning Plan / Roadmap

**Concept**: Create a structured `LEARNING_PATH.md` document organizing all projects into a coherent curriculum (Level 1: Fundamentals -> Level 6: Advanced).

---

### H. Testbenches & Simulation (HIGH PRIORITY)

**Why**: Essential skill missing from current series. Every professional uses simulation.

**What to cover**:
- Writing non-synthesizable test code
- `initial` blocks and `#` delays
- `$display`, `$monitor`, `$dumpvars`
- Self-checking testbenches
- Using Icarus Verilog (`iverilog`) and GTKWave

---

### I. Memory: SPRAM and Block RAM

**Why**: iCE40 UP5K has 1Mbit SPRAM - should learn to use it!

**What to cover**:
- iCE40 memory types (SPRAM, EBR, registers)
- SB_SPRAM256KA primitive instantiation
- Memory initialization
- Read/write timing
- Simple applications: data buffer, sample storage

---

### J. FIFO (First-In-First-Out Buffer)

**Why**: Fundamental building block, bridges different clock rates

**What to cover**:
- Circular buffer concepts
- Write/Read pointers
- Full/Empty flags
- Synchronous vs Asynchronous FIFOs

---

### K. Dual Stepper Motor Motion Control (GRBL-style)

**Concept**: FPGA-based CNC/3D printer style motion controller with coordinated 2-axis movement

**Key features**:
- 2 independent axes (X, Y) with step/direction outputs
- Trapezoidal velocity profile (acceleration/cruise/deceleration)
- Coordinated motion (Bresenham's algorithm)
- Real-time pulse generation (up to 200kHz+)

---

### L. DC Servo Motor Closed-Loop Control

**Concept**: PID position/velocity control of DC motor with quadrature encoder feedback

**Why this is valuable**:
- Introduces closed-loop control (vs open-loop steppers)
- Real-world industrial control technique
- FPGA advantage: High-speed control loop (>100kHz)

**Modules**:
- Quadrature Decoder
- Velocity Calculator
- PID Controller (Fixed-point)
- PWM H-Bridge Driver

---

### M. Audio Synthesis

**Why**: Uses existing DAC, creates audible output, fun project

**What to cover**:
- Audio sample rates
- Simple waveforms (square, triangle, sawtooth)
- Tone generation
- Simple envelope (ADSR)

---

### N. Clock Domain Crossing (ADVANCED)

**Why**: Critical for robust designs, often poorly understood

**What to cover**:
- Metastability explained
- Two-flop synchronizer
- Pulse synchronization
- Handshake synchronization
- FIFO for data crossing

---

### O. High-Speed ADC Burst Capture (FFT Prep)

**Concept**: Capture a 50ms burst of high-speed ADC data into SPRAM for offline analysis or internal FFT processing.

**Why it fits**:
- Leverages the iCE40UP5K's unique 128KB SPRAM
- Pushes hardware limits of PMOD AD1 (1 MSPS)
- Demonstrates "Store and Forward" architecture

**Performance**:
- Max Frequency: 500 kHz
- Resolution: 20 Hz bins

---

### P. Warm Boot / Multi-Boot Loader

**Concept**: Store and switch between up to 4 different bitstreams on the 16MB SPI flash without a power cycle.

**Why it fits**:
- Demonstrates advanced iCE40 configuration features
- Teaches `SB_WARMBOOT` primitive
- Allows "BIOS" menu to select between projects (ADC, Logic Analyzer, RISC-V)

---

### Q. FFT Spectrum Analyzer (DSP Capstone)

**Concept**: Transform captured time-domain ADC data into the frequency domain using a Radix-2 Pipelined FFT.

**Why it fits**:
- The "Killer App" for iCE40UP5K's DSP blocks + SPRAM
- Combines memory management, high-speed I/O, and complex math
- Teaches Fixed-Point Complex Arithmetic ($A+Bi$)

---

### R. RISC-V Soft CPU (CAPSTONE)

**Why**: Ultimate learning project, ties everything together.

**Approach**: "From Blinker to RISC-V"
1. Fetch
2. Decode
3. ALU
4. Registers
5. Load/Store
6. Branch
7. Run C Code

**References**:
- Bruno Levy's FemtoRV tutorial (iCEBreaker specific)

---

## Priority Matrix

| Topic | Complexity | Visual Appeal | Builds On | Priority |
|-------|------------|---------------|-----------|----------|
| I2C ADS1115 (Soft) | Medium | Medium | SPI | **A** ✓ |
| Shared Module Library | Low | Low | All | **A.2** |
| Button Debouncing | Low | Low | Blinky | **B** |
| Testbenches | Low | Medium | All | High |
| STM32 Integration | Medium | High | SPI/I2C | High |
| ESP32 OTA | Medium | Very High | SPI | High |
| Digital Filter | High | High | DSP | High |
| Stepper Control | High | Very High | Timing | High |
| DC Servo Loop | High | Very High | PID | High |
| RISC-V CPU | Very High | Very High | All | Capstone |

---