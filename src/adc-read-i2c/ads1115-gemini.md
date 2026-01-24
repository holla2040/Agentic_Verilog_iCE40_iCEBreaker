# ADS1115 I2C ADC Reader - Project Review

This review evaluates the implementation of the ADS1115 16-bit I2C ADC reader project located in `/src/adc-read-i2c`.

## 1. Technical Implementation Review

The Verilog implementation is technically sound and follows best practices for low-level protocol implementation on iCE40 FPGAs.

### I2C Master (`i2c_master.v`)
*   **Open-Drain Logic**: The use of `SB_IO` primitives with `PIN_TYPE(6'b101001)` is the correct and robust way to implement open-drain I2C signals on the iCE40 UP5K. By fixing `D_OUT_0` to `0` and using the enable signal (`oe`) to drive the line, it strictly enforces the "drive low, release high" requirement of the I2C bus.
*   **State Machine**: The finite state machine (FSM) correctly decomposes I2C transactions into bit-level timing. It handles START, STOP, WRITE, and READ sequences with appropriate setup/hold times relative to the SCL clock.
*   **Timing**: The 100 kHz clock derivation (via `HALF_PERIOD` of 60 cycles at 12 MHz) is accurate for standard mode I2C.

### Top Level (`top.v`)
*   **Architecture**: The module orchestrates the `i2c_master` and `uart_tx` modules effectively. The main state machine clearly separates initialization, configuration, pointer setup, and the continuous read loop.
*   **ADS1115 Configuration**: The configuration word `0xC2C3` correctly sets up the device for single-ended reading (AIN0), +/-4.096V range, and continuous conversion mode.
*   **Read Sequence**: The implementation correctly separates the "Set Pointer" operation (write to address 0x00) from the "Read Data" loop. This is efficient as the pointer in the ADS1115 persists, allowing direct reads in the loop without re-sending the register address.
*   **Error Handling**: The inclusion of NACK detection (sending 'E' via UART) is a good practice for debugging hardware connectivity issues.
*   **Data Formatting**: The hex-to-ASCII conversion is implemented correctly and efficiently for reporting 16-bit values.

### UART Transmitter (`uart_tx.v`)
*   A standard, clean implementation of an 8N1 UART transmitter configured for 115200 baud.

### Constraints and Build (`icebreaker.pcf`, `Makefile`)
*   **Pin Constraints**: Assignments match the documented hardware setup (PMOD1A for I2C, Pin 20/2 for address selection via button).
*   **Build System**: The Makefile correctly leverages the open-source iCE40 toolchain (Yosys, nextpnr, icepack).

## 2. Documentation Review

The documentation is exceptional in its detail and utility.

*   **`README.md`**: Provides a clear high-level overview, pinout tables, wiring diagrams, and operational description. It effectively serves as a user manual.
*   **`PLAN.md`**: Demonstrates a methodical, step-by-step development approach (UART verify -> I2C Addr verify -> Full implementation). The inclusion of specific "STOP POINTS" ensures incremental verification.
*   **`ADC-READ-I2C.prd`**: Clearly defines the requirements and constraints that guided the implementation.

## 3. Conclusion and Recommendation

This project is in a **complete and high-quality state**. The code logic aligns perfectly with the documentation and standard protocols. It is a robust example of I2C peripheral integration on an FPGA.

**Recommendation**:
The project is ready for final deployment. No code changes are required based on this technical review.
