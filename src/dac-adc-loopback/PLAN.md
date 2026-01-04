# DAC-ADC Loopback Project Plan

## Overview
Combine DAC and ADC projects into a loopback test system. DAC outputs triangle wave, ADC reads it back, UART outputs hex values.

## Requirements
| Parameter | Value |
|-----------|-------|
| Clock | 12 MHz (NO PLL) |
| DAC waveform | Triangle: 0→4095→0 |
| DAC timing | 30s up, 30s down (60s cycle) |
| ADC sample rate | 10 Hz |
| UART | 115200 baud, `0xNNN\r\n` format |
| Project folder | `src/dac-adc-loopback/` |

## Key Timing Calculations
- **Clocks per DAC step**: 87,891 (30 sec × 12 MHz / 4096 steps)
- **Clocks per ADC sample**: 1,200,000 (12 MHz / 10 Hz)
- **UART clocks per bit**: 104 (12 MHz / 115200 baud)

## Pin Assignments
| Signal | Pin | PMOD |
|--------|-----|------|
| clk | 35 | - |
| dac_sync_n | 4 | PMOD1A |
| dac_din | 2 | PMOD1A |
| dac_sclk | 45 | PMOD1A |
| adc_cs_n | 43 | PMOD1B |
| adc_sdata | 38 | PMOD1B |
| adc_sclk | 31 | PMOD1B |
| uart_tx | 9 | USB |

## Critical Source Files
| File | Purpose |
|------|---------|
| `src/dac-ramp/dac-ramp.v` @ commit 7d12a2a | Pre-PLL DAC SPI code |
| `src/adc-read/adc-read.v` | ADC SPI + UART TX code |
| `src/dac-ramp/icebreaker.pcf` | DAC pin mappings |
| `src/adc-read/icebreaker.pcf` | ADC + UART pin mappings |

---

## TODO List

### Phase 1: DAC Triangle Wave (12 MHz, No PLL)
- [x] Create `icebreaker.pcf` with DAC pins only (clk, dac_sync_n, dac_din, dac_sclk)
- [x] Create `Makefile` based on dac-ramp
- [x] Create `dac-adc-loopback.v` with:
  - [x] Module declaration with DAC ports only
  - [x] DAC SPI state machine (from commit 7d12a2a, NO PLL)
  - [x] Step timer (17-bit counter to 87,891)
  - [x] Direction flag for triangle wave
  - [x] Boundary logic (toggle direction at 0 and 4095)
- [x] Build and verify with `make`
- [ ] **USER TEST**: Verify triangle wave on oscilloscope (60s cycle)

**STOP HERE** - Wait for user to verify DAC output before proceeding to Phase 2.

---

### Phase 2: Add ADC Sampling
- [ ] Add ADC pins to `icebreaker.pcf` (adc_cs_n, adc_sdata, adc_sclk)
- [ ] Add ADC ports to module declaration
- [ ] Add 10 Hz interval timer (21-bit counter to 1,200,000)
- [ ] Add ADC state machine (IDLE → START → SHIFT → DONE)
- [ ] Add `adc_result[11:0]` register to store readings
- [ ] Build and verify with `make`

### Phase 3: Add UART Output
- [ ] Add uart_tx pin to `icebreaker.pcf`
- [ ] Add uart_tx port to module declaration
- [ ] Add `hex_to_ascii` function
- [ ] Add message buffer for `0xNNN\r\n` (7 characters)
- [ ] Add UART state machine (IDLE → START → DATA → STOP)
- [ ] Add handshake between ADC and UART (uart_start_request, uart_busy)
- [ ] Build with `make`
- [ ] **USER TEST**: Program and verify with `screen /dev/ttyUSB1 115200`

### Final Verification
- [ ] Connect DAC output to ADC input with jumper wire
- [ ] Verify hex values ramp up over 30 seconds
- [ ] Verify hex values ramp down over 30 seconds
- [ ] Verify 10 readings per second
