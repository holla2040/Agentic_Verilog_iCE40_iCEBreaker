# ADS1115 I2C ADC Implementation Plan

## Project Overview

Read analog voltage from ADS1115 16-bit ADC via I2C and output hex values over UART at 5 readings per second.

**Target:** iCEBreaker FPGA (iCE40 UP5K) with 12 MHz clock

---

## CRITICAL NOTES FOR IMPLEMENTING AGENT

### Git Policy
**DO NOT commit or push changes without explicit instruction from the developer.** Wait for explicit "commit" or "push" commands before performing these git operations.

### Hardware Verification - DO NOT QUESTION
The following hardware configuration is VERIFIED and WORKING. Do not suggest debugging these aspects or question whether they are connected correctly:
- ADS1115 breakout board is connected and powered on 3.3V
- Pull-up resistors on SDA/SCL are present on the breakout board
- Pin assignments are correct as specified below
- The breakout board functions correctly

**If communication fails, the issue is in the Verilog implementation, NOT the hardware.**

---

## Hardware Configuration

### Pin Assignments (ACTIVE - DO NOT MODIFY)

| Signal | FPGA Pin | Direction | Description |
|--------|----------|-----------|-------------|
| CLK | 35 | Input | 12 MHz system clock |
| SCL | 45 | Bidirectional | I2C clock (PMOD1A) |
| SDA | 47 | Bidirectional | I2C data (PMOD1A) |
| ADDR_BTN | 2 | Output | Connected to ADS1115 ADDR pin |
| ALRT | 4 | Input | ADS1115 alert/ready (optional) |
| BTN_N | 20 | Input | iCEBreaker button (directly drives ADDR_BTN) |
| TX | 9 | Output | UART transmit to FTDI chip |

### Button-to-ADDR Connection
- iCEBreaker button (pin 20) directly drives ADS1115 ADDR pin (pin 2)
- Button UP (not pressed): ADDR = LOW → I2C address = 0x48
- Button DOWN (pressed): ADDR = HIGH → I2C address = 0x49
- This allows dynamic address verification during development

### ADS1115 Breakout Board
- Operating voltage: 3.3V
- On-board pull-up resistors for SDA and SCL (no external pull-ups needed)
- Analog input: A0 pin (single-ended, 0-3.3V range)

---

## I2C Bus Requirements

### Bus States
- **IDLE:** Both SDA and SCL HIGH (released to pull-ups)
- **ACTIVE:** Communication in progress

### START Condition
1. Bus must be IDLE (SDA=1, SCL=1)
2. Pull SDA LOW while SCL remains HIGH
3. Then pull SCL LOW
4. **Critical:** SDA transition HIGH→LOW while SCL is stable HIGH

### STOP Condition
1. SCL must be LOW, SDA must be LOW
2. Release SCL (pull-up brings it HIGH)
3. After SCL is HIGH, release SDA (pull-up brings it HIGH)
4. **Critical:** SDA transition LOW→HIGH while SCL is stable HIGH

### ACK/NACK Protocol
- 9th bit of every byte frame
- **ACK:** Receiver pulls SDA LOW during SCL HIGH pulse
- **NACK:** SDA remains HIGH (released)
- Master must release SDA during ACK bit to allow slave to respond
- On NACK: abort transaction and report error

### Open-Drain Implementation
Both SCL and SDA MUST use open-drain configuration:
- `OE=1` → Drive pin LOW (pull-down active)
- `OE=0` → Release pin (external pull-up brings HIGH)
- **Never drive HIGH directly**

---

## ADS1115 Configuration

### I2C Addresses
- ADDR tied to GND: **0x48** (default when button not pressed)
- ADDR tied to VDD: **0x49** (when button pressed)

### Register Map
| Pointer | Register | Access | Description |
|---------|----------|--------|-------------|
| 0x00 | Conversion | Read-only | 16-bit ADC result |
| 0x01 | Config | Read/Write | Configuration settings |
| 0x02 | Lo_thresh | Read/Write | Low threshold |
| 0x03 | Hi_thresh | Read/Write | High threshold |

### Configuration Register Value: 0xC3E3

