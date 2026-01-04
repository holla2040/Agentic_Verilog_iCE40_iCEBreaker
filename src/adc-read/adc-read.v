// ============================================================================
// ADC Reader for PMOD AD1 (AD7476A)
// ============================================================================
//
// This module reads analog values from the AD7476A 12-bit ADC and sends
// the readings via UART to your PC 10 times per second.
//
// HARDWARE: PMOD AD1 (Digilent) connected to iCEBreaker PMOD1B
//   - Contains two AD7476A 12-bit ADCs (we use channel 0)
//   - Supply voltage (3.3V) serves as reference, so input range is 0-3.3V
//   - SPI-like interface: CS (chip select), SCLK (clock), SDATA (data out)
//
// AD7476A SPI PROTOCOL (READ operation):
// --------------------------------------
// Unlike the DAC which receives data, the ADC sends data TO the FPGA.
//
//   CS  ‾‾‾|___________________________________|‾‾‾
//   SCLK   ‾‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾‾
//   SDATA  ---<Z0><Z1><Z2><Z3><D11><D10>...<D0>---
//             (16 bits total: 4 zeros + 12 data bits)
//
//   - Falling edge of CS starts conversion and samples the analog input
//   - ADC clocks out data on FALLING edges of SCLK
//   - Data format: [0][0][0][0][DB11][DB10]...[DB1][DB0]
//   - 16 SCLK cycles needed for full conversion
//   - CS goes HIGH to end transfer
//
// TIMING (12 MHz system clock):
//   - SPI clock: 6 MHz (divide by 2)
//   - Conversion time: 16 bits * 2 clocks = 32 clocks ≈ 2.67 µs
//   - Sample rate: 10 Hz (100ms intervals)
//
// OUTPUT FORMAT (UART at 115200 baud):
//   0x0FFF
//   0x0800
//   0x0000
//
// ============================================================================

