# FPGA Video Series - Future Topics

A roadmap for additional agentic Verilog tutorials, organized by priority and complexity.

**Target Hardware**: iCEBreaker v1.0b/v1.1a with Lattice iCE40 UP5K
- Note: Unlike boards like the Nandland Go Board, iCEBreaker does NOT have built-in 7-segment displays or multiple user buttons. It has minimal onboard I/O (1 button, 2 LEDs) - most I/O comes via PMODs.

---

## Future Projects (A-Z)

### A. I2C for ADS1115 Breakout Board (Soft Implementation)

**Concept**: Implement I2C master in pure Verilog to read from the 16-bit ADS1115 ADC

**Why it fits**:
- Natural progression from SPI (DAC-Ramp, ADC-Read) to I2C
- Builds on familiar concepts: state machines, shift registers, timing
- I2C is more complex: bidirectional SDA, ACK/NACK, addressing
- ADS1115 offers 16-bit resolution vs AD7476A's 12-bit
- **Soft implementation teaches the protocol deeply** (no black-box primitives)

**Why soft implementation (not hard IP)**:
- Educational: understand every bit of the protocol
- Portable: works on any FPGA, not just iCE40
- Flexible: can modify timing, add features
- Pins: not restricted to hard IP pin locations
- Foundation: prepares viewers for the comparison video later

**New concepts introduced**:
- I2C protocol fundamentals:
  - START condition (SDA falls while SCL high)
  - STOP condition (SDA rises while SCL high)
  - ACK/NACK (9th clock pulse acknowledgment)
  - 7-bit addressing + R/W bit
- Bidirectional signals (`inout` ports)
- Tristate buffers (SB_IO primitive for open-drain)
- Open-drain with external pullups
- Multi-byte transactions with register addressing
- Clock stretching detection (slave holds SCL low)

**Hardware needed**:
- ADS1115 breakout board (Adafruit or generic, ~$3-10)
- 4.7k pullup resistors (usually on breakout already)
- Analog signal source (potentiometer, or just read Vdd/GND)
- Jumper wires

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
| I2C ADS1115 (Soft) | Medium | Medium | SPI | **A** |
| Button Debouncing | Low | Low | Blinky | **B** |
| Testbenches | Low | Medium | All | High |
| STM32 Integration | Medium | High | SPI/I2C | High |
| ESP32 OTA | Medium | Very High | SPI | High |
| Digital Filter | High | High | DSP | High |
| Stepper Control | High | Very High | Timing | High |
| DC Servo Loop | High | Very High | PID | High |
| RISC-V CPU | Very High | Very High | All | Capstone |

---