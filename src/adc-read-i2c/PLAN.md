# ADS1115 I2C ADC Reader Implementation Plan

## Overview

Implementation of an ADS1115 16-bit I2C ADC reader for iCEBreaker FPGA with UART output.

**Branch**: `feature/ads1115`
**Location**: `/src/adc-read-i2c/`

**IMPORTANT**: Do not commit or push changes without explicit instruction from the user.

---

## Hardware Configuration

| Signal | Pin | Notes |
|--------|-----|-------|
| CLK | 35 | 12 MHz system clock |
| SCL | 45 | I2C clock (PMOD1A) |
| SDA | 47 | I2C data (PMOD1A) |
| BTN_ADDR | 20 | Button to ADS1115 ADDR |
| ADS_ADDR | 2 | ADS1115 address select |
| UART_TX | 9 | Serial output |

**DO NOT QUESTION**: Pin configuration and breakout board connection are verified correct.

---

## Architecture

```
+------------------+     +-------------+     +-----------+
|   i2c_master.v   |<--->|   top.v     |<--->|  uart_tx.v|
|  (SB_IO inside)  |     | (app logic) |     |           |
+------------------+     +-------------+     +-----------+
       ||                                         |
     SCL/SDA                                   UART_TX
       ||
   +----------+
   | ADS1115  |
   +----------+
```

---

## Files to Create

| File | Description |
|------|-------------|
| `top.v` | Main module with application state machine |
| `i2c_master.v` | I2C controller with SB_IO primitives inside |
| `uart_tx.v` | Copy from `/src/dac-adc-loopback/uart_tx.v` |
| `icebreaker.pcf` | Pin constraints |
| `Makefile` | Build system |
| `PLAN.md` | Plan document (copy of this) |
| `README.md` | Final docs (after all steps verified) |

---

## ADS1115 Configuration

- **Address**: 0x48 (ADDR=GND) or 0x49 (ADDR=VDD via button)
- **Config Register (0x01)**: `0x96D5`
  - MUX=100 (AIN0 single-ended)
  - PGA=001 (+/-4.096V)
  - MODE=0 (continuous)
  - DR=110 (250 SPS)
- **Conversion Register (0x00)**: 16-bit signed result

---

## I2C Implementation Details

### SB_IO Pattern (inside i2c_master.v)
```verilog
SB_IO #(
    .PIN_TYPE(6'b101001),
    .PULLUP(1'b0)
) scl_io (
    .PACKAGE_PIN(scl),
    .OUTPUT_CLK(clk),
    .OUTPUT_ENABLE(scl_oe),  // oe=1 drives LOW, oe=0 releases
    .D_OUT_0(1'b0),
    .D_IN_0(scl_in)
);
```

### Command Interface
- `CMD_START` (1): Generate START condition
- `CMD_STOP` (2): Generate STOP condition
- `CMD_WRITE` (3): Write byte, return ACK status
- `CMD_READ` (4): Read byte, send ACK/NACK

### Timing
- I2C clock: 100 kHz
- HALF_PERIOD = 60 cycles (at 12 MHz)
- Sample ACK at end of SCL HIGH period

### seen_busy Pattern
```verilog
if (i2c_busy) seen_busy <= 1;
else if (seen_busy) begin
    seen_busy <= 0;
    state <= NEXT_STATE;
end
```

---

## Implementation Steps

### Step 1: UART TX Verification (STOP POINT)

**Tasks**:
1. Copy `uart_tx.v` from dac-adc-loopback
2. Create minimal `top.v`:
   - Send `\r\nads1115\r\n` at startup
   - Send debug char every 1 second
3. Create `icebreaker.pcf` (clock + UART TX only)
4. Create `Makefile`
5. Build: `make && make prog`

**Verification**:
- UART shows "ads1115" at startup
- Debug chars appear every second
- **STOP AND WAIT** for developer verification

---

### Step 2: Address Check (STOP POINT)

**Tasks**:
1. Create `i2c_master.v` with:
   - SB_IO primitives for SCL/SDA
   - START, WRITE, STOP commands
   - ACK/NACK detection
2. Update `top.v`:
   - Button passthrough to ADS1115 ADDR
   - Address check: START -> 0x90 -> STOP
   - Send 'A' on ACK, 'E' on NACK
3. Update PCF with I2C and button pins

**Verification**:
- Button released: 'A' (ACK at 0x48)
- Button pressed: 'E' (NACK, wrong address)
- **STOP AND WAIT** for developer verification

---

### Step 3: Full I2C Read/Write

**Tasks**:
1. Add CMD_READ to i2c_master.v
2. Implement config write: START -> 0x90 -> 0x01 -> 0x96 -> 0xD5 -> STOP
3. Set conversion pointer: START -> 0x90 -> 0x00 -> STOP

---

### Step 4: Continuous Reading

**Tasks**:
1. Read loop: START -> 0x91 -> MSB(ACK) -> LSB(NACK) -> STOP
2. Format as hex: `0xNNNN\r\n`
3. 200ms delay (5 readings/sec)

---

### Step 5: Final Polish

**Tasks**:
1. Error handling ('E' on any NACK)
2. Create README.md
3. Code cleanup

---

## Common Pitfalls

| Mistake | Correct Approach |
|---------|------------------|
| Using `assign` for open-drain | Use SB_IO primitive |
| `scl_oe=1` means drive HIGH | `scl_oe=1` means drive LOW |
| Changing SDA when SCL HIGH | SDA changes only when SCL LOW |
| Not waiting for command completion | Use seen_busy pattern |

---

## Verification

### Expected UART Output

**Step 1**:
```
\r\nads1115\r\n
I
I
...
```

**Step 2**:
```
\r\nads1115\r\n
A   (button released)
E   (button pressed)
```

**Final**:
```
\r\nads1115\r\n
0x0ABC
0x0ABD
...
```

---

## Reference Files

- `/src/dac-adc-loopback/uart_tx.v` - UART module to copy
- `/src/dac-adc-loopback/top.v` - Pattern reference
- `/src/dac-adc-loopback/Makefile` - Build template
- `/docs/ads1115.pdf` - ADC datasheet
- `/docs/A Basic Guide to I2C - TI.pdf` - I2C protocol
