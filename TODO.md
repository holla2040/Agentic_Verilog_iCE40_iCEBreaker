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

**Priority**: Create before starting new projects.

---

#### Architecture: Two-Tier Module Library

The library uses a two-tier architecture:

1. **Protocol-level modules** - Universal implementations of communication protocols
2. **Device-level modules** - Wrappers for specific ICs that encapsulate device quirks

```
src/lib/
├── README.md                # Library documentation
│
├── # Protocol-level modules (universal)
├── uart_tx.v                # UART transmitter (8N1)
├── uart_rx.v                # UART receiver (8N1)
├── i2c_master.v             # I2C master (START/STOP/READ/WRITE primitives)
├── spi_master.v             # SPI master (all 4 modes via CPOL/CPHA)
│
├── # Device-level modules (part-specific wrappers)
├── ads1115.v                # 16-bit I2C ADC (wraps i2c_master)
├── ad7476a.v                # 12-bit SPI ADC (wraps spi_master)
└── dac121s101.v             # 12-bit SPI DAC (wraps spi_master)
```

**Rationale for device modules**: SPI timing varies significantly between devices. The `dac-adc-loopback` project revealed that combining AD7476A (ADC) and DAC121S101 (DAC) required extensive debugging due to incompatible SPI timing. Device-specific wrappers encapsulate these quirks and provide clean "read_value" / "write_value" interfaces.

---

#### Interface Conventions

All library modules follow these conventions:

| Convention | Description |
|------------|-------------|
| `_i` suffix | Input ports |
| `_o` suffix | Output ports |
| `_io` suffix | Bidirectional (inout) ports |
| `clk_i` | System clock input |
| `rst_i` | Synchronous reset, **active HIGH** |
| `ready_o` | HIGH when module is idle and ready to accept commands |
| `start_i` | Single-clock pulse to begin operation |
| `valid_o` | Single-clock pulse indicating data is available |

**Why `ready_o` instead of `busy_o`**: Industry standard (AXI-Stream uses TREADY/TVALID). Positive logic reads more naturally: `if (uart_ready && data_valid)` vs `if (!uart_busy && data_valid)`.

---

#### Source Files Reference

| Library Module | Source Reference | Notes |
|----------------|------------------|-------|
| `uart_tx.v` | `src/adc-read-i2c-reset-logic/uart_tx.v` | Has reset support, rename ports, invert busy→ready |
| `uart_rx.v` | `src/uart-rx/uart_rx.v` | Demo module - extract RX logic, remove LED, add data_o/valid_o |
| `i2c_master.v` | `src/adc-read-i2c-reset-logic/i2c_master.v` | Has reset support, rename ports, invert busy→ready |
| `spi_master.v` | **Create new** | Do NOT use dac-adc-loopback SPI code (has timing bugs) |
| `ads1115.v` | Reference `src/adc-read-i2c/top.v` | Extract ADS1115 transaction sequence |
| `ad7476a.v` | **Create new** | Wrap spi_master with correct framing |
| `dac121s101.v` | **Create new** | Wrap spi_master with correct framing |

**WARNING**: Do NOT use SPI code from `dac-adc-loopback/spi_adc.v` as a reference. It contains a timing bug where the first bit is missed and compensated with a `[12:1]` bit extraction hack. The new `spi_master.v` must handle this correctly.

---

#### Module Interface Specifications

##### uart_tx.v
```verilog
module uart_tx #(
    parameter CLOCKS_PER_BIT = 104   // 115200 baud @ 12MHz
) (
    input  wire       clk_i,
    input  wire       rst_i,         // Synchronous reset (active HIGH)
    input  wire [7:0] data_i,        // Byte to transmit
    input  wire       start_i,       // Pulse to begin transmission
    output wire       ready_o,       // HIGH when idle/ready
    output reg        tx_o           // UART TX line (directly to pin)
);
```

##### uart_rx.v
```verilog
module uart_rx #(
    parameter CLOCKS_PER_BIT = 104   // 115200 baud @ 12MHz
) (
    input  wire       clk_i,
    input  wire       rst_i,         // Synchronous reset (active HIGH)
    input  wire       rx_i,          // UART RX line (directly from pin)
    output reg  [7:0] data_o,        // Received byte
    output reg        valid_o        // Pulses HIGH for one clock when byte received
);
```
Implementation notes:
- Include 2-FF synchronizer for rx_i (metastability protection)
- Sample at mid-bit (CLOCKS_PER_BIT / 2)
- Extract from `src/uart-rx/uart_rx.v`, remove LED logic, add data_o/valid_o interface