Bit-by-bit breakdown for our application:

| Bits | Field | Value | Setting |
|------|-------|-------|---------|
| 15 | OS | 1 | Start conversion / conversion complete |
| 14:12 | MUX | 100 | AIN0 single-ended (vs GND) |
| 11:9 | PGA | 001 | ±4.096V full-scale (125 µV/LSB) |
| 8 | MODE | 0 | Continuous conversion |
| 7:5 | DR | 111 | 860 SPS (fastest rate) |
| 4 | COMP_MODE | 0 | Traditional comparator |
| 3 | COMP_POL | 0 | Active low |
| 2 | COMP_LAT | 0 | Non-latching |
| 1:0 | COMP_QUE | 11 | Disable comparator |

**Config register bytes:** High byte = 0xC3, Low byte = 0xE3

### Voltage Calculation
- Full-scale: ±4.096V (but input limited to 0-3.3V)
- LSB size: 4.096V / 32768 = 125 µV
- For 3.3V input: 3.3V / 0.000125 = 26,400 counts (0x6720)
- Output is 16-bit unsigned for single-ended (always positive)

---

## I2C Communication Sequences

### Sequence 1: Write Configuration Register
```
START → [0x90] → ACK → [0x01] → ACK → [0xC3] → ACK → [0xE3] → ACK → STOP
         addr+W      pointer      config_hi       config_lo
```
- Address byte: 0x48 << 1 | 0 = 0x90 (write)
- Pointer byte: 0x01 (config register)
- Data: 0xC3E3

### Sequence 2: Set Pointer to Conversion Register
```
START → [0x90] → ACK → [0x00] → ACK → STOP
         addr+W      pointer
```

### Sequence 3: Read Conversion Result
```
START → [0x91] → ACK → [MSB] → ACK → [LSB] → NACK → STOP
         addr+R      data_hi       data_lo
```
- Address byte: 0x48 << 1 | 1 = 0x91 (read)
- Master sends ACK after MSB, NACK after LSB
- NACK signals end of read to slave

### Continuous Read Operation
After initial configuration, repeatedly execute Sequence 3 to read new conversion results. In continuous mode, the conversion register always contains the most recent completed conversion - no need to poll status bits.

---

## I2C Timing (Fast Mode 400 kHz)

| Parameter | Value | Description |
|-----------|-------|-------------|
| Clock period | 2.5 µs | 400 kHz |
| tLOW | 1.3 µs min | SCL low time |
| tHIGH | 0.6 µs min | SCL high time |
| tSU;DAT | 100 ns min | Data setup before SCL rise |
| tHD;STA | 0.6 µs min | Hold time after START |
| tSU;STO | 0.6 µs min | Setup time for STOP |
| tBUF | 0.6 µs min | Bus free time between STOP and START |

**Clock divider calculation:**
- System clock: 12 MHz (83.3 ns period)
- I2C clock: 400 kHz (2.5 µs period)
- Divider: 12 MHz / 400 kHz = 30 system clocks per I2C clock
- Half period: 15 clocks LOW, 15 clocks HIGH

---

## SB_IO_OD Implementation for iCE40UP

Use `SB_IO_OD` primitive (not regular `SB_IO`) for proper open-drain:

```verilog
// SCL open-drain output with input
SB_IO_OD #(
    .PIN_TYPE(6'b010001)  // Tristate output + latched input
) scl_io (
    .PACKAGEPIN(scl),
    .OUTPUTENABLE(scl_oe),  // 1=drive LOW, 0=release to pull-up
    .DOUT0(1'b0),           // Always drive 0 when enabled
    .DIN0(scl_in)           // Read back actual pin state
);

// SDA open-drain bidirectional
SB_IO_OD #(
    .PIN_TYPE(6'b010001)
) sda_io (
    .PACKAGEPIN(sda),
    .OUTPUTENABLE(sda_oe),  // 1=drive LOW, 0=release to pull-up
    .DOUT0(1'b0),
    .DIN0(sda_in)           // Read SDA for ACK detection and data reads
);
```

**Control Logic:**
- To output LOW: set `xxx_oe = 1`
- To release HIGH: set `xxx_oe = 0`
- Read pin state via `xxx_in` (for ACK detection and reading data)

