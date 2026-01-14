# SBTICE Technology Library Index

**Document**: Lattice ICE Technology Library Version 3.0 (August 2016, January 2017)
**Source**: `docs/SBTICETechnologyLibrary201701-part-*.pdf` (18 parts, pages 1-180)

This index maps sections and primitives to their PDF part files for easy reference. The iCEBreaker board uses the **iCE40UP (iCE40 Ultra Plus)** family - look for sections marked with that family for the most relevant documentation.

---

## Quick Reference by Device Family

| Device Family | Pages | Part Files | Key Primitives |
|---------------|-------|------------|----------------|
| **iCE40 (General)** | 7-93 | part-001-010 to part-091-100 | SB_DFF*, SB_LUT4, SB_CARRY, SB_RAM*, SB_IO, SB_GB* |
| **iCE40 PLL** | 94-112 | part-091-100 to part-111-120 | SB_PLL40_* |
| **iCE40LM** | 113-120 | part-111-120 | SB_HSOSC, SB_LSOSC, SB_I2C, SB_SPI |
| **iCE5LP (Ultra)** | 121-144 | part-121-130 to part-141-150 | SB_HFOSC, SB_LFOSC, SB_LED_DRV_CUR, SB_RGB_DRV, SB_IR_DRV, SB_MAC16 |
| **iCE40UL (Ultra Lite)** | 145-161 | part-141-150 to part-161-170 | SB_RGBA_DRV, SB_IR400_DRV, SB_BARCODE_DRV, SB_IR500_DRV, SB_LEDDA_IP, SB_IR_IP, SB_I2C_FIFO |
| **iCE40UP (Ultra Plus)** | 162-180 | part-161-170 to part-171-180 | SB_HFOSC, SB_LFOSC, SB_RGBA_DRV, SB_LEDDA_IP, SB_I2C, SB_SPI, SB_MAC16, SB_SPRAM256KA, SB_IO_I3C |

---

## Document Structure

### Front Matter (Pages 1-6)
**Part File**: `part-001-010.pdf`
- Title Page, Copyright, Trademarks, Disclaimers
- Revision History (Version 2.0 to 3.0)
- Table of Contents

---

## Register Primitives (Pages 7-46)

### Positive Edge Clock D Flip-Flops

| Primitive | Description | Pages | Part File |
|-----------|-------------|-------|-----------|
| **SB_DFF** | Basic D Flip-Flop | 7-8 | part-001-010 |
| **SB_DFFE** | D Flip-Flop with Clock Enable | 9-10 | part-001-010 |
| **SB_DFFSR** | D Flip-Flop with Synchronous Reset | 11-12 | part-011-020 |
| **SB_DFFR** | D Flip-Flop with Asynchronous Reset | 13-14 | part-011-020 |
| **SB_DFFSS** | D Flip-Flop with Synchronous Set | 15-16 | part-011-020 |
| **SB_DFFS** | D Flip-Flop with Asynchronous Set | 17-18 | part-011-020 |
| **SB_DFFESR** | D Flip-Flop with Enable and Synchronous Reset | 19-20 | part-011-020 |
| **SB_DFFER** | D Flip-Flop with Enable and Asynchronous Reset | 21-22 | part-021-030 |
| **SB_DFFESS** | D Flip-Flop with Enable and Synchronous Set | 23-24 | part-021-030 |
| **SB_DFFES** | D Flip-Flop with Enable and Asynchronous Set | 25-26 | part-021-030 |

### Negative Edge Clock D Flip-Flops

| Primitive | Description | Pages | Part File |
|-----------|-------------|-------|-----------|
| **SB_DFFN** | D Flip-Flop (negative edge) | 27-28 | part-021-030 |
| **SB_DFFNE** | D Flip-Flop with Enable (negative edge) | 29-30 | part-021-030 |
| **SB_DFFNSR** | D Flip-Flop with Synchronous Reset (negative edge) | 31-32 | part-031-040 |
| **SB_DFFNR** | D Flip-Flop with Asynchronous Reset (negative edge) | 33-34 | part-031-040 |
| **SB_DFFNSS** | D Flip-Flop with Synchronous Set (negative edge) | 35-36 | part-031-040 |
| **SB_DFFNS** | D Flip-Flop with Asynchronous Set (negative edge) | 37-38 | part-031-040 |
| **SB_DFFNESR** | D Flip-Flop with Enable and Synchronous Reset (negative edge) | 39-40 | part-031-040 |
| **SB_DFFNER** | D Flip-Flop with Enable and Asynchronous Reset (negative edge) | 41-42 | part-041-050 |
| **SB_DFFNESS** | D Flip-Flop with Enable and Synchronous Set (negative edge) | 43-44 | part-041-050 |
| **SB_DFFNES** | D Flip-Flop with Enable and Asynchronous Set (negative edge) | 45-46 | part-041-050 |