##### i2c_master.v
```verilog
module i2c_master #(
    parameter HALF_PERIOD = 60       // 100 kHz @ 12MHz
) (
    input  wire       clk_i,
    input  wire       rst_i,         // Synchronous reset (active HIGH)

    // I2C bus (directly to package pins)
    inout  wire       scl_io,        // I2C clock (open-drain via SB_IO)
    inout  wire       sda_io,        // I2C data (open-drain via SB_IO)

    // Command interface
    input  wire [2:0] cmd_i,         // CMD_START/STOP/READ/WRITE
    input  wire [7:0] data_i,        // Byte to write
    input  wire       ack_i,         // ACK to send on read (0=ACK, 1=NACK)
    input  wire       start_i,       // Pulse to execute command

    // Response interface
    output reg  [7:0] data_o,        // Byte read
    output reg        ack_o,         // ACK received (0=ACK, 1=NACK)
    output wire       ready_o        // HIGH when idle/ready
);

// Command constants
localparam CMD_NONE  = 3'd0;
localparam CMD_START = 3'd1;
localparam CMD_STOP  = 3'd2;
localparam CMD_WRITE = 3'd3;
localparam CMD_READ  = 3'd4;
```
Implementation notes:
- Uses SB_IO primitives for open-drain (Lattice iCE40 specific - acceptable)
- Keep existing state machine from source

##### spi_master.v (NEW - do not copy from existing projects)
```verilog
module spi_master #(
    parameter CPOL = 0,              // Clock polarity: 0=idle LOW, 1=idle HIGH
    parameter CPHA = 0,              // Clock phase: 0=sample on 1st edge, 1=sample on 2nd edge
    parameter WIDTH = 8,             // Bits per transfer
    parameter HALF_PERIOD = 6        // SCLK half-period in clk_i cycles
) (
    input  wire             clk_i,
    input  wire             rst_i,

    // Data interface
    input  wire [WIDTH-1:0] data_i,  // MOSI data to send
    input  wire             start_i, // Pulse to begin transfer
    output reg  [WIDTH-1:0] data_o,  // MISO data received
    output wire             ready_o, // HIGH when idle/ready

    // SPI bus
    output reg              sclk_o,  // SPI clock
    output reg              mosi_o,  // Master Out, Slave In
    input  wire             miso_i,  // Master In, Slave Out
    output reg              cs_n_o   // Chip select (directly active LOW directly)
);
```

**Critical: Correct SPI Mode Implementation**

The AD7476A bug in `dac-adc-loopback` occurred because CPHA=0 was implemented incorrectly:

| What happened (BUG) | What should happen (CORRECT) |
|---------------------|------------------------------|
| 1. CS falls | 1. CS falls |
| 2. Create falling SCLK edge | 2. Slave outputs first bit (already present!) |
| 3. Sample on rising edge | 3. Rising SCLK edge → **sample here** |
| 4. Missed first bit! | 4. Falling SCLK edge → slave shifts next bit |

In **CPHA=0**, the slave outputs data when CS falls, BEFORE any clock edge. The master must sample on the FIRST clock edge (rising for CPOL=0), not after creating a falling edge first.

**SPI Mode Truth Table**:
| Mode | CPOL | CPHA | SCLK Idle | Sample Edge | Shift Edge |
|------|------|------|-----------|-------------|------------|
| 0 | 0 | 0 | LOW | Rising | Falling |
| 1 | 0 | 1 | LOW | Falling | Rising |
| 2 | 1 | 0 | HIGH | Falling | Rising |
| 3 | 1 | 1 | HIGH | Rising | Falling |

##### ads1115.v (Device wrapper)
```verilog
module ads1115 #(
    parameter I2C_ADDR = 7'h48,      // Default I2C address (ADDR pin to GND)
    parameter HALF_PERIOD = 60       // I2C timing
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // I2C bus
    inout  wire        scl_io,
    inout  wire        sda_io,

    // User interface
    input  wire [1:0]  channel_i,    // ADC channel (0-3)
    input  wire        start_i,      // Start conversion
    output reg  [15:0] data_o,       // 16-bit ADC result
    output wire        ready_o,      // HIGH when idle
    output reg         valid_o       // Pulses when data_o is valid
);
```
Implementation: Instantiate i2c_master internally, implement config register write + conversion read sequence.

##### ad7476a.v (Device wrapper)
```verilog
module ad7476a #(
    parameter HALF_PERIOD = 6        // SPI timing
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // SPI bus
    output wire        sclk_o,
    input  wire        sdata_i,      // ADC data out (directly MISO directly)
    output wire        cs_n_o,

    // User interface
    input  wire        start_i,      // Start conversion
    output reg  [11:0] data_o,       // 12-bit ADC result
    output wire        ready_o,
    output reg         valid_o
);
```
Implementation: Instantiate spi_master with CPOL=0, CPHA=0, WIDTH=16. Extract bits [13:2] for 12-bit result (2 leading zeros + 12 data bits + 2 trailing bits).