---

## UART Output Specification

### Format
- Baud rate: 115200 bps
- Frame: 8N1 (8 data bits, no parity, 1 stop bit)
- Output format: `0xNNNN\r\n` where NNNN is 4 hex digits

### Timing
- Output rate: 5 readings per second (200 ms interval)
- Characters per reading: 8 (`0x` + 4 hex digits + `\r\n`)
- Time per character at 115200: ~87 µs
- Total transmission time: ~0.7 ms per reading (well under 200 ms budget)

### Error Output
- On NACK (no ACK received): Output `E\r\n`
- This indicates communication failure (wrong address, device not responding)

### Reference Implementation
See `/src/uart-tx/uart_tx.v` for working UART transmitter:
- Module interface: `clk` input, `tx` output
- State machine: IDLE → START → DATA (8 bits) → STOP
- Baud timing: `CLOCKS_PER_BIT = 104` for 115200 baud at 12 MHz

---

## Module Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        top.v                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  i2c_master │  │  ads1115    │  │  uart_tx            │ │
│  │             │←→│  _controller│→→│                     │ │
│  │  (low-level │  │             │  │  (byte transmitter) │ │
│  │   I2C ops)  │  │  (ADC state │  │                     │ │
│  │             │  │   machine)  │  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│         ↕                ↑                    ↓            │
│     SDA/SCL          btn_addr_n              TX            │
│   (SB_IO_OD)         (button)             (to FTDI)       │
└─────────────────────────────────────────────────────────────┘
```

### Module Breakdown

1. **top.v** - Top-level instantiation and pin mapping
2. **i2c_master.v** - Low-level I2C operations (START, STOP, byte TX/RX, ACK handling)
3. **ads1115_controller.v** - ADS1115-specific state machine (configure, read loop)
4. **uart_tx.v** - UART byte transmitter with hex formatting

---

## Implementation Steps

### STEP 1: UART TX Verification

**Objective:** Verify UART communication works before adding I2C complexity.

**Tasks:**
- [ ] Create project directory structure and Makefile
- [ ] Implement `uart_tx.v` module (adapt from `/src/uart-tx/`)
- [ ] Create `top.v` that sends `"\r\nads1115\r\n"` at startup
- [ ] After startup message, send a state character every 1 second (e.g., 'I' for idle)
- [ ] Create `icebreaker.pcf` with TX pin (pin 9) and CLK (pin 35)
- [ ] Run `make` to verify compilation
- [ ] Run `make prog` to flash

**Verification Criteria:**
```
Developer opens serial terminal at 115200 baud.
Expected output:
  ads1115
  I
  I
  I
  ... (repeating every second)
```

**STOP HERE** - Do not proceed until developer confirms UART output is working.

---

### STEP 2: I2C Address Check (ACK/NACK Detection)

**Objective:** Verify I2C communication with ACK/NACK detection.

**Tasks:**
- [ ] Implement `i2c_master.v` with SB_IO_OD primitives for SCL/SDA
- [ ] Implement START condition generation
- [ ] Implement byte transmission with ACK detection
- [ ] Implement STOP condition generation
- [ ] Add button pass-through (pin 20 directly to pin 2 for ADDR)
- [ ] Modify `top.v` to:
  - On startup: send address byte (0x90) and check for ACK
  - Output 'A' if ACK received, 'N' if NACK
  - Repeat check every second
- [ ] Update PCF with I2C pins and button

**Pin Configuration for Step 2:**
```
set_io clk 35
set_io tx 9
set_io scl 45
set_io sda 47
set_io btn_n 20
set_io addr_out 2
```

**Verification Criteria:**
```
With button NOT pressed (ADDR=GND, address 0x48):
  Expected: "A" (ACK received)