module adc_read (
    input  wire clk,           // 12 MHz system clock

    // ADC SPI interface (directly PMOD1B)
    output reg  adc_cs_n,      // Chip select (active LOW)
    input  wire adc_sdata,     // Serial data FROM ADC (MISO)
    output reg  adc_sclk,      // SPI clock to ADC

    // UART output
    output reg  uart_tx        // UART transmit pin
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================

    // SPI timing (12 MHz clock, 6 MHz SPI)
    localparam SPI_HALF_PERIOD = 1;     // Toggle every clock = 6 MHz SPI

    // UART timing (115200 baud)
    // 12 MHz / 115200 = 104.166... ≈ 104 clocks per bit
    localparam CLOCKS_PER_BIT = 104;

    // Sample interval timer (10 Hz = 100ms intervals)
    localparam CLOCKS_PER_INTERVAL = 1200000;  // 12 MHz / 10 = 100ms

    // ========================================================================
    // ADC STATE MACHINE
    // ========================================================================
    //
    // States for reading from the AD7476A:
    //   IDLE  → Wait for sample trigger
    //   START → Assert CS low, prepare for clocking
    //   SHIFT → Clock in 16 bits (4 zeros + 12 data)
    //   DONE  → CS high, store result, start UART transmission

    localparam ADC_IDLE  = 2'd0;
    localparam ADC_START = 2'd1;
    localparam ADC_SHIFT = 2'd2;
    localparam ADC_DONE  = 2'd3;

    reg [1:0] adc_state = ADC_IDLE;

    // ========================================================================
    // UART STATE MACHINE
    // ========================================================================
    //
    // States for transmitting via UART:
    //   IDLE  → Waiting for data to send
    //   START → Send start bit (LOW)
    //   DATA  → Send 8 data bits (LSB first)
    //   STOP  → Send stop bit (HIGH)

    localparam UART_IDLE  = 2'd0;
    localparam UART_START = 2'd1;
    localparam UART_DATA  = 2'd2;
    localparam UART_STOP  = 2'd3;

    reg [1:0] uart_state = UART_IDLE;

    // ========================================================================
    // REGISTERS
    // ========================================================================

    // Sample interval timer
    reg [20:0] interval_counter = 0;  // 21 bits for 1.2M count
    reg        sample_trigger = 0;

    // ADC SPI controller
    reg [15:0] adc_shift_reg = 0;       // Shift register for incoming data
    reg [4:0]  adc_bit_count = 0;       // Count of bits received (0-15)
    reg        sclk_phase = 0;          // Track SCLK phase (0=low half, 1=high half)
    reg [11:0] adc_result = 0;          // Stored 12-bit ADC result

    // UART transmitter
    reg [7:0]  uart_tx_byte = 0;        // Current byte being transmitted
    reg [6:0]  uart_baud_counter = 0;   // Baud rate counter
    reg [2:0]  uart_bit_index = 0;      // Which bit we're sending (0-7)
    reg [3:0]  uart_char_index = 0;     // Which character in message (0-7)

    // Handshake between ADC and UART state machines
    reg        uart_start_request = 0;  // ADC sets this to request UART send
    reg        uart_busy = 0;           // UART sets this while transmitting

    // Message buffer for hex output: "0xHHHH\r\n" = 8 characters
    // We build this from the ADC result
    reg [7:0] message [0:7];

    // ========================================================================
    // HEX DIGIT TO ASCII CONVERSION
    // ========================================================================
    //
    // Function to convert a 4-bit value to ASCII hex character:
    //   0-9 → '0'-'9' (0x30-0x39)
    //   A-F → 'A'-'F' (0x41-0x46)

    function [7:0] hex_to_ascii;
        input [3:0] nibble;
        begin
            if (nibble < 10)
                hex_to_ascii = 8'h30 + nibble;  // '0' + value
            else
                hex_to_ascii = 8'h41 + (nibble - 10);  // 'A' + (value - 10)
        end
    endfunction

    // ========================================================================
    // SAMPLE INTERVAL TIMER (10 Hz)
    // ========================================================================
    //
    // Generates a single-clock pulse every 100ms to trigger ADC sampling.

    always @(posedge clk) begin
        if (interval_counter == CLOCKS_PER_INTERVAL - 1) begin
            interval_counter <= 0;
            // Only trigger if not already busy
            if (adc_state == ADC_IDLE && !uart_busy) begin
                sample_trigger <= 1;
            end
        end else begin
            interval_counter <= interval_counter + 1;
            sample_trigger <= 0;
        end
    end

    // ========================================================================
    // ADC SPI STATE MACHINE
    // ========================================================================
    //
    // Reads 16 bits from the AD7476A:
    //   - Assert CS low to start conversion
    //   - Toggle SCLK 16 times
    //   - Sample SDATA on rising edge (data valid after falling edge)
    //   - Release CS high when done

    always @(posedge clk) begin
        case (adc_state)
            // ----------------------------------------------------------------
            // IDLE: Wait for sample trigger
            // ----------------------------------------------------------------
            ADC_IDLE: begin
                adc_cs_n <= 1'b1;        // CS high (inactive)
                adc_sclk <= 1'b1;        // SCLK idles high
                sclk_phase <= 0;

                // Clear the start request once UART acknowledges (goes busy)
                if (uart_busy) begin
                    uart_start_request <= 0;
                end

                if (sample_trigger) begin
                    adc_state <= ADC_START;
                end
            end

            // ----------------------------------------------------------------
            // START: Assert CS low to begin conversion
            // ----------------------------------------------------------------
            // The AD7476A samples its analog input on the falling edge of CS.
            // We also initialize the shift register and bit counter here.
            ADC_START: begin
                adc_cs_n <= 1'b0;        // Assert CS low - starts conversion
                adc_sclk <= 1'b1;        // SCLK starts high
                adc_shift_reg <= 16'd0;
                adc_bit_count <= 5'd0;
                sclk_phase <= 0;
                adc_state <= ADC_SHIFT;
            end

            // ----------------------------------------------------------------
            // SHIFT: Clock in 16 bits from ADC
            // ----------------------------------------------------------------
            // The AD7476A outputs data on the FALLING edge of SCLK.
            // We sample the data on the RISING edge (after it's stable).
            //
            // Phase 0: SCLK goes LOW (ADC outputs next bit)
            // Phase 1: SCLK goes HIGH (we sample SDATA)
            ADC_SHIFT: begin
                if (sclk_phase == 0) begin
                    // Falling edge - ADC clocks out data
                    adc_sclk <= 1'b0;
                    sclk_phase <= 1;
                end else begin
                    // Rising edge - we sample the data
                    adc_sclk <= 1'b1;
                    adc_shift_reg <= {adc_shift_reg[14:0], adc_sdata};
                    sclk_phase <= 0;

                    if (adc_bit_count == 5'd15) begin
                        // All 16 bits received
                        adc_state <= ADC_DONE;
                    end else begin
                        adc_bit_count <= adc_bit_count + 1;
                    end
                end
            end

            // ----------------------------------------------------------------
            // DONE: Store result and trigger UART transmission
            // ----------------------------------------------------------------
            // Note: Due to SPI timing, we capture bits 1-16 instead of 0-15.
            // The first bit (output when CS falls) is missed because we
            // create a falling edge before sampling. To compensate, we
            // extract bits [12:1] instead of [11:0].
            ADC_DONE: begin
                adc_cs_n <= 1'b1;        // Release CS high

                // Extract 12-bit result (shifted by 1 to compensate for timing)
                adc_result <= adc_shift_reg[12:1];

                // Build the message: "0xHHHH\r\n"
                message[0] <= "0";
                message[1] <= "x";
                message[2] <= hex_to_ascii(adc_shift_reg[12:9]);
                message[3] <= hex_to_ascii(adc_shift_reg[8:5]);
                message[4] <= hex_to_ascii(adc_shift_reg[4:1]);
                message[5] <= 8'h0D;     // \r (carriage return)
                message[6] <= 8'h0A;     // \n (newline)
                message[7] <= 8'h00;     // Unused

                // Request UART transmission (handshake signal)
                uart_start_request <= 1;

                adc_state <= ADC_IDLE;
            end

            default: begin
                adc_state <= ADC_IDLE;
            end
        endcase
    end

    // ========================================================================
    // UART TRANSMITTER STATE MACHINE
    // ========================================================================
    //
    // Sends the message buffer via UART at 115200 baud.
    // Message format: "0xHHH\r\n" (7 characters)

    localparam MSG_LEN = 7;  // "0xHHH\r\n" but only 5 hex digits? No, 4 hex + 0x prefix

    always @(posedge clk) begin
        case (uart_state)
            // ----------------------------------------------------------------
            // IDLE: Wait for transmission request
            // ----------------------------------------------------------------
            UART_IDLE: begin
                uart_tx <= 1'b1;         // UART idle is HIGH
                uart_baud_counter <= 0;
                uart_bit_index <= 0;
                uart_busy <= 0;

                if (uart_start_request) begin
                    // Load first character and start
                    uart_tx_byte <= message[0];
                    uart_char_index <= 0;
                    uart_busy <= 1;
                    uart_state <= UART_START;
                end
            end

            // ----------------------------------------------------------------
            // START: Send start bit (LOW) for one bit period
            // ----------------------------------------------------------------
            UART_START: begin
                uart_tx <= 1'b0;         // Start bit is LOW

                if (uart_baud_counter == CLOCKS_PER_BIT - 1) begin
                    uart_baud_counter <= 0;
                    uart_state <= UART_DATA;
                end else begin
                    uart_baud_counter <= uart_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DATA: Send 8 data bits, LSB first
            // ----------------------------------------------------------------
            UART_DATA: begin
                uart_tx <= uart_tx_byte[0];  // Send LSB

                if (uart_baud_counter == CLOCKS_PER_BIT - 1) begin
                    uart_baud_counter <= 0;

                    if (uart_bit_index == 7) begin
                        // All 8 bits sent
                        uart_bit_index <= 0;
                        uart_state <= UART_STOP;
                    end else begin
                        uart_bit_index <= uart_bit_index + 1;
                        uart_tx_byte <= uart_tx_byte >> 1;
                    end
                end else begin
                    uart_baud_counter <= uart_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // STOP: Send stop bit (HIGH) for one bit period
            // ----------------------------------------------------------------
            UART_STOP: begin
                uart_tx <= 1'b1;         // Stop bit is HIGH

                if (uart_baud_counter == CLOCKS_PER_BIT - 1) begin
                    uart_baud_counter <= 0;

                    if (uart_char_index == MSG_LEN - 1) begin
                        // All characters sent
                        uart_busy <= 0;
                        uart_state <= UART_IDLE;
                    end else begin
                        // Load next character
                        uart_char_index <= uart_char_index + 1;
                        uart_tx_byte <= message[uart_char_index + 1];
                        uart_state <= UART_START;
                    end
                end else begin
                    uart_baud_counter <= uart_baud_counter + 1;
                end
            end

            default: begin
                uart_state <= UART_IDLE;
                uart_tx <= 1'b1;
            end
        endcase
    end

endmodule

// ============================================================================
// HOW TO TEST THIS PROJECT:
// ============================================================================
//
// 1. Build the project:
//      make
//
// 2. Program the FPGA:
//      make prog
//
// 3. Connect your PMOD AD1 to PMOD1B on the iCEBreaker
//    Apply an analog signal (0-3.3V) to the A0 input on the PMOD AD1
//
// 4. Open a terminal program at 115200 baud:
//      screen /dev/ttyUSB1 115200
//
// 5. You should see hex values like "0x0800" appearing every second
//    - 0x000 = 0V input
//    - 0x800 = ~1.65V input (half scale)
//    - 0xFFF = 3.3V input (full scale)
//
// TESTING WITHOUT A SIGNAL SOURCE:
// - Leave input floating: you'll see noise (random values)
// - Connect A0 to GND on the PMOD: should read ~0x000
// - Connect A0 to VCC (3.3V) on the PMOD: should read ~0xFFF
//
// ============================================================================