### Flip-Flop Naming Convention
- **SB_DFF** = Base name
- **N** = Negative edge clock
- **E** = Clock Enable
- **S** or **R** = Set or Reset
- Final **S** = Synchronous (absence = Asynchronous)

---

## Combinational Logic Primitives (Pages 47-50)
**Part File**: `part-041-050.pdf`

| Primitive | Description | Pages |
|-----------|-------------|-------|
| **SB_LUT4** | 4-input Look-Up Table | 47-48 |
| **SB_CARRY** | Carry chain logic for arithmetic operations | 49-50 |

**SB_LUT4 Key Details**:
- 16-bit LUT_INIT parameter defines output for all 16 input combinations
- Inputs: I0, I1, I2, I3; Output: O

**SB_CARRY Key Details**:
- Accelerates adders, counters, ALUs, comparators
- Shares I1 and I2 inputs with associated LUT

---

## Block RAM Primitives (Pages 51-87)

### iCE40 Block RAM Overview
**Part File**: `part-051-060.pdf`
- 4Kbit RAM blocks with separate write/read ports
- Four configurations: 256x16, 512x8, 1024x4, 2048x2
- Only 256x16 has MASK port

### RAM Primitive Naming Convention
- Base name (e.g., `SB_RAM256x16`): Positive edge on both clocks
- **NR** suffix: Negative edge on Read clock
- **NW** suffix: Negative edge on Write clock
- **NRNW** suffix: Negative edge on both clocks

### 256x16 RAM Family
**Part Files**: `part-051-060.pdf` to `part-061-070.pdf`

| Primitive | Read Clock | Write Clock | Pages |
|-----------|------------|-------------|-------|
| SB_RAM256x16 | Positive | Positive | 53-55 |
| SB_RAM256x16NR | Negative | Positive | 55-56 |
| SB_RAM256x16NW | Positive | Negative | 57-58 |
| SB_RAM256x16NRNW | Negative | Negative | 58-59 |

### 512x8 RAM Family
**Part Files**: `part-051-060.pdf` to `part-061-070.pdf`

| Primitive | Read Clock | Write Clock | Pages |
|-----------|------------|-------------|-------|
| SB_RAM512x8 | Positive | Positive | 59-61 |
| SB_RAM512x8NR | Negative | Positive | 62-63 |
| SB_RAM512x8NW | Positive | Negative | 63-65 |
| SB_RAM512x8NRNW | Negative | Negative | 65-67 |

### 1024x4 RAM Family
**Part Files**: `part-061-070.pdf` to `part-071-080.pdf`

| Primitive | Read Clock | Write Clock | Pages |
|-----------|------------|-------------|-------|
| SB_RAM1024x4 | Positive | Positive | 68-69 |
| SB_RAM1024x4NR | Negative | Positive | 70-71 |
| SB_RAM1024x4NW | Positive | Negative | 71-73 |
| SB_RAM1024x4NRNW | Negative | Negative | 73-75 |

### 2048x2 RAM Family
**Part Files**: `part-071-080.pdf` to `part-081-090.pdf`

| Primitive | Read Clock | Write Clock | Pages |
|-----------|------------|-------------|-------|
| SB_RAM2048x2 | Positive | Positive | 75-77 |
| SB_RAM2048x2NR | Negative | Positive | 77-79 |
| SB_RAM2048x2NW | Positive | Negative | 79-80 |
| SB_RAM2048x2NRNW | Negative | Negative | 81-82 |

### SB_RAM40_4K (Physical 4K RAM)
**Part File**: `part-081-090.pdf` (Pages 82-87)
- Basic physical 4K-bit RAM primitive
- Configurable data widths via READ_MODE and WRITE_MODE parameters
- INIT_0 through INIT_F for initialization
- Variants: SB_RAM40_4K, SB_RAM40_4KNR, SB_RAM40_4KNW, SB_RAM40_4KNRNW

