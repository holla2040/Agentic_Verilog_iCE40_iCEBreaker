// ============================================================================
// DAC-ADC Loopback - Phase 2: DAC + ADC
// ============================================================================
//
// This module generates a slow triangle wave on the PMOD DA2's DAC output
// and reads it back via the PMOD AD1's ADC at 10 Hz.
//
// HARDWARE:
//   - PMOD DA2 (Digilent) on PMOD1A - DAC121S101 12-bit DAC
//   - PMOD AD1 (Digilent) on PMOD1B - AD7476A 12-bit ADC
//   - Physical wire connecting DAC output to ADC input
//
// DAC121S101 SPI PROTOCOL (write):
//   - Data clocked into DAC on FALLING edges of SCLK
//   - 16 bits: [X][X][PD1][PD0][D11][D10]...[D1][D0]
//
// AD7476A SPI PROTOCOL (read):
//   - CS falling edge starts conversion
//   - Data clocked out on FALLING edges of SCLK
//   - 16 bits: [0][0][0][0][DB11][DB10]...[DB1][DB0]
//
// TIMING (12 MHz system clock, NO PLL):
//   - SPI clock: 6 MHz (12 MHz / 2)
//   - DAC: Triangle wave 0-4095-0 over 60 seconds
//   - ADC: Samples at 10 Hz (every 100ms)
//
// ============================================================================

