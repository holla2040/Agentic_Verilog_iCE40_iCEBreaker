# ADC Reader - PMOD AD1 (AD7476A)

Reads analog values from the AD7476A 12-bit ADC and displays them via UART.

## Hardware Setup

- **FPGA Board**: iCEBreaker
- **ADC Module**: PMOD AD1 (Digilent)
- **Connection**: PMOD1B connector
- **Input**: Analog signal on A0 (0V to 3.3V)

## Pin Connections

| PMOD AD1 Pin | Function | iCEBreaker PMOD1B | FPGA Pin |
|--------------|----------|-------------------|----------|
| 1 | CS | Pin 1 | 43 |
| 2 | D0 (SDATA) | Pin 2 | 38 |
| 3 | D1 (unused) | Pin 3 | 34 |
| 4 | CLK (SCLK) | Pin 4 | 31 |
| 5 | GND | GND | - |
| 6 | VCC | 3.3V | - |

## Output Format

The ADC value is sent via UART (115200 baud) 10 times per second:

```
0x0FFF
0x0800
0x0000
```

### Voltage to ADC Value Mapping

| Input Voltage | ADC Value | Hex Output |
|---------------|-----------|------------|
| 0.0V | 0 | 0x000 |
| 1.65V | 2048 | 0x800 |
| 3.3V | 4095 | 0xFFF |

Formula: `ADC_Value = (Vin / 3.3V) * 4095`

## Usage

1. **Build**:
   ```bash
   make
   ```

2. **Program the FPGA**:
   ```bash
   make prog
   ```

3. **Connect serial terminal** (115200 baud):
   ```bash
   screen /dev/ttyUSB1 115200
   ```

4. **Apply analog signal** to A0 on the PMOD AD1

## Quick Tests (No Signal Generator Required)

- **Connect A0 to GND**: Should read `0x000` (or close to it)
- **Connect A0 to VCC**: Should read `0xFFF` (or close to it)
- **Leave floating**: Will show noise (random values)

## Concepts Demonstrated

1. **SPI Master (Read)**: Unlike the DAC project which writes to a device, this reads data from the ADC
2. **ADC Operation**: How analog-to-digital converters work with successive approximation
3. **Timing**: Meeting the AD7476A's SPI timing requirements
4. **Data Formatting**: Converting binary to hex ASCII for display
5. **UART Transmission**: Serial communication at 115200 baud
6. **State Machine Handshaking**: Coordination between ADC and UART state machines

## AD7476A SPI Protocol

The AD7476A uses a simple SPI-like interface for reading conversion results:

1. **CS goes LOW** - Samples analog input, starts conversion
2. **16 SCLK cycles** - ADC clocks out data on falling SCLK edges
3. **Data format**: `[0][0][0][0][DB11][DB10]...[DB1][DB0]`
4. **CS goes HIGH** - Ends transfer

Key timing (from datasheet):
- Max SCLK: 20 MHz (we use 6 MHz)
- Conversion time: 16 SCLK cycles
- Input bandwidth: 13.5 MHz

## Differences from DAC Project

| Aspect | DAC (dac-ramp) | ADC (adc-read) |
|--------|----------------|----------------|
| Data direction | FPGA -> Device | Device -> FPGA |
| Data pin | Output (DIN) | Input (SDATA) |
| Clock action | Output data before falling edge | Sample data after falling edge |
| Transfer | 16 bits written | 16 bits read |

## Files

- `adc-read.v` - Main Verilog module
- `icebreaker.pcf` - Pin constraints
- `Makefile` - Build rules
- `README.md` - This file