---

## IO Primitives (Pages 88-91)
**Part Files**: `part-081-090.pdf` to `part-091-100.pdf`

### SB_IO
- General purpose I/O primitive with 5 registers
- PIN_TYPE[5:0] configures input and output functions
- DDR support for rising/falling edge data
- High drive strength options (x1, x2, x3)

**Input Pin Functions** (PIN_TYPE[1:0]):
- PIN_INPUT (01): Simple input
- PIN_INPUT_LATCH (11): Latched input
- PIN_INPUT_REGISTERED (00): Registered input
- PIN_INPUT_REGISTERED_LATCH (10): Registered and latched
- PIN_INPUT_DDR (00): DDR input

**Output Pin Functions** (PIN_TYPE[5:2]):
- 13 modes including output, tristate, registered, DDR, inverted

### Pull-Up Resistor Configuration
**Part File**: `part-091-100.pdf` (Page 91)
- iCE40UL: PULLUP_RESISTOR attribute ("3P3K", "6P8K", "10K", "100K")

---

## Global Buffer Primitives (Pages 92-93)
**Part File**: `part-091-100.pdf`

| Primitive | Description |
|-----------|-------------|
| **SB_GB_IO** | Global buffer with I/O capability |
| **SB_GB** | Standard global buffer for internally generated clocks |

---

## PLL Primitives (Pages 94-112)
**Part Files**: `part-091-100.pdf` to `part-111-120.pdf`

### PLL Primitive Selection Guide

| Primitive | Clock Source | Output Ports | Use When |
|-----------|--------------|--------------|----------|
| **SB_PLL40_CORE** | FPGA routing | 1 | Clock from FPGA or non-Bank 0/2 pad |
| **SB_PLL40_PAD** | IO Bank 0/2 pad | 1 | External clock, not needed internally |
| **SB_PLL40_2_PAD** | IO Bank 0/2 pad | 2 (source + PLL) | External clock needed internally |
| **SB_PLL40_2F_CORE** | FPGA routing | 2 different freqs | Generate 2 frequencies from internal |
| **SB_PLL40_2F_PAD** | IO Bank 0/2 pad | 2 different freqs | Generate 2 frequencies from external |

### Key PLL Parameters

| Parameter | Description | Values |
|-----------|-------------|--------|
| FEEDBACK_PATH | Feedback path selection | SIMPLE, DELAY, PHASE_AND_DELAY, EXTERNAL |
| DIVR | Reference clock divider | 0-15 |
| DIVF | Feedback divider | 0-63 |
| DIVQ | VCO divider | 1-6 |
| FILTER_RANGE | PLL filter range | 0-7 |
| PLLOUT_SELECT | Output signal selection | SHIFTREG_0deg, SHIFTREG_90deg, GENCLK, GENCLK_HALF |
| FDA_FEEDBACK | Fine delay adjust | 0-15 (delay = (n+1)*150ps) |

---

## Hard Macro Primitives

### iCE40LM Hard Macros (Pages 113-120)
**Part File**: `part-111-120.pdf`

| Primitive | Description | Frequency/Rate |
|-----------|-------------|----------------|
| **SB_HSOSC** | High-Speed Strobe Generator | 12 MHz |
| **SB_LSOSC** | Low-Power Strobe Generator | 10 KHz |
| **SB_I2C** | I2C hard IP (2 instances: upper left/right) | Configurable |
| **SB_SPI** | SPI hard IP (2 instances: lower left/right) | Configurable |

### iCE5LP (iCE40 Ultra) Hard Macros (Pages 121-144)
**Part Files**: `part-121-130.pdf` to `part-141-150.pdf`

| Primitive | Description | Pages |
|-----------|-------------|-------|
| **SB_HFOSC** | High-frequency oscillator (48MHz, divider 1/2/4/8) | 121-122 |
| **SB_LFOSC** | Low-frequency oscillator (10KHz) | 122-123 |
| **SB_LED_DRV_CUR** | Reference current generator for LED drivers | 123-124 |
| **SB_RGB_DRV** | RGB LED driver (0-24mA per channel) | 124-125 |
| **SB_IR_DRV** | IR LED driver (0-500mA) | 125-126 |
| **SB_RGB_IP** | RGB PWM generator | 127 |
| **SB_IO_OD** | Open drain I/O | 128-129 |
| **SB_I2C** | I2C hard IP | 130 |
| **SB_SPI** | SPI hard IP | 131 |
| **SB_MAC16** | 16x16 DSP block | 132-144 |