module dac_adc_loopback (
    input  wire clk,           // 12 MHz system clock

    // DAC SPI interface (PMOD DA2 on PMOD1A)
    output reg  dac_sync_n,    // Chip select (active LOW)
    output reg  dac_din,       // Serial data out
    output reg  dac_sclk,      // SPI clock

    // ADC SPI interface (PMOD AD1 on PMOD1B)
    output reg  adc_cs_n,      // Chip select (active LOW)
    input  wire adc_sdata,     // Serial data FROM ADC (MISO)
    output reg  adc_sclk,      // SPI clock to ADC

    // UART output
    output reg  uart_tx        // UART transmit pin
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    //
    // Triangle wave timing:
    //   - 30 seconds to ramp up (0 to 4095)
    //   - 30 seconds to ramp down (4095 to 0)
    //   - 60 seconds total cycle
    //
    // Clocks per DAC step:
    //   12,000,000 Hz * 30 sec / 4096 steps = 87,890.625
    //   We use 87,891 clocks per step (30.0003 seconds per ramp direction)
    //
    // Counter needs 17 bits: 2^17 = 131,072 > 87,891

    localparam CLOCKS_PER_STEP = 17'd87891;  // ~30 seconds per 4096 steps
    localparam SPI_HALF_PERIOD = 1;          // Toggle every clock = 6 MHz SPI

    // ADC sample interval (10 Hz = 100ms = 1,200,000 clocks)
    localparam CLOCKS_PER_INTERVAL = 21'd1200000;

    // UART timing (115200 baud)
    // 12 MHz / 115200 = 104.166... ≈ 104 clocks per bit
    localparam CLOCKS_PER_BIT = 104;

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // The SPI controller uses a simple state machine:
    //   IDLE:  SYNC high, wait briefly
    //   LOAD:  Prepare shift register, assert SYNC low
    //   SHIFT: Clock out 16 bits on falling SCLK edges
    //   DONE:  Release SYNC high

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_LOAD  = 2'd1;
    localparam STATE_SHIFT = 2'd2;
    localparam STATE_DONE  = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // ADC STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // States for reading from the AD7476A:
    //   IDLE  → Wait for sample trigger
    //   START → Assert CS low, prepare for clocking
    //   SHIFT → Clock in 16 bits (4 zeros + 12 data)
    //   DONE  → CS high, store result

    localparam ADC_IDLE  = 2'd0;
    localparam ADC_START = 2'd1;
    localparam ADC_SHIFT = 2'd2;
    localparam ADC_DONE  = 2'd3;

    reg [1:0] adc_state = ADC_IDLE;

    // ========================================================================
    // UART STATE MACHINE DEFINITIONS
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

    // Triangle wave generator (updated by step timer, not SPI transfers)
    reg [11:0] dac_value = 12'd0;        // Current DAC value (0-4095)
    reg        ramp_direction = 1'b1;    // 1 = counting up, 0 = counting down

    // Step timer - controls how often dac_value changes
    reg [16:0] step_timer = 17'd0;       // Counts clocks between DAC value changes

    // DAC SPI controller
    reg [15:0] shift_reg = 16'd0;        // 16-bit shift register for SPI data
    reg [3:0]  bit_count = 4'd0;         // Count of bits shifted (0-15)
    reg [3:0]  clk_div = 4'd0;           // Clock divider counter

    // ADC sample interval timer
    reg [20:0] interval_counter = 21'd0; // 21 bits for 1.2M count
    reg        sample_trigger = 1'b0;    // Pulse to start ADC read

    // ADC SPI controller
    reg [15:0] adc_shift_reg = 16'd0;    // Shift register for incoming data
    reg [4:0]  adc_bit_count = 5'd0;     // Count of bits received (0-15)
    reg        adc_sclk_phase = 1'b0;    // Track SCLK phase
    reg [11:0] adc_result = 12'd0;       // Stored 12-bit ADC result

    // UART transmitter
    reg [7:0]  uart_tx_byte = 8'd0;      // Current byte being transmitted
    reg [6:0]  uart_baud_counter = 7'd0; // Baud rate counter
    reg [2:0]  uart_bit_index = 3'd0;    // Which bit we're sending (0-7)
    reg [2:0]  uart_char_index = 3'd0;   // Which character in message (0-6)

    // Handshake between ADC and UART state machines
    reg        uart_start_request = 1'b0; // ADC sets this to request UART send
    reg        uart_busy = 1'b0;          // UART sets this while transmitting

    // Message buffer for hex output: "0xNNN\r\n" = 7 characters
    reg [7:0] message [0:6];

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
    // STEP TIMER - Controls triangle wave speed
    // ========================================================================
    //
    // This timer runs independently of the SPI state machine.
    // Every 87,891 clock cycles, the DAC value increments or decrements.
    // The SPI controller continuously sends the current dac_value to the DAC.

    always @(posedge clk) begin
        if (step_timer == CLOCKS_PER_STEP - 1) begin
            step_timer <= 17'd0;

            // Update DAC value based on direction
            if (ramp_direction) begin
                // Counting up
                if (dac_value == 12'd4095) begin
                    ramp_direction <= 1'b0;  // Switch to counting down
                    dac_value <= 12'd4094;
                end else begin
                    dac_value <= dac_value + 1'b1;
                end
            end else begin
                // Counting down
                if (dac_value == 12'd0) begin
                    ramp_direction <= 1'b1;  // Switch to counting up
                    dac_value <= 12'd1;
                end else begin
                    dac_value <= dac_value - 1'b1;
                end
            end
        end else begin
            step_timer <= step_timer + 1'b1;
        end
    end

    // ========================================================================
    // SPI STATE MACHINE - Continuously sends dac_value to DAC
    // ========================================================================
    //
    // This runs as fast as possible (6 MHz SPI), continuously updating the DAC
    // with whatever value is currently in dac_value. The actual value only
    // changes every 87,891 clocks via the step timer above.

    always @(posedge clk) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE STATE: Brief pause, then start next transfer
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                dac_sync_n <= 1'b1;      // SYNC high (inactive)
                dac_sclk <= 1'b1;        // SCLK idles high
                state <= STATE_LOAD;     // Go to next transfer
            end

            // ----------------------------------------------------------------
            // LOAD STATE: Prepare shift register and assert SYNC low
            // ----------------------------------------------------------------
            STATE_LOAD: begin
                // Build the 16-bit SPI word
                // Bits 15-12: 0000 (don't care + normal mode)
                // Bits 11-0: DAC value
                shift_reg <= {4'b0000, dac_value};

                bit_count <= 4'd0;
                clk_div <= 4'd0;
                dac_sync_n <= 1'b0;      // Assert SYNC low to start transfer
                dac_sclk <= 1'b1;        // Clock starts high
                dac_din <= 1'b0;

                state <= STATE_SHIFT;
            end

            // ----------------------------------------------------------------
            // SHIFT STATE: Clock out 16 bits, data sampled on falling edge
            // ----------------------------------------------------------------
            STATE_SHIFT: begin
                if (clk_div == SPI_HALF_PERIOD - 1) begin
                    clk_div <= 4'd0;

                    if (dac_sclk == 1'b1) begin
                        // Falling edge of SCLK - data is captured by DAC
                        dac_sclk <= 1'b0;
                    end else begin
                        // Rising edge of SCLK - advance to next bit
                        dac_sclk <= 1'b1;

                        if (bit_count == 4'd15) begin
                            // All 16 bits sent, transfer complete
                            state <= STATE_DONE;
                        end else begin
                            // Shift to next bit (MSB first)
                            bit_count <= bit_count + 1'b1;
                            shift_reg <= {shift_reg[14:0], 1'b0};
                        end
                    end
                end else begin
                    clk_div <= clk_div + 1'b1;
                end

                // Output the MSB of shift register
                dac_din <= shift_reg[15];
            end

            // ----------------------------------------------------------------
            // DONE STATE: Release SYNC, go back to IDLE
            // ----------------------------------------------------------------
            STATE_DONE: begin
                dac_sync_n <= 1'b1;      // Release SYNC high
                dac_sclk <= 1'b1;        // SCLK returns to idle high
                state <= STATE_IDLE;
            end

            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end

    // ========================================================================
    // ADC SAMPLE INTERVAL TIMER (10 Hz)
    // ========================================================================
    //
    // Generates a single-clock pulse every 100ms to trigger ADC sampling.

    always @(posedge clk) begin
        if (interval_counter == CLOCKS_PER_INTERVAL - 1) begin
            interval_counter <= 21'd0;
            // Only trigger if ADC is idle and UART is not busy
            if (adc_state == ADC_IDLE && !uart_busy) begin
                sample_trigger <= 1'b1;
            end
        end else begin
            interval_counter <= interval_counter + 1'b1;
            sample_trigger <= 1'b0;
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
                adc_sclk_phase <= 1'b0;

                // Clear the start request once UART acknowledges (goes busy)
                if (uart_busy) begin
                    uart_start_request <= 1'b0;
                end

                if (sample_trigger) begin
                    adc_state <= ADC_START;
                end
            end

            // ----------------------------------------------------------------
            // START: Assert CS low to begin conversion
            // ----------------------------------------------------------------
            ADC_START: begin
                adc_cs_n <= 1'b0;        // Assert CS low - starts conversion
                adc_sclk <= 1'b1;        // SCLK starts high
                adc_shift_reg <= 16'd0;
                adc_bit_count <= 5'd0;
                adc_sclk_phase <= 1'b0;
                adc_state <= ADC_SHIFT;
            end

            // ----------------------------------------------------------------
            // SHIFT: Clock in 16 bits from ADC
            // ----------------------------------------------------------------
            // The AD7476A outputs data on the FALLING edge of SCLK.
            // We sample the data on the RISING edge (after it's stable).
            ADC_SHIFT: begin
                if (adc_sclk_phase == 1'b0) begin
                    // Falling edge - ADC clocks out data
                    adc_sclk <= 1'b0;
                    adc_sclk_phase <= 1'b1;
                end else begin
                    // Rising edge - we sample the data
                    adc_sclk <= 1'b1;
                    adc_shift_reg <= {adc_shift_reg[14:0], adc_sdata};
                    adc_sclk_phase <= 1'b0;

                    if (adc_bit_count == 5'd15) begin
                        // All 16 bits received
                        adc_state <= ADC_DONE;
                    end else begin
                        adc_bit_count <= adc_bit_count + 1'b1;
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

                // Build the message: "0xNNN\r\n"
                message[0] <= "0";
                message[1] <= "x";
                message[2] <= hex_to_ascii(adc_shift_reg[12:9]);
                message[3] <= hex_to_ascii(adc_shift_reg[8:5]);
                message[4] <= hex_to_ascii(adc_shift_reg[4:1]);
                message[5] <= 8'h0D;     // \r (carriage return)
                message[6] <= 8'h0A;     // \n (newline)

                // Request UART transmission
                uart_start_request <= 1'b1;

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
    // Message format: "0xNNN\r\n" (7 characters)

    localparam MSG_LEN = 7;

    always @(posedge clk) begin
        case (uart_state)
            // ----------------------------------------------------------------
            // IDLE: Wait for transmission request
            // ----------------------------------------------------------------
            UART_IDLE: begin
                uart_tx <= 1'b1;         // UART idle is HIGH
                uart_baud_counter <= 7'd0;
                uart_bit_index <= 3'd0;
                uart_busy <= 1'b0;

                if (uart_start_request) begin
                    // Load first character and start
                    uart_tx_byte <= message[0];
                    uart_char_index <= 3'd0;
                    uart_busy <= 1'b1;
                    uart_state <= UART_START;
                end
            end

            // ----------------------------------------------------------------
            // START: Send start bit (LOW) for one bit period
            // ----------------------------------------------------------------
            UART_START: begin
                uart_tx <= 1'b0;         // Start bit is LOW

                if (uart_baud_counter == CLOCKS_PER_BIT - 1) begin
                    uart_baud_counter <= 7'd0;
                    uart_state <= UART_DATA;
                end else begin
                    uart_baud_counter <= uart_baud_counter + 1'b1;
                end
            end

            // ----------------------------------------------------------------
            // DATA: Send 8 data bits, LSB first
            // ----------------------------------------------------------------
            UART_DATA: begin
                uart_tx <= uart_tx_byte[0];  // Send LSB

                if (uart_baud_counter == CLOCKS_PER_BIT - 1) begin
                    uart_baud_counter <= 7'd0;

                    if (uart_bit_index == 3'd7) begin
                        // All 8 bits sent
                        uart_bit_index <= 3'd0;
                        uart_state <= UART_STOP;
                    end else begin
                        uart_bit_index <= uart_bit_index + 1'b1;
                        uart_tx_byte <= uart_tx_byte >> 1;
                    end
                end else begin
                    uart_baud_counter <= uart_baud_counter + 1'b1;
                end
            end

            // ----------------------------------------------------------------
            // STOP: Send stop bit (HIGH) for one bit period
            // ----------------------------------------------------------------
            UART_STOP: begin
                uart_tx <= 1'b1;         // Stop bit is HIGH

                if (uart_baud_counter == CLOCKS_PER_BIT - 1) begin
                    uart_baud_counter <= 7'd0;

                    if (uart_char_index == MSG_LEN - 1) begin
                        // All characters sent
                        uart_busy <= 1'b0;
                        uart_state <= UART_IDLE;
                    end else begin
                        // Load next character
                        uart_char_index <= uart_char_index + 1'b1;
                        uart_tx_byte <= message[uart_char_index + 1];
                        uart_state <= UART_START;
                    end
                end else begin
                    uart_baud_counter <= uart_baud_counter + 1'b1;
                end
            end

            default: begin
                uart_state <= UART_IDLE;
                uart_tx <= 1'b1;
            end
        endcase
    end

endmodule