##### dac121s101.v (Device wrapper)
```verilog
module dac121s101 #(
    parameter HALF_PERIOD = 6        // SPI timing
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // SPI bus
    output wire        sclk_o,
    output wire        mosi_o,       // DAC data in
    output wire        cs_n_o,       // directly Called SYNC on DAC directly

    // User interface
    input  wire [11:0] data_i,       // 12-bit value to output
    input  wire        start_i,
    output wire        ready_o
);
```
Implementation: Instantiate spi_master with CPOL=0, CPHA=1, WIDTH=16. Format: `{2'b00, 2'b00, data_i}` (2 don't care + 2 mode bits for normal operation + 12 data).

---

#### Implementation Steps

1. Create `src/lib/` directory
2. Create protocol modules:
   - `uart_tx.v` - adapt from adc-read-i2c-reset-logic
   - `uart_rx.v` - extract from uart-rx demo
   - `i2c_master.v` - adapt from adc-read-i2c-reset-logic
   - `spi_master.v` - create new with correct CPOL/CPHA implementation
3. Create device modules:
   - `ads1115.v` - wrap i2c_master
   - `ad7476a.v` - wrap spi_master
   - `dac121s101.v` - wrap spi_master
4. Create `README.md` with:
   - Interface conventions documentation
   - Module API reference with port tables
   - Makefile integration example: `LIB_DIR = ../lib` and `SRC = top.v $(LIB_DIR)/uart_tx.v`
   - Example instantiations for each module

#### Verification

Three levels of testing, in order of complexity:

---

##### Level 1: Synthesis Check (Minimum - No Hardware)

Verifies Verilog is syntactically correct and synthesizable for iCE40. Catches syntax errors and unsynthesizable constructs but does NOT verify behavior.

```bash
cd src/lib

# Test each module individually
yosys -p "synth_ice40 -top uart_tx" uart_tx.v
yosys -p "synth_ice40 -top uart_rx" uart_rx.v
yosys -p "synth_ice40 -top i2c_master" i2c_master.v
yosys -p "synth_ice40 -top spi_master" spi_master.v

# Device wrappers need their dependencies
yosys -p "synth_ice40 -top ads1115" ads1115.v i2c_master.v
yosys -p "synth_ice40 -top ad7476a" ad7476a.v spi_master.v
yosys -p "synth_ice40 -top dac121s101" dac121s101.v spi_master.v
```

**Pass criteria**: No errors, reasonable cell count (compare to original implementations).

---

##### Level 2: Simulation with Testbenches (Recommended - No Hardware)

Write testbenches using Icarus Verilog to verify correct behavior. This is critical for `spi_master.v` to prove the CPHA=0 fix works.

**Testbench files to create** in `src/lib/tb/`:

| Testbench | Verifies |
|-----------|----------|
| `uart_tx_tb.v` | Start bit, 8 data bits (LSB first), stop bit, timing, ready_o behavior |
| `uart_rx_tb.v` | 2-FF synchronizer, mid-bit sampling, valid_o pulse, data_o correctness |
| `spi_master_tb.v` | All 4 CPOL/CPHA modes, first-bit capture (the bug fix), CS timing |
| `i2c_master_tb.v` | START/STOP conditions, ACK/NACK, byte read/write, open-drain behavior |

**Running testbenches**:
```bash
cd src/lib/tb
iverilog -o uart_tx_tb.vvp uart_tx_tb.v ../uart_tx.v
vvp uart_tx_tb.vvp
gtkwave uart_tx.vcd  # Optional: view waveforms
```

**Testbench specifications**:

###### uart_tx_tb.v
```verilog
// Test cases:
// 1. Reset behavior: tx_o=HIGH, ready_o=HIGH after reset
// 2. Single byte: Send 0x55 (alternating bits), verify timing
// 3. Back-to-back: Send two bytes, verify ready_o transitions
// 4. Timing: Verify each bit is exactly CLOCKS_PER_BIT cycles

// Self-checking: Use $display to show PASS/FAIL for each test
// Generate VCD: $dumpfile("uart_tx.vcd"); $dumpvars(0, uart_tx_tb);
```

###### uart_rx_tb.v
```verilog
// Test cases:
// 1. Reset behavior: valid_o=LOW after reset
// 2. Receive 0x55: Inject serial waveform, verify data_o
// 3. Receive 0xAA: Verify LSB-first reception
// 4. Noise rejection: Glitch during idle should not trigger reception
// 5. valid_o pulse: Must be exactly 1 clock cycle

// Stimulus: Generate rx_i waveform with correct timing
// Use task to send a byte: task send_byte(input [7:0] data);
```

###### spi_master_tb.v (CRITICAL - must verify CPHA=0 fix)
```verilog
// Test cases for EACH of the 4 modes (parameterized testbench):
//
// Mode 0 (CPOL=0, CPHA=0) - THE BUG FIX TEST:
//   1. Simulate slave that outputs data on CS fall (like AD7476A)
//   2. Verify FIRST bit is captured correctly (not missed!)
//   3. Verify sample occurs on RISING edge
//   4. Verify shift occurs on FALLING edge
//
// Mode 1 (CPOL=0, CPHA=1):
//   1. Verify sample on FALLING edge
//   2. Verify shift on RISING edge
//
// Mode 2 (CPOL=1, CPHA=0):
//   1. Verify SCLK idles HIGH
//   2. Verify sample on FALLING edge
//
// Mode 3 (CPOL=1, CPHA=1):
//   1. Verify SCLK idles HIGH
//   2. Verify sample on RISING edge
//
// All modes:
//   - Verify CS_n timing (assert before first clock, deassert after last)
//   - Verify ready_o behavior
//   - Verify data_o contains correct received data
//   - Test different WIDTH values (8, 12, 16)

// Simulated SPI slave model:
module spi_slave_model #(parameter CPOL=0, CPHA=0, WIDTH=8) (
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    input  wire [WIDTH-1:0] tx_data,  // Data slave sends to master
    output reg  [WIDTH-1:0] rx_data   // Data slave receives from master
);
    // Implement slave behavior based on CPOL/CPHA
endmodule
```

###### i2c_master_tb.v
```verilog
// Test cases:
// 1. START condition: SDA falls while SCL HIGH
// 2. STOP condition: SDA rises while SCL HIGH
// 3. Write byte with ACK: Slave pulls SDA LOW on 9th clock
// 4. Write byte with NACK: SDA stays HIGH on 9th clock
// 5. Read byte with ACK: Master pulls SDA LOW on 9th clock
// 6. Read byte with NACK: Master releases SDA on 9th clock
// 7. Full transaction: START + address + data + STOP

// Simulated I2C slave model:
module i2c_slave_model #(parameter ADDR=7'h48) (
    inout wire scl,
    inout wire sda
);
    // Implement slave that responds to address, ACKs, provides read data
endmodule
```

**Pass criteria**:
- All test cases print "PASS"
- No timing violations
- Waveforms match expected behavior when viewed in GTKWave

---

##### Level 3: Hardware Verification (Gold Standard)

Create `src/lib-test/` project that verifies library modules with real hardware.

**Project structure**:
```
src/lib-test/
├── Makefile
├── icebreaker.pcf
├── top.v              # Test harness
└── README.md          # Test procedures
```

**Test configurations** (select via DIP switch or recompile):

###### Test A: UART Loopback
- Connect TX pin to RX pin (external wire jumper)
- Send bytes via USB-UART, verify they echo back
- Tests: `uart_tx.v` + `uart_rx.v`

```verilog
// top.v for UART loopback
uart_rx rx_inst (.clk_i(clk), .rx_i(rx_pin), .data_o(rx_data), .valid_o(rx_valid));
uart_tx tx_inst (.clk_i(clk), .data_i(rx_data), .start_i(rx_valid), .tx_o(tx_pin));
```

**Pass criteria**: Every character typed in terminal echoes back correctly.

###### Test B: I2C ADS1115 Read
- Connect ADS1115 breakout to PMOD connector
- Read ADC value, send via UART
- Compare output to `adc-read-i2c` project
- Tests: `i2c_master.v` + `ads1115.v` + `uart_tx.v`

**Pass criteria**: ADC readings match `adc-read-i2c` output (same voltage = same hex value).

###### Test C: SPI DAC-ADC Loopback
- Connect PMOD DA2 (DAC) output to PMOD AD1 (ADC) input
- Write ramp to DAC, read from ADC, send via UART
- Compare output to `dac-adc-loopback` project
- Tests: `spi_master.v` + `ad7476a.v` + `dac121s101.v` + `uart_tx.v`

**Pass criteria**:
- ADC readings track DAC output (linear relationship)
- No bit-shift errors (the CPHA=0 bug would cause incorrect values)
- Compare to `dac-adc-loopback` output at same DAC values

###### Test D: SPI Mode Verification (if logic analyzer available)
- Capture SPI waveforms with logic analyzer (Saleae, etc.)
- Verify clock polarity and phase match configured mode
- Verify CS timing relative to first/last clock edge

**Pass criteria**: Waveforms match SPI mode specification.

---

#### Concepts Demonstrated

- IP reuse and library management
- Two-tier architecture (protocol vs device abstraction)
- Consistent module interfaces (`_i`/`_o`/`_io` suffixes, `ready_o` convention)
- Parameterization for flexibility
- SPI modes (CPOL/CPHA) and why they matter
- Encapsulating device-specific quirks in wrappers
- Makefile include paths for shared code

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