# iCEBreaker Shared Module Library

Reusable Verilog modules for iCEBreaker FPGA projects with the Lattice iCE40 UP5K.

## Overview

This library provides canonical, well-documented modules for common peripherals. All modules follow consistent interface conventions for easy integration.

## Architecture

The library uses a two-tier architecture:

1. **Protocol-level modules** - Universal implementations of communication protocols
2. **Device-level modules** - Wrappers for specific ICs that encapsulate device quirks

```
src/lib/
├── README.md                # This file
│
├── # Protocol-level modules (universal)
├── uart_tx.v                # UART transmitter (8N1)
├── uart_rx.v                # UART receiver (8N1)
├── i2c_master.v             # I2C master controller
├── spi_master.v             # SPI master (all 4 modes)
│
├── # Device-level modules (part-specific)
├── ads1115.v                # 16-bit I2C ADC
├── ad7476a.v                # 12-bit SPI ADC
└── dac121s101.v             # 12-bit SPI DAC
```

## Interface Conventions

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

## Module Reference

### uart_tx.v - UART Transmitter

Standard 8N1 UART transmitter.

```verilog
module uart_tx #(
    parameter CLOCKS_PER_BIT = 104   // 115200 baud @ 12MHz
) (
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire [7:0] data_i,
    input  wire       start_i,
    output wire       ready_o,
    output reg        tx_o
);
```

**Usage:**
1. Wait for `ready_o == 1`
2. Load `data_i` with byte to send
3. Pulse `start_i` for one clock
4. Wait for `ready_o` to go HIGH again

### uart_rx.v - UART Receiver

Standard 8N1 UART receiver with 2-FF synchronizer.

```verilog
module uart_rx #(
    parameter CLOCKS_PER_BIT = 104
) (
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       rx_i,
    output reg  [7:0] data_o,
    output reg        valid_o
);
```

**Usage:**
1. Connect `rx_i` to UART receive pin
2. When `valid_o` pulses HIGH, read `data_o`

### i2c_master.v - I2C Master Controller

I2C master with command-based interface. Uses SB_IO primitives for open-drain.

```verilog
module i2c_master #(
    parameter HALF_PERIOD = 60       // 100 kHz @ 12MHz
) (
    input  wire       clk_i,
    input  wire       rst_i,
    inout  wire       scl_io,
    inout  wire       sda_io,
    input  wire [2:0] cmd_i,         // CMD_START/STOP/READ/WRITE
    input  wire [7:0] data_i,
    input  wire       ack_i,
    input  wire       start_i,
    output reg  [7:0] data_o,
    output reg        ack_o,
    output wire       ready_o
);
```

**Commands:**
- `CMD_START (1)`: Generate START condition
- `CMD_STOP (2)`: Generate STOP condition
- `CMD_WRITE (3)`: Write byte, check `ack_o` for ACK/NACK
- `CMD_READ (4)`: Read byte into `data_o`, send ACK/NACK via `ack_i`

### spi_master.v - SPI Master Controller

SPI master supporting all 4 modes via CPOL/CPHA parameters.

```verilog
module spi_master #(
    parameter CPOL = 0,              // Clock polarity
    parameter CPHA = 0,              // Clock phase
    parameter WIDTH = 8,             // Bits per transfer
    parameter HALF_PERIOD = 6        // SCLK half-period
) (
    input  wire             clk_i,
    input  wire             rst_i,
    input  wire [WIDTH-1:0] data_i,
    input  wire             start_i,
    output reg  [WIDTH-1:0] data_o,
    output wire             ready_o,
    output reg              sclk_o,
    output reg              mosi_o,
    input  wire             miso_i,
    output reg              cs_n_o
);
```

**SPI Modes:**
| Mode | CPOL | CPHA | Sample Edge |
|------|------|------|-------------|
| 0 | 0 | 0 | Rising |
| 1 | 0 | 1 | Falling |
| 2 | 1 | 0 | Falling |
| 3 | 1 | 1 | Rising |