### iCE40UL (Ultra Lite) Hard Macros (Pages 145-161)
**Part Files**: `part-141-150.pdf` to `part-161-170.pdf`

| Primitive | Description | Pages |
|-----------|-------------|-------|
| **SB_HFOSC** | High-frequency oscillator (48MHz) | 145-146 |
| **SB_LFOSC** | Low-frequency oscillator (10KHz) | 146-147 |
| **SB_RGBA_DRV** | RGBA LED driver | 147-148 |
| **SB_IR400_DRV** | IR LED driver (0-400mA) | 149-150 |
| **SB_BARCODE_DRV** | Barcode LED driver (0-100mA) | 150-151 |
| **SB_IR500_DRV** | IR LED driver (0-500mA, 2 pins) | 151-152 |
| **SB_LEDDA_IP** | LED Driver Analog IP (SCI bus programmed) | 153-154 |
| **SB_IR_IP** | IR transceiver module | 154-156 |
| **SB_IO_OD** | Open drain I/O | 156-158 |
| **SB_I2C_FIFO** | I2C with FIFO buffer | 158-161 |

### iCE40UP (Ultra Plus) Hard Macros (Pages 162-180)
**Part Files**: `part-161-170.pdf` to `part-171-180.pdf`

**This is the device family used by iCEBreaker!**

| Primitive | Description | Pages |
|-----------|-------------|-------|
| **SB_HFOSC** | High-frequency oscillator (48MHz, divider 1/2/4/8) | 162-163 |
| **SB_LFOSC** | Low-frequency oscillator (10KHz) | 163-164 |
| **SB_RGBA_DRV** | RGBA LED driver (0-24mA per channel) | 164-165 |
| **SB_LEDDA_IP** | LED Driver Analog IP | 166 |
| **SB_IO_OD** | Open drain I/O | 166-168 |
| **SB_I2C** | I2C hard IP (upper left/right corners) | 168-170 |
| **SB_SPI** | SPI hard IP (lower left/right corners) | 171 |
| **SB_MAC16** | 16x16 DSP block | 171 (refs 133) |
| **SB_SPRAM256KA** | 256Kbit Single-Port RAM (4 blocks) | 172-174 |
| **SB_IO_I3C** | I3C compatible I/O with pull-up control | 175-178 |

---

## SB_MAC16 DSP Block (Pages 132-144)
**Part Files**: `part-131-140.pdf` to `part-141-150.pdf`

### Supported Configurations
1. **Multiplier**: 8x8 or 16x16
2. **MAC (Multiply-Accumulate)**: 16-bit or 32-bit
3. **Accumulator**: 16-bit or 32-bit
4. **Add/Subtract**: 16-bit or 32-bit
5. **Multiply-Add/Subtract**: 16-bit or 32-bit

### Key Parameters
- NEG_TRIGGER: Clock polarity
- A_REG, B_REG, C_REG, D_REG: Input register controls
- PIPELINE_16x16_MULT_REG1/2: Pipeline register controls
- TOPOUTPUT_SELECT, BOTOUTPUT_SELECT: Output mux controls
- A_SIGNED, B_SIGNED: Signed/unsigned inputs

---

## SB_SPRAM256KA (Pages 172-174)
**Part File**: `part-171-180.pdf`

**iCE40UP Single-Port RAM** - 4 blocks of 256Kbit each (16K x 16)

### Key Ports
| Port | Width | Description |
|------|-------|-------------|
| ADDRESS | 14 | Read/write address |
| DATAIN | 16 | Write data input |
| DATAOUT | 16 | Read data output |
| MASKWREN | 4 | Nibble-level write mask |
| WREN | 1 | Write enable (high=write, low=read) |
| CHIPSELECT | 1 | Memory enable |
| CLOCK | 1 | Clock input |
| STANDBY | 1 | Low leakage mode |
| SLEEP | 1 | Power down periphery |
| POWEROFF | 1 | Memory core power (low=off, no retention) |