Press button (ADDR=VDD, address 0x49):
  Expected: "N" (NACK - device at 0x48 doesn't respond to 0x49 address probe)

Release button:
  Expected: "A" again
```

**STOP HERE** - Do not proceed until developer confirms ACK/NACK detection works correctly.

---

### STEP 3: ADS1115 Configuration

**Objective:** Write configuration register to set up continuous conversion.

**Tasks:**
- [ ] Implement I2C write sequence (START → addr → pointer → data_hi → data_lo → STOP)
- [ ] Create `ads1115_controller.v` state machine
- [ ] Add configuration state: write 0xC3E3 to config register (0x01)
- [ ] Verify ACK received for each byte
- [ ] Output 'C' on successful configuration, 'E' on any NACK

**Verification Criteria:**
```
Expected output: "C" indicating successful configuration write
```

---

### STEP 4: Read Conversion Data

**Objective:** Read ADC values and output over UART.

**Tasks:**
- [ ] Implement I2C read sequence (START → addr+R → read_hi → read_lo → STOP)
- [ ] Master must send ACK after first byte, NACK after second byte
- [ ] Implement 200 ms timer for 5 Hz read rate
- [ ] Implement hex formatting (convert 16-bit value to "0xNNNN\r\n")
- [ ] Output reading every 200 ms

**Verification Criteria:**
```
Apply known voltage to A0:
  0V → ~0x0000
  1.65V → ~0x3390
  3.3V → ~0x6720

Output format: 0x1234\r\n (5 times per second)
```

---

### STEP 5: Error Handling and Cleanup

**Objective:** Robust error handling and code cleanup.

**Tasks:**
- [ ] Add timeout detection for stuck bus
- [ ] Ensure 'E\r\n' output on any communication failure
- [ ] Add detailed comments explaining I2C protocol
- [ ] Verify no LEDs are manipulated (per requirements)
- [ ] Final code review and cleanup

---

## I2C State Machine Design Notes

### Recommended State Structure

Use `_CMD` and `_WAIT` states to ensure command completion:

```verilog
localparam STATE_IDLE       = 4'd0;
localparam STATE_START_CMD  = 4'd1;
localparam STATE_START_WAIT = 4'd2;
localparam STATE_WRITE_CMD  = 4'd3;
localparam STATE_WRITE_WAIT = 4'd4;
localparam STATE_READ_CMD   = 4'd5;
localparam STATE_READ_WAIT  = 4'd6;
localparam STATE_STOP_CMD   = 4'd7;
localparam STATE_STOP_WAIT  = 4'd8;
```

### Detecting Command Completion

Monitor falling edge of `i2c_busy` signal:

```verilog
reg i2c_busy_prev;
wire i2c_done = i2c_busy_prev & ~i2c_busy;  // Falling edge

always @(posedge clk) begin
    i2c_busy_prev <= i2c_busy;
end
```

---

## Files to Create

```
src/adc-read-i2c/
├── PLAN.md              (this file)
├── Makefile
├── icebreaker.pcf
├── top.v                (top-level module)
├── i2c_master.v         (low-level I2C)
├── ads1115_controller.v (ADC state machine)
└── uart_tx.v            (serial output)
```

---

## Makefile Template

```makefile
PROJ = adc_read_i2c
TOP = top

SOURCES = top.v i2c_master.v ads1115_controller.v uart_tx.v
PCF = icebreaker.pcf

all: $(PROJ).bin

$(PROJ).json: $(SOURCES)
	yosys -p "synth_ice40 -top $(TOP) -json $@" $(SOURCES)

$(PROJ).asc: $(PROJ).json $(PCF)
	nextpnr-ice40 --up5k --package sg48 --json $< --pcf $(PCF) --asc $@

$(PROJ).bin: $(PROJ).asc
	icepack $< $@

prog: $(PROJ).bin
	iceprog $<

clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).bin

.PHONY: all prog clean
```

---

## Quick Reference

| Item | Value |
|------|-------|
| System clock | 12 MHz |
| I2C clock | 400 kHz (30 system clocks per I2C clock) |
| I2C address | 0x48 (button up) / 0x49 (button down) |
| Config register | 0xC3E3 |
| UART baud | 115200 |
| Output rate | 5 Hz (200 ms) |
| Output format | `0xNNNN\r\n` |
| Error output | `E\r\n` |

---

## Revision History

| Date | Description |
|------|-------------|
| Initial | Plan created for clean agent implementation |