### ads1115.v - 16-bit I2C ADC

Wrapper for TI ADS1115 ADC. Handles configuration and conversion internally.

```verilog
module ads1115 #(
    parameter I2C_ADDR = 7'h48,
    parameter HALF_PERIOD = 60
) (
    input  wire        clk_i,
    input  wire        rst_i,
    inout  wire        scl_io,
    inout  wire        sda_io,
    input  wire [1:0]  channel_i,    // 0-3 for single-ended
    input  wire        start_i,
    output reg  [15:0] data_o,
    output wire        ready_o,
    output reg         valid_o
);
```

### ad7476a.v - 12-bit SPI ADC

Wrapper for Analog Devices AD7476A ADC.

```verilog
module ad7476a #(
    parameter HALF_PERIOD = 6
) (
    input  wire        clk_i,
    input  wire        rst_i,
    output wire        sclk_o,
    input  wire        sdata_i,
    output wire        cs_n_o,
    input  wire        start_i,
    output reg  [11:0] data_o,
    output wire        ready_o,
    output reg         valid_o
);
```

### dac121s101.v - 12-bit SPI DAC

Wrapper for TI DAC121S101 DAC.

```verilog
module dac121s101 #(
    parameter HALF_PERIOD = 6
) (
    input  wire        clk_i,
    input  wire        rst_i,
    output wire        sclk_o,
    output wire        mosi_o,
    output wire        cs_n_o,
    input  wire [11:0] data_i,
    input  wire        start_i,
    output wire        ready_o
);
```

## Usage in Projects

### Makefile Integration

Reference library modules from your project directory:

```makefile
LIB_DIR = ../lib

SRC = top.v \
      $(LIB_DIR)/uart_tx.v \
      $(LIB_DIR)/uart_rx.v

$(BUILD_DIR)/$(PROJ).json: $(SRC)
	yosys -p "synth_ice40 -top $(TOP) -json $@" $(SRC)
```

### Example: UART Echo

```verilog
module top (
    input  wire clk,
    input  wire uart_rx_pin,
    output wire uart_tx_pin
);

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       tx_ready;

    uart_rx #(.CLOCKS_PER_BIT(104)) rx_inst (
        .clk_i(clk),
        .rst_i(1'b0),
        .rx_i(uart_rx_pin),
        .data_o(rx_data),
        .valid_o(rx_valid)
    );

    uart_tx #(.CLOCKS_PER_BIT(104)) tx_inst (
        .clk_i(clk),
        .rst_i(1'b0),
        .data_i(rx_data),
        .start_i(rx_valid),
        .ready_o(tx_ready),
        .tx_o(uart_tx_pin)
    );

endmodule
```

### Example: Read ADS1115

```verilog
module top (
    input  wire clk,
    inout  wire i2c_scl,
    inout  wire i2c_sda,
    output wire uart_tx_pin
);

    wire [15:0] adc_data;
    wire        adc_valid;
    wire        adc_ready;
    reg         adc_start = 0;

    ads1115 #(.I2C_ADDR(7'h48)) adc_inst (
        .clk_i(clk),
        .rst_i(1'b0),
        .scl_io(i2c_scl),
        .sda_io(i2c_sda),
        .channel_i(2'd0),
        .start_i(adc_start),
        .data_o(adc_data),
        .ready_o(adc_ready),
        .valid_o(adc_valid)
    );

    // Start conversion every 100ms, send result via UART...

endmodule
```

## Target Hardware

- **Board**: iCEBreaker v1.0b/v1.1a
- **FPGA**: Lattice iCE40 UP5K
- **System Clock**: 12 MHz (default parameters assume this)

## Notes

- `i2c_master.v` uses Lattice SB_IO primitives (not portable to other FPGAs)
- Existing projects in `src/` are frozen; this library is for new projects
- See `TODO.md` section A.2 for design rationale and verification procedures