---

## Device Configuration Primitives (Page 180)
**Part File**: `part-171-180.pdf`

### SB_WARMBOOT
- Runtime loading of different configuration images
- Supports 4 pre-defined images via S1, S0 inputs
- BOOT signal (level-triggered) initiates image loading
- Image addresses configured in iCEcube2

---

## Synthesis Attributes Reference

| Attribute | Primitive | Description |
|-----------|-----------|-------------|
| ROUTE_THROUGH_FABRIC | SB_HFOSC, SB_LFOSC | 0=dedicated clock, 1=fabric routes |
| I2C_CLK_DIVIDER | SB_I2C | Clock divider 0-1023 |
| SPI_CLK_DIVIDER | SB_SPI | Clock divider 0-63 |
| SDA_INPUT_DELAYED | SB_I2C | Add 50ns delay to SDAI |
| SDA_OUTPUT_DELAYED | SB_I2C | Add 50ns delay to SDAO |
| SCL_INPUT_FILTERED | SB_I2C | Add 50ns glitch filter to SCLI |
| I2C_FIFO_ENB | SB_I2C_FIFO | Enable/disable FIFO mode |
| PULLUP_RESISTOR | SB_IO, SB_IO_I3C | "3P3K", "6P8K", "10K", "100K" |
| DRIVE_STRENGTH | SB_IO | x1, x2, x3 (iCE40/iCE40LM only) |
| CURRENT_MODE | LED drivers | Full/Half current mode |

---

## Part File Quick Reference

| Part File | Pages | Key Contents |
|-----------|-------|--------------|
| part-001-010 | 1-10 | Front matter, TOC, SB_DFF, SB_DFFE |
| part-011-020 | 11-20 | SB_DFFSR, SB_DFFR, SB_DFFSS, SB_DFFS, SB_DFFESR |
| part-021-030 | 21-30 | SB_DFFER, SB_DFFESS, SB_DFFES, SB_DFFN, SB_DFFNE |
| part-031-040 | 31-40 | Negative edge flip-flops (SB_DFFN*) |
| part-041-050 | 41-50 | SB_DFFNER, SB_DFFNESS, SB_DFFNES, SB_LUT4, SB_CARRY |
| part-051-060 | 51-60 | Block RAM intro, SB_RAM256x16 family, SB_RAM512x8 start |
| part-061-070 | 61-70 | SB_RAM512x8 family, SB_RAM1024x4 start |
| part-071-080 | 71-80 | SB_RAM1024x4 family, SB_RAM2048x2 family |
| part-081-090 | 81-90 | SB_RAM2048x2NRNW, SB_RAM40_4K, SB_IO |
| part-091-100 | 91-100 | Pull-up config, SB_GB_IO, SB_GB, PLL intro, SB_PLL40_CORE, SB_PLL40_PAD |
| part-101-110 | 101-110 | SB_PLL40_PAD params, SB_PLL40_2_PAD, SB_PLL40_2F_CORE, SB_PLL40_2F_PAD start |
| part-111-120 | 111-120 | SB_PLL40_2F_PAD params, iCE40LM macros (SB_HSOSC, SB_LSOSC, SB_I2C, SB_SPI) |
| part-121-130 | 121-130 | iCE5LP macros (SB_HFOSC, SB_LFOSC, SB_LED_DRV_CUR, SB_RGB_DRV, SB_IR_DRV, SB_RGB_IP, SB_IO_OD, SB_I2C) |
| part-131-140 | 131-140 | SB_SPI, SB_MAC16 (ports, params, config tables) |
| part-141-150 | 141-150 | SB_MAC16 configs, iCE40UL macros start |
| part-151-160 | 151-160 | iCE40UL macros (SB_BARCODE_DRV, SB_IR500_DRV, SB_LEDDA_IP, SB_IR_IP, SB_IO_OD, SB_I2C_FIFO) |
| part-161-170 | 161-170 | iCE40UP macros (SB_HFOSC, SB_LFOSC, SB_RGBA_DRV, SB_LEDDA_IP, SB_IO_OD, SB_I2C) |
| part-171-180 | 171-180 | SB_SPI, SB_MAC16 ref, SB_SPRAM256KA, SB_IO_I3C, SB_WARMBOOT |
