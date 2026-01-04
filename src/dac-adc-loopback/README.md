# DAC-ADC Loopback

Generates a triangle wave on the DAC and reads it back via the ADC, demonstrating both analog output and input with UART monitoring.

## What It Does

A slow triangle wave (60-second full cycle) is generated on the PMOD DA2 DAC output. This signal is physically looped back to the PMOD AD1 ADC input, which samples it 10 times per second and sends hex readings via UART.

## Hardware Required

- iCEBreaker FPGA board
- PMOD DA2 (Digilent) on PMOD1A - DAC121S101 12-bit DAC
- PMOD AD1 (Digilent) on PMOD1B - AD7476A 12-bit ADC
- Jumper wire connecting DAC output to ADC input

## Pin Connections

### DAC (PMOD DA2 on PMOD1A)

| Signal | PMOD Pin | FPGA Pin | Description |
|--------|----------|----------|-------------|
| SYNC | 1 | 4 | Chip select (active low) |
| DIN | 2 | 2 | Serial data to DAC |
| SCLK | 4 | 45 | SPI clock |

### ADC (PMOD AD1 on PMOD1B)

| Signal | PMOD Pin | FPGA Pin | Description |
|--------|----------|----------|-------------|
| CS | 1 | 43 | Chip select (active low) |
| SDATA | 2 | 38 | Serial data from ADC |
| SCLK | 4 | 31 | SPI clock |

### Loopback Connection

Connect PMOD DA2 J2 pin 1 (VOUTA) to PMOD AD1 A0 input.

## Output Format

UART output at 115200 baud shows hex ADC readings:

```
0x000
0x010
0x020
...
0xFFF
0xFEF
...
```

## Timing

- System clock: 12 MHz
- SPI clock: 6 MHz
- Triangle wave period: 60 seconds (30s up, 30s down)
- ADC sample rate: 10 Hz
- UART: 115200 baud

## Project Structure

This project uses a modular design with separate reusable components:

| File | Description |
|------|-------------|
| `top.v` | Top-level module - wires everything together |
| `spi_dac.v` | Reusable SPI driver for DAC121S101 |
| `spi_adc.v` | Reusable SPI driver for AD7476A |
| `uart_tx.v` | Reusable UART transmitter |
| `triangle_gen.v` | Configurable triangle wave generator |
| `icebreaker.pcf` | Pin constraints |
| `Makefile` | Build rules |

## Usage

```bash
make        # Build bitstream
make prog   # Program iCEBreaker
make clean  # Remove build artifacts
```

Then monitor UART output:

```bash
screen /dev/ttyUSB1 115200
```

## Concepts Demonstrated

1. **Modular Verilog design** - Separate reusable modules vs monolithic code
2. **Module instantiation** - Connecting submodules with wires
3. **Parameterized modules** - Configurable baud rate, SPI speed, wave timing
4. **SPI master (write)** - Sending data to DAC121S101
5. **SPI master (read)** - Receiving data from AD7476A
6. **State machine handshaking** - Coordinating ADC and UART
7. **Analog loopback testing** - Verifying DAC output with ADC input

## Reusing Modules

The SPI and UART modules can be copied to other projects:

```verilog
// Example: instantiate UART transmitter
uart_tx #(
    .CLOCKS_PER_BIT(104)  // 115200 baud at 12 MHz
) u_uart (
    .clk(clk),
    .data_i(my_byte),
    .start_i(send_now),
    .busy_o(uart_busy),
    .tx_o(uart_tx)
);
```

## Expected Results

With loopback connected, ADC readings should track the triangle wave:
- Values slowly increase from 0x000 to 0xFFF over 30 seconds
- Values slowly decrease from 0xFFF to 0x000 over 30 seconds
- Cycle repeats continuously
