# ADS1115 I2C ADC Reader for iCEBreaker FPGA

A complete I2C master implementation in Verilog that reads analog voltage from a Texas Instruments ADS1115 16-bit ADC and outputs hex values over UART. Designed for learning FPGA development and I2C protocol fundamentals.

## Table of Contents

- [Overview](#overview)
- [Hardware Requirements](#hardware-requirements)
- [Wiring Diagram](#wiring-diagram)
- [Building and Programming](#building-and-programming)
- [Usage](#usage)
- [Output Format](#output-format)
- [Theory of Operation](#theory-of-operation)
- [I2C Protocol Deep Dive](#i2c-protocol-deep-dive)
- [ADS1115 Configuration](#ads1115-configuration)
- [Module Architecture](#module-architecture)
- [State Machine Documentation](#state-machine-documentation)
- [Timing Analysis](#timing-analysis)
- [Error Handling](#error-handling)
- [Troubleshooting](#troubleshooting)
- [Verilog Concepts Demonstrated](#verilog-concepts-demonstrated)
- [File Reference](#file-reference)
- [References](#references)

## Overview

This project demonstrates:
- **I2C Master**: Complete I2C master with START, STOP, byte read/write, ACK/NACK handling
- **Open-Drain Emulation**: Using iCE40 SB_IO primitives for proper I2C signaling
- **UART Transmission**: 115200 baud serial output for debugging and data logging
- **State Machine Design**: Multi-level state machines for protocol sequencing
- **Timeout Detection**: Robust error handling for stuck bus conditions

**Specifications:**
| Parameter | Value |
|-----------|-------|
| FPGA | iCE40 UP5K (iCEBreaker) |
| System Clock | 12 MHz |
| I2C Speed | 400 kHz (Fast Mode) |
| UART Baud | 115200 |
| ADC Resolution | 16-bit |
| Sample Rate | 5 Hz (output rate) |
| ADC Conversion Rate | 860 SPS (internal) |

## Hardware Requirements

### Components

| Component | Description | Notes |
|-----------|-------------|-------|
| iCEBreaker v1.0b/v1.1a | FPGA development board | iCE40 UP5K, SG48 package |
| ADS1115 breakout | 16-bit I2C ADC | Adafruit, SparkFun, or generic |
| Jumper wires | For connections | 4 wires minimum |
| Voltage source | 0-3.3V analog signal | Potentiometer, sensor, etc. |

### ADS1115 Breakout Board Features

Most ADS1115 breakouts include:
- **On-board pull-up resistors** (10k) for SDA and SCL - no external pull-ups needed
- **Voltage regulator** - can be powered from 3.3V or 5V
- **ADDR pin** - for I2C address selection
- **ALRT pin** - alert/ready output (not used in this project)

## Wiring Diagram

```
                    iCEBreaker FPGA                      ADS1115 Breakout
                   ┌──────────────────┐                 ┌─────────────────┐
                   │                  │                 │                 │
    USB ───────────┤ FTDI        PMOD1A├─── Pin 45 ────┤ SCL             │
    (Serial)       │             (top) │                │                 │
                   │                   ├─── Pin 47 ────┤ SDA             │
                   │                   │                │                 │
                   │              Pin 2├───────────────┤ ADDR            │
                   │                   │                │                 │
                   │   BTN ○──── Pin 20│                │ A0 ◄─── Analog Input
                   │  (directly wired  │                │        (0-3.3V)
                   │   to ADDR)        │                │                 │
                   │                   │     3.3V ─────┤ VDD             │
                   │              3.3V ├───────────────┤                 │
                   │               GND ├───────────────┤ GND             │
                   │                   │                │                 │
                   └──────────────────┘                └─────────────────┘

PMOD1A Pinout (directly plug in jumpers):
    ┌─────────────────────────┐
    │  GND  GND  47  45  43  4│  (active pins: 45=SCL, 47=SDA)
    │  3V3  3V3  48  46  44  2│  (active pins: 2=ADDR)
    └─────────────────────────┘
```

### Pin Assignments

| Signal   | FPGA Pin | Direction | Description |
|----------|----------|-----------|-------------|
| clk      | 35       | Input     | 12 MHz system clock (on-board oscillator) |
| tx       | 9        | Output    | UART TX to FTDI chip (USB serial) |
| scl      | 45       | Bidir     | I2C clock line (PMOD1A) |
| sda      | 47       | Bidir     | I2C data line (PMOD1A) |
| btn_n    | 20       | Input     | iCEBreaker user button (directly drives ADDR) |
| addr_out | 2        | Output    | Connected to ADS1115 ADDR pin |

### I2C Address Selection

The iCEBreaker button directly controls the ADS1115 I2C address via the ADDR pin:

| Button State | ADDR Pin | I2C Address | Write Byte | Read Byte |
|--------------|----------|-------------|------------|-----------|
| Released     | GND      | 0x48        | 0x90       | 0x91      |
| Pressed      | VDD      | 0x49        | 0x92       | 0x93      |

This allows verifying I2C communication by pressing the button and observing NACK errors (the code uses address 0x48).

## Building and Programming

### Prerequisites

Install the open-source iCE40 toolchain:

```bash
# Ubuntu/Debian
sudo apt install fpga-icestorm yosys nextpnr-ice40

# Or build from source - see:
# https://github.com/YosysHQ/oss-cad-suite-build
```

### Build Process

```bash
# Clone/navigate to project
cd fpga/src/adc-read-i2c

# Synthesize and generate bitstream
make

# Program the iCEBreaker (connect via USB first)
make prog

# Clean build artifacts
make clean
```

### Build Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Verilog   │    │    JSON     │    │     ASC     │    │     BIN     │
│   Sources   │───►│   Netlist   │───►│  Bitstream  │───►│   Binary    │
│  (.v files) │    │             │    │  (ASCII)    │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
      │                  │                  │                  │
      │     yosys        │    nextpnr       │    icepack       │
      │   synth_ice40    │    --up5k        │                  │
      └──────────────────┴──────────────────┴──────────────────┘
                                                               │
                                                               ▼
                                                          ┌─────────┐
                                                          │ iceprog │
                                                          │ (flash) │
                                                          └─────────┘
```

### Resource Utilization

After synthesis (approximate):
- Logic Cells: ~800 / 5280 (15%)
- Registers: ~150
- Max Frequency: ~45 MHz (3.7x margin over 12 MHz requirement)

## Usage

### Quick Start

1. Wire the ADS1115 breakout to PMOD1A as shown in wiring diagram
2. Connect analog voltage (0-3.3V) to ADS1115 A0 input
3. Connect iCEBreaker to computer via USB
4. Program: `make prog`
5. Open serial terminal at 115200 baud

### Serial Terminal

```bash
# Linux - find the correct port (usually ttyUSB1 for FPGA UART)
ls /dev/ttyUSB*

# Using screen
screen /dev/ttyUSB1 115200

# Using picocom
picocom -b 115200 /dev/ttyUSB1

# Using minicom
minicom -D /dev/ttyUSB1 -b 115200

# Exit screen: Ctrl-A then K then Y
# Exit picocom: Ctrl-A then Ctrl-X
```

### macOS

```bash
ls /dev/tty.usbserial*
screen /dev/tty.usbserial-* 115200
```

### Windows

Use PuTTY or similar terminal emulator:
- Connection type: Serial
- Serial line: COM3 (check Device Manager)
- Speed: 115200

## Output Format

### Startup Message

```
ads1115
```

Sent once on power-up/reset to identify the project.

### Normal Operation

```
0x3AF2
0x3AF1
0x3AF5
0x3AF0
0x3AF3
```

Hex values output 5 times per second (every 200ms). Each line shows the 16-bit ADC reading.

### Error Output

```
E
```

Output when communication fails (NACK from device or bus timeout). The system retries after 200ms.

### Complete Session Example

```
ads1115
0x0000
0x0003
0x1F42
0x3E81
0x5DC0
0x6720
0x6721
E
0x6720
```

This shows: startup, voltage sweep from 0V to 3.3V, a brief communication error, then recovery.

## Theory of Operation

### System Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                            top.v                                      │
│  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐     │
│  │   i2c_master   │    │  Main State    │    │    uart_tx     │     │
│  │                │◄──►│   Machine      │───►│                │     │
│  │  - START/STOP  │    │                │    │  - 115200 baud │     │
│  │  - Read/Write  │    │  - Sequencing  │    │  - 8N1 format  │     │
│  │  - ACK/NACK    │    │  - Formatting  │    │                │     │
│  │  - Timeout     │    │  - Timing      │    │                │     │
│  └───────┬────────┘    └────────────────┘    └───────┬────────┘     │
│          │                                           │               │
│          ▼                                           ▼               │
│     ┌─────────┐                                 ┌─────────┐         │
│     │  SB_IO  │                                 │   TX    │         │
│     │(tristate│                                 │  (9)    │         │
│     └────┬────┘                                 └────┬────┘         │
└──────────┼───────────────────────────────────────────┼───────────────┘
           │                                           │
           ▼                                           ▼
      ┌─────────┐                                 ┌─────────┐
      │SCL (45) │                                 │  FTDI   │
      │SDA (47) │                                 │  Chip   │
      └────┬────┘                                 └────┬────┘
           │                                           │
           ▼                                           ▼
      ┌─────────┐                                 ┌─────────┐
      │ ADS1115 │                                 │   USB   │
      │   ADC   │                                 │ Serial  │
      └─────────┘                                 └─────────┘
```

### Operation Sequence

1. **Power-up**: Send "ads1115\r\n" over UART
2. **Configure ADC**: Write 0xC2E3 to config register (continuous mode, 860 SPS)
3. **Set Pointer**: Point to conversion register (0x00)
4. **Read Loop**: Every 200ms:
   - Read 2 bytes from conversion register
   - Convert to hex ASCII
   - Send "0xNNNN\r\n" over UART
5. **Error Handling**: On NACK or timeout, send "E\r\n" and retry

## I2C Protocol Deep Dive

### Bus Characteristics

I2C (Inter-Integrated Circuit) is a two-wire serial protocol:

| Line | Function | Idle State | Drive Method |
|------|----------|------------|--------------|
| SCL  | Clock    | HIGH       | Open-drain   |
| SDA  | Data     | HIGH       | Open-drain   |

**Open-Drain Signaling:**
- To output LOW: Actively pull line to ground
- To output HIGH: Release line (external pull-up brings it HIGH)
- Multiple devices can share the bus
- Enables clock stretching (slave can hold SCL LOW)

### START and STOP Conditions

```
START Condition:                    STOP Condition:
SDA falls while SCL is HIGH         SDA rises while SCL is HIGH

     SCL ─────────┐                      SCL      ┌─────────
                  └──────                    ─────┘
     SDA ────┐                           SDA           ┌────
             └───────────                    ──────────┘
         ▲                                         ▲
         │                                         │
       START                                     STOP
```

### Byte Transmission

```
        B7   B6   B5   B4   B3   B2   B1   B0   ACK
        ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌───
SCL      └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘
        ───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───
SDA        │ D7│ D6│ D5│ D4│ D3│ D2│ D1│ D0│ACK│
        ───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───
              MSB first                    │
                                           └── 0=ACK, 1=NACK
```

- Data sampled on SCL rising edge
- Data changed on SCL falling edge
- MSB transmitted first
- 9th bit is ACK/NACK from receiver

### ACK vs NACK

| Response | SDA Level | Meaning |
|----------|-----------|---------|
| ACK      | LOW       | Receiver acknowledges, ready for more |
| NACK     | HIGH      | No acknowledgment (error or end of read) |

### I2C Address Format

```
7-bit address + R/W bit:
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ A6│ A5│ A4│ A3│ A2│ A1│ A0│R/W│
└───┴───┴───┴───┴───┴───┴───┴───┘
                              │
                              └── 0=Write, 1=Read

ADS1115 at address 0x48:
  Write: 0x48 << 1 | 0 = 0x90
  Read:  0x48 << 1 | 1 = 0x91
```

## ADS1115 Configuration

### Register Map

| Pointer | Register    | Access | Description |
|---------|-------------|--------|-------------|
| 0x00    | Conversion  | R      | 16-bit ADC result |
| 0x01    | Config      | R/W    | Configuration settings |
| 0x02    | Lo_thresh   | R/W    | Low threshold for comparator |
| 0x03    | Hi_thresh   | R/W    | High threshold for comparator |

### Configuration Register (0xC2E3)

```
Bit:  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
      ┌───┬───────────┬───────────┬───┬───────────┬───┬───┬───┬─────┐
      │OS │    MUX    │    PGA    │MOD│    DR     │CMP│CPO│CLA│CQUE │
      │ 1 │   1 0 0   │   0 0 1   │ 0 │  1 1 1    │ 0 │ 0 │ 0 │ 1 1 │
      └───┴───────────┴───────────┴───┴───────────┴───┴───┴───┴─────┘
       │       │           │       │       │       │   │   │    │
       │       │           │       │       │       │   │   │    └─ COMP_QUE: 11 = Disable
       │       │           │       │       │       │   │   └────── COMP_LAT: 0 = Non-latching
       │       │           │       │       │       │   └────────── COMP_POL: 0 = Active low
       │       │           │       │       │       └────────────── COMP_MODE: 0 = Traditional
       │       │           │       │       └────────────────────── DR: 111 = 860 SPS
       │       │           │       └────────────────────────────── MODE: 0 = Continuous
       │       │           └────────────────────────────────────── PGA: 001 = ±4.096V
       │       └────────────────────────────────────────────────── MUX: 100 = AIN0 vs GND
       └────────────────────────────────────────────────────────── OS: 1 = Start conversion

Hex: 0xC2E3 = 1100 0010 1110 0011
```

### Configuration Field Details

| Field | Bits | Value | Setting |
|-------|------|-------|---------|
| OS | 15 | 1 | Start single conversion (in continuous mode, starts immediately) |
| MUX | 14:12 | 100 | AIN0 single-ended (measure A0 vs GND) |
| PGA | 11:9 | 001 | ±4.096V full-scale range |
| MODE | 8 | 0 | Continuous conversion mode |
| DR | 7:5 | 111 | 860 samples per second |
| COMP_MODE | 4 | 0 | Traditional comparator |
| COMP_POL | 3 | 0 | Active low alert |
| COMP_LAT | 2 | 0 | Non-latching |
| COMP_QUE | 1:0 | 11 | Disable comparator |

### Voltage Calculation

With PGA = ±4.096V:
- Full-scale range: -4.096V to +4.095875V
- LSB size: 4.096V / 32768 = **125 µV**
- Single-ended readings are always positive (0x0000 to 0x7FFF)

**Conversion formula:**
```
Voltage = ADC_Value × 0.000125 V
ADC_Value = Voltage / 0.000125
```

**Reference table:**

| Input Voltage | ADC Value (Hex) | ADC Value (Dec) |
|---------------|-----------------|-----------------|
| 0.000 V       | 0x0000          | 0               |
| 0.500 V       | 0x0FA0          | 4000            |
| 1.000 V       | 0x1F40          | 8000            |
| 1.500 V       | 0x2EE0          | 12000           |
| 1.650 V       | 0x3390          | 13200           |
| 2.000 V       | 0x3E80          | 16000           |
| 2.500 V       | 0x4E20          | 20000           |
| 3.000 V       | 0x5DC0          | 24000           |
| 3.300 V       | 0x6720          | 26400           |

## Module Architecture

### top.v - Main Controller

**Responsibilities:**
- Startup message transmission
- I2C sequence orchestration
- 200ms timing for sample rate
- Hex-to-ASCII conversion
- Error handling and retry logic

**Key Interfaces:**
```verilog
module top (
    input  wire clk,        // 12 MHz system clock
    output wire tx,         // UART transmit
    inout  wire scl,        // I2C clock
    inout  wire sda,        // I2C data
    input  wire btn_n,      // Button input
    output wire addr_out    // ADS1115 ADDR control
);
```

### i2c_master.v - I2C Engine

**Responsibilities:**
- Generate START/STOP conditions
- Transmit bytes with ACK detection
- Receive bytes with ACK/NACK generation
- Timeout detection for stuck bus

**Command Interface:**
```verilog
// Commands (directly from code)
localparam CMD_IDLE  = 3'b000;  // Do nothing
localparam CMD_START = 3'b001;  // Generate START condition
localparam CMD_WRITE = 3'b010;  // Transmit byte, check ACK
localparam CMD_READ  = 3'b011;  // Receive byte, send ACK/NACK
localparam CMD_STOP  = 3'b100;  // Generate STOP condition
```

**Usage Pattern:**
```
1. Set cmd and tx_data (for writes)
2. Pulse cmd_start HIGH for one clock
3. Wait for busy to go LOW (i2c_done)
4. Check ack_error and timeout flags
5. For reads, capture rx_data
```

### uart_tx.v - Serial Transmitter

**Responsibilities:**
- 115200 baud transmission
- 8N1 frame format (8 data, no parity, 1 stop)
- Busy flag for flow control

**Timing:**
- Clocks per bit: 12 MHz / 115200 = 104 clocks
- Frame duration: 10 bits × 104 clocks = 1040 clocks = 86.7 µs

## State Machine Documentation

### Main State Machine (top.v)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         STARTUP                                      │
│  ┌──────────────┐    ┌──────────────┐                               │
│  │STARTUP_SEND  │───►│STARTUP_WAIT  │──┐                            │
│  └──────────────┘    └──────────────┘  │ (11 chars sent)            │
│                                         ▼                            │
├─────────────────────────────────────────────────────────────────────┤
│                    CONFIGURE ADC                                     │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐         │
│  │CFG_START │──►│CFG_ADDR  │──►│CFG_PTR   │──►│CFG_HI    │──►       │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘          │
│       ┌──────────┐   ┌──────────┐                                   │
│   ───►│CFG_LO    │──►│CFG_STOP  │──┐                                │
│       └──────────┘   └──────────┘  │                                │
│                                     ▼                                │
├─────────────────────────────────────────────────────────────────────┤
│                    SET POINTER                                       │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐         │
│  │PTR_START │──►│PTR_ADDR  │──►│PTR_REG   │──►│PTR_STOP  │──┐      │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘  │      │
│                                                              ▼      │
├─────────────────────────────────────────────────────────────────────┤
│                    READ LOOP                                         │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐         │
│  │RD_START  │──►│RD_ADDR   │──►│RD_MSB    │──►│RD_LSB    │──►      │
│  └──────────┘   └──────────┘   └──────────┘   └──────────┘          │
│       ┌──────────┐   ┌──────────┐   ┌──────────┐                    │
│   ───►│RD_STOP   │──►│HEX_SEND  │──►│HEX_WAIT  │──┐                 │
│       └──────────┘   └──────────┘   └──────────┘  │                 │
│                                                    ▼                 │
│                                              ┌──────────┐            │
│                              ┌───────────────│  IDLE    │◄───┐      │
│                              │ (200ms timer) └──────────┘    │      │
│                              │                    │          │      │
│                              ▼                    │(error)   │      │
│                         ┌──────────┐              ▼          │      │
│                         │PTR_START │        ┌──────────┐     │      │
│                         └──────────┘        │ERR_SEND  │─────┘      │
│                                             └──────────┘            │
└─────────────────────────────────────────────────────────────────────┘
```

### I2C State Machine (i2c_master.v)

```
                              ┌──────────┐
                              │   IDLE   │◄────────────────────┐
                              └────┬─────┘                     │
                                   │ cmd_start                 │
              ┌────────────────────┼────────────────────┐      │
              │                    │                    │      │
              ▼                    ▼                    ▼      │
        ┌───────────┐        ┌───────────┐        ┌─────────┐ │
        │  START_1  │        │ WRITE_BIT │        │READ_BIT │ │
        │  (SDA↓)   │        │ (set SDA) │        │(release)│ │
        └─────┬─────┘        └─────┬─────┘        └────┬────┘ │
              │                    │                   │      │
              ▼                    ▼                   ▼      │
        ┌───────────┐        ┌───────────┐        ┌─────────┐ │
        │  START_2  │        │WRITE_HIGH │        │READ_HIGH│ │
        │  (SCL↓)   │        │ (SCL↑)    │        │(sample) │ │
        └─────┬─────┘        └─────┬─────┘        └────┬────┘ │
              │                    │                   │      │
              │                    ▼                   ▼      │
              │              ┌───────────┐        ┌─────────┐ │
              │              │WRITE_LOW  │        │READ_LOW │ │
              │              │ (SCL↓)    │        │(SCL↓)   │ │
              │              └─────┬─────┘        └────┬────┘ │
              │                    │                   │      │
              │         (8 bits)   │        (8 bits)   │      │
              │                    ▼                   ▼      │
              │              ┌───────────┐        ┌─────────┐ │
              │              │ACK_SETUP  │        │ACK_SETUP│ │
              │              │(release)  │        │(set ACK)│ │
              │              └─────┬─────┘        └────┬────┘ │
              │                    │                   │      │
              │                    ▼                   ▼      │
              │              ┌───────────┐        ┌─────────┐ │
              │              │ ACK_HIGH  │        │ACK_HIGH │ │
              │              │ (sample)  │        │(SCL↑)   │ │
              │              └─────┬─────┘        └────┬────┘ │
              │                    │                   │      │
              │                    ▼                   ▼      │
              │              ┌───────────┐        ┌─────────┐ │
              │              │ ACK_LOW   │───────►│ACK_LOW  │─┤
              │              └───────────┘        └─────────┘ │
              │                                               │
              ▼                    ┌───────────┐              │
        ┌───────────┐              │  STOP_1   │◄─────────────┤
        │   done    │──────────────│  (SDA↓)   │              │
        └───────────┘              └─────┬─────┘              │
                                         │                    │
                                         ▼                    │
                                   ┌───────────┐              │
                                   │  STOP_2   │              │
                                   │  (SCL↑)   │              │
                                   └─────┬─────┘              │
                                         │                    │
                                         ▼                    │
                                   ┌───────────┐              │
                                   │  STOP_3   │──────────────┘
                                   │  (SDA↑)   │
                                   └───────────┘
```

## Timing Analysis

### I2C Timing (400 kHz Fast Mode)

| Parameter | Spec Min | Implementation | Margin |
|-----------|----------|----------------|--------|
| SCL clock | 2.5 µs   | 2.5 µs (30 clocks) | Exact |
| SCL LOW   | 1.3 µs   | 1.25 µs (15 clocks) | OK |
| SCL HIGH  | 0.6 µs   | 1.25 µs (15 clocks) | 2x |
| Data setup| 100 ns   | 583 ns (7 clocks) | 5.8x |
| Start hold| 0.6 µs   | 1.25 µs | 2x |
| Stop setup| 0.6 µs   | 1.25 µs | 2x |

### UART Timing (115200 baud)

| Parameter | Calculated | Actual | Error |
|-----------|------------|--------|-------|
| Bit period| 8.68 µs    | 8.67 µs (104 clocks) | 0.16% |
| Baud rate | 115200     | 115385 | 0.16% |

UART tolerance is typically ±2%, so 0.16% error is well within spec.

### Sample Rate Timing

| Parameter | Value |
|-----------|-------|
| Output rate | 5 Hz (200 ms) |
| ADC conversion | 860 SPS (1.16 ms) |
| I2C read time | ~100 µs |
| UART output | ~700 µs (8 chars) |
| Idle time | ~199 ms |

## Error Handling

### NACK Detection

When the ADS1115 doesn't acknowledge:

1. `ack_error` flag is set by i2c_master
2. `got_nack` flag is set in main state machine
3. Current transaction completes (STOP sent)
4. "E\r\n" output over UART
5. System waits 200ms then retries from pointer set

**Common NACK causes:**
- Wrong I2C address (button pressed)
- Device not connected
- Bus contention
- Power supply issues

### Timeout Detection

If any I2C operation takes longer than 1ms:

1. `timeout` flag is set by i2c_master
2. Bus lines released (SCL and SDA HIGH)
3. State machine returns to IDLE
4. Treated same as NACK (outputs "E\r\n")

**Timeout causes:**
- Slave holding SCL LOW (clock stretching stuck)
- Bus shorted to ground
- Severe electrical noise

### Recovery Sequence

```
Error detected → STOP condition → "E\r\n" → 200ms delay → Retry
```

The retry starts from setting the pointer register, not full reconfiguration.

## Troubleshooting

### No Output on Serial Terminal

1. **Check serial port**: `ls /dev/ttyUSB*` - use ttyUSB1 (not ttyUSB0)
2. **Check baud rate**: Must be exactly 115200
3. **Check FPGA programmed**: LED should flash briefly during `make prog`
4. **Try different terminal**: screen, picocom, or minicom

### Continuous "E" Errors

1. **Check wiring**: Verify SCL, SDA, VDD, GND connections
2. **Check address**: Release button (ADDR should be GND for 0x48)
3. **Check pull-ups**: Most breakouts have them; add 4.7k if not
4. **Check power**: ADS1115 needs 3.3V

### Wrong/Stuck Values

1. **Check analog input**: Verify voltage on A0 pin
2. **Check ground**: Common ground between FPGA and ADS1115
3. **Check for shorts**: A0 shouldn't be shorted to VDD or GND

### Button Test

Press the iCEBreaker button while running:
- **Normal (released)**: Hex values output
- **Pressed**: "E" errors (address mismatch expected)

If both states show errors, check wiring. If both show values, check ADDR connection.

### I2C Bus Analyzer

For deep debugging, use a logic analyzer on SCL/SDA:
- Verify START/STOP conditions
- Check byte values and ACK bits
- Measure timing

## Verilog Concepts Demonstrated

### 1. SB_IO Primitive for Tristate

```verilog
// Open-drain emulation using tristate
SB_IO #(
    .PIN_TYPE(6'b1010_01)  // Tristate output + simple input
) scl_io (
    .PACKAGE_PIN(scl),
    .OUTPUT_ENABLE(scl_oe),  // 1=drive LOW, 0=release
    .D_OUT_0(1'b0),          // Always drive 0 when enabled
    .D_IN_0(scl_in)          // Read actual pin state
);
```

### 2. Edge Detection

```verilog
// Detect falling edge of busy signal
reg i2c_busy_prev;
wire i2c_done = i2c_busy_prev & ~i2c_busy;

always @(posedge clk) begin
    i2c_busy_prev <= i2c_busy;
end
```

### 3. State Machine with CMD/WAIT Pattern

```verilog
// Issue command
STATE_CFG_ADDR_CMD: begin
    i2c_cmd <= CMD_WRITE;
    i2c_tx_data <= I2C_ADDR_WRITE;
    i2c_cmd_start <= 1'b1;
    state <= STATE_CFG_ADDR_WAIT;
end

// Wait for completion
STATE_CFG_ADDR_WAIT: begin
    if (i2c_done) begin
        if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
        state <= STATE_CFG_PTR_CMD;
    end
end
```

### 4. Function for Combinational Logic

```verilog
// Convert 4-bit value to ASCII hex character
function [7:0] nibble_to_hex;
    input [3:0] nibble;
    begin
        if (nibble < 10)
            nibble_to_hex = 8'h30 + nibble;  // '0'-'9'
        else
            nibble_to_hex = 8'h41 + (nibble - 10);  // 'A'-'F'
    end
endfunction
```

### 5. Initial Blocks for Simulation/Synthesis

```verilog
// Initialize memory contents
initial begin
    startup_msg[0] = 8'h0D;  // \r
    startup_msg[1] = 8'h0A;  // \n
    startup_msg[2] = "a";
    // ...
end
```

### 6. Parameterized Timing

```verilog
localparam CLOCKS_PER_BIT = 104;    // 12 MHz / 115200 baud
localparam HALF_PERIOD = 15;        // I2C half-period
localparam TIMEOUT_CLOCKS = 12000;  // 1ms timeout
```

## File Reference

| File | Lines | Description |
|------|-------|-------------|
| `top.v` | ~630 | Main module: state machine, I2C sequencing, hex formatting |
| `i2c_master.v` | ~530 | I2C engine: START/STOP, read/write, ACK/NACK, timeout |
| `uart_tx.v` | ~160 | UART transmitter: 115200 baud, 8N1 |
| `icebreaker.pcf` | ~46 | Pin constraints for iCEBreaker |
| `Makefile` | ~48 | Build automation |
| `PLAN.md` | ~488 | Implementation plan and protocol reference |

## References

### Datasheets

- [ADS1115 Datasheet](https://www.ti.com/lit/ds/symlink/ads1115.pdf) - Texas Instruments
- [iCE40 UltraPlus Family Data Sheet](https://www.latticesemi.com/view_document?document_id=51968) - Lattice Semiconductor

### I2C Specification

- [I2C-bus specification and user manual](https://www.nxp.com/docs/en/user-guide/UM10204.pdf) - NXP (original Philips spec)

### iCEBreaker Resources

- [iCEBreaker FPGA](https://github.com/icebreaker-fpga/icebreaker) - Hardware documentation
- [iCEBreaker Verilog Examples](https://github.com/icebreaker-fpga/icebreaker-verilog-examples) - Reference code

### Tools

- [Yosys](https://github.com/YosysHQ/yosys) - Synthesis
- [nextpnr](https://github.com/YosysHQ/nextpnr) - Place and route
- [Project IceStorm](https://github.com/YosysHQ/icestorm) - Bitstream tools

## License

Public domain / educational use.
