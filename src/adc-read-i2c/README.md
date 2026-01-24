# ADS1115 I2C ADC Reader

Reads 16-bit ADC values from an ADS1115 over I2C and outputs them via UART.

## Hardware

- **FPGA**: iCEBreaker (iCE40 UP5K)
- **ADC**: ADS1115 16-bit I2C ADC
- **Interface**: I2C @ 100 kHz, UART @ 115200 baud

### Pin Connections

| Signal | Pin | Description |
|--------|-----|-------------|
| CLK | 35 | 12 MHz system clock |
| SCL | 45 | I2C clock (PMOD1A) |
| SDA | 47 | I2C data (PMOD1A) |
| BTN_ADDR | 20 | Button input |
| ADS_ADDR | 2 | ADS1115 ADDR pin |
| UART_TX | 9 | Serial output |

### ADS1115 Wiring

```
iCEBreaker          ADS1115
----------          -------
Pin 45 (SCL) -----> SCL
Pin 47 (SDA) -----> SDA
Pin 2  -----------> ADDR
3.3V -------------> VDD
GND --------------> GND
                    AIN0 <--- Analog input (0-4V)
```

## Operation

1. On startup, sends `ads1115` via UART
2. Configures ADS1115 for continuous conversion:
   - AIN0 single-ended (vs GND)
   - +/-4.096V full scale range
   - 250 samples per second
3. Every 200ms, reads and outputs the 16-bit value as `0xNNNN`

### Sample Output

```
ads1115
0x55BE
0x55C0
0x55BC
...
```

### Voltage Calculation

The ADS1115 returns a 16-bit signed value with +/-4.096V range:

```
Voltage = (raw_value / 32768) × 4.096V
```

| Raw Value | Voltage |
|-----------|---------|
| 0x7FFF | +4.096V (limited to ~3.3V by VDD) |
| 0x55BE | +2.72V |
| 0x4000 | +2.048V |
| 0x0000 | 0V |
| 0x8000 | -4.096V |

## Build

```bash
make        # Synthesize and generate bitstream
make prog   # Program the iCEBreaker
make clean  # Remove build artifacts
```

## Files

| File | Description |
|------|-------------|
| `top.v` | Main module with state machine |
| `i2c_master.v` | I2C controller with SB_IO primitives |
| `uart_tx.v` | UART transmitter (115200 8N1) |
| `icebreaker.pcf` | Pin constraints |
| `Makefile` | Build system |

## Architecture

```
┌──────────────┐     ┌─────────────┐     ┌───────────┐
│ i2c_master.v │<--->│   top.v     │<--->│ uart_tx.v │
│  (SB_IO)     │     │ (app logic) │     │           │
└──────────────┘     └─────────────┘     └───────────┘
       ││                                      │
    SCL/SDA                                 UART_TX
       ││                                      │
  ┌──────────┐                            Terminal
  │ ADS1115  │
  └──────────┘
```

## I2C Protocol

The I2C master uses SB_IO primitives for proper open-drain signaling:

```verilog
SB_IO #(.PIN_TYPE(6'b101001)) sda_io (
    .PACKAGE_PIN(sda),
    .OUTPUT_ENABLE(sda_oe),  // 1=drive LOW, 0=release (pull-up)
    .D_OUT_0(1'b0),
    .D_IN_0(sda_in)
);
```

### I2C Sequences

**Configure ADS1115 (0xC2C3):**
```
START → 0x90 → 0x01 → 0xC2 → 0xC3 → STOP
        addr   reg    config MSB/LSB
```

**Read conversion:**
```
START → 0x91 → [MSB] → [LSB] → STOP
        addr    ACK     NACK
```

## Concepts Demonstrated

- **I2C Master**: Bit-banged I2C with proper open-drain using SB_IO primitives
- **State Machine**: Multi-step I2C transactions with error handling
- **UART Output**: Hex formatting of 16-bit values
- **Timing**: 100 kHz I2C clock derived from 12 MHz system clock
