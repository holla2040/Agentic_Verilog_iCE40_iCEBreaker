// ============================================================================
// FREQUENCY COUNTER with Selectable Generator - iCEBreaker FPGA
// ============================================================================
//
// This project demonstrates two fundamental concepts:
//   1. FREQUENCY GENERATION: Creating precise clock signals from a master clock
//   2. FREQUENCY MEASUREMENT: Counting pulses over a known time period
//
// The design has two main sections:
//
//   GENERATOR SECTION:
//   - Creates a test signal at one of three frequencies
//   - Button 1: 500 kHz
//   - Button 2: 1 MHz
//   - Button 3: 2 MHz
//   - Default (no button): 500 kHz
//
//   COUNTER SECTION:
//   - Counts rising edges of the generated signal for exactly 1 second
//   - Sends the measured frequency over UART (115200 baud)
//   - Updates every second with a new measurement
//
// ============================================================================
// HOW FREQUENCY GENERATION WORKS
// ============================================================================
//
// To generate a lower frequency from a higher one, we use a CLOCK DIVIDER.
// The basic idea: toggle an output signal every N cycles of the input clock.
//
// Example: Generate 1 MHz from 12 MHz
//   - We need to divide by 12 (12 MHz / 1 MHz = 12)
//   - A square wave has two transitions per period (rising and falling)
//   - So we toggle the output every 6 clock cycles
//   - Result: 6 cycles HIGH, 6 cycles LOW = 12 cycles per period = 1 MHz
//
// Frequency formulas:
//   Output frequency = Input frequency / (2 * toggle_count)
//   Toggle count = Input frequency / (2 * Output frequency)
//
// For our frequencies with 12 MHz input:
//   500 kHz: toggle every 12 clocks (12M / 500k / 2 = 12)
//   1 MHz:   toggle every 6 clocks  (12M / 1M / 2 = 6)
//   2 MHz:   toggle every 3 clocks  (12M / 2M / 2 = 3)
//
// ============================================================================
// HOW FREQUENCY MEASUREMENT WORKS
// ============================================================================
//
// Frequency is defined as cycles per second. To measure it:
//   1. Create a precise 1-second time window
//   2. Count rising edges of the signal during that window
//   3. The count directly equals the frequency in Hz!
//
// This is called a RECIPROCAL FREQUENCY COUNTER because we're measuring
// the number of cycles in a fixed time, rather than measuring the time
// of a fixed number of cycles.
//
// Advantages:
//   - Simple to implement
//   - Accuracy improves with longer measurement windows
//   - Works well for frequencies above 1 Hz
//
// Disadvantages:
//   - Resolution is always 1 Hz with a 1-second window
//   - Low frequencies (< 1 Hz) read as 0 or 1
//
// ============================================================================

module freq_counter (
    input  wire clk,        // 12 MHz master clock
    input  wire btn1,       // Button 1: Select 500 kHz
    input  wire btn2,       // Button 2: Select 1 MHz
    input  wire btn3,       // Button 3: Select 2 MHz
    output reg  tx,         // UART transmit pin
    output wire freq_out,   // Generated frequency output (PMOD 1A pin 1)
    input  wire freq_in     // Frequency input to measure (PMOD 1A pin 7)
);

    // ========================================================================
    // CLOCK AND TIMING PARAMETERS
    // ========================================================================

    localparam CLOCK_FREQ = 12_000_000;        // 12 MHz master clock
    localparam CLOCKS_PER_SECOND = 12_000_000; // Gate time for measurement

    // Divider values to toggle output (half-period counts)
    // These create the frequencies by toggling at specific intervals
    localparam DIV_500KHZ = 12;  // 12 MHz / (2 * 12) = 500 kHz
    localparam DIV_1MHZ   = 6;   // 12 MHz / (2 * 6)  = 1 MHz
    localparam DIV_2MHZ   = 3;   // 12 MHz / (2 * 3)  = 2 MHz

    // UART timing: 115200 baud
    localparam CLOCKS_PER_BIT = 104;  // 12 MHz / 115200 = 104

    // ========================================================================
    // BUTTON SYNCHRONIZATION
    // ========================================================================
    //
    // External signals (like button presses) are asynchronous to our clock.
    // They could change at any time, potentially causing METASTABILITY.
    //
    // Metastability: When a flip-flop samples a signal exactly as it's
    // changing, the output can become undefined (neither 0 nor 1) for
    // an unpredictable amount of time.
    //
    // Solution: Pass external signals through TWO flip-flops (a synchronizer).
    // This gives the first flip-flop time to settle before the second samples.

    reg btn1_sync_0, btn1_sync_1;
    reg btn2_sync_0, btn2_sync_1;
    reg btn3_sync_0, btn3_sync_1;

    always @(posedge clk) begin
        // Two-stage synchronizer for each button
        btn1_sync_0 <= btn1;
        btn1_sync_1 <= btn1_sync_0;

        btn2_sync_0 <= btn2;
        btn2_sync_1 <= btn2_sync_0;

        btn3_sync_0 <= btn3;
        btn3_sync_1 <= btn3_sync_0;
    end

    // Use the synchronized button values
    wire btn1_pressed = btn1_sync_1;
    wire btn2_pressed = btn2_sync_1;
    wire btn3_pressed = btn3_sync_1;

    // ========================================================================
    // FREQUENCY SELECTION LOGIC
    // ========================================================================
    //
    // Based on which button is pressed, select the appropriate divider value.
    // Priority: btn3 > btn2 > btn1 > default

    reg [3:0] divider_value;  // Current half-period count

    always @(posedge clk) begin
        if (btn3_pressed)
            divider_value <= DIV_2MHZ;    // 2 MHz
        else if (btn2_pressed)
            divider_value <= DIV_1MHZ;    // 1 MHz
        else if (btn1_pressed)
            divider_value <= DIV_500KHZ;  // 500 kHz
        else
            divider_value <= DIV_500KHZ;  // Default: 500 kHz
    end

    // ========================================================================
    // FREQUENCY GENERATOR (Clock Divider)
    // ========================================================================
    //
    // This section generates the test signal that we'll measure.
    // It counts clock cycles and toggles the output at the selected rate.

    reg [3:0]  gen_counter = 0;   // Counts up to divider_value - 1
    reg        gen_signal = 0;    // The generated frequency signal

    always @(posedge clk) begin
        if (gen_counter >= divider_value - 1) begin
            gen_counter <= 0;
            gen_signal <= ~gen_signal;  // Toggle the output
        end else begin
            gen_counter <= gen_counter + 1;
        end
    end

    // Output the generated signal on the external pin
    assign freq_out = gen_signal;

    // ========================================================================
    // 1-SECOND GATE TIMER
    // ========================================================================
    //
    // This counter creates the precise 1-second measurement window.
    // At the end of each second, it pulses 'gate_done' and resets.

    reg [23:0] gate_counter = 0;  // Counts 0 to 11,999,999 (12 million - 1)
    reg        gate_done = 0;     // Pulses HIGH for one clock each second

    always @(posedge clk) begin
        if (gate_counter == CLOCKS_PER_SECOND - 1) begin
            gate_counter <= 0;
            gate_done <= 1;
        end else begin
            gate_counter <= gate_counter + 1;
            gate_done <= 0;
        end
    end

    // ========================================================================
    // INPUT SIGNAL SYNCHRONIZATION
    // ========================================================================
    //
    // The frequency input comes from an external source (PMOD pin).
    // We must synchronize it to our clock domain to prevent metastability.
    // This adds a 2-cycle delay but ensures reliable operation.

    reg freq_in_sync_0 = 0;
    reg freq_in_sync_1 = 0;

    always @(posedge clk) begin
        freq_in_sync_0 <= freq_in;
        freq_in_sync_1 <= freq_in_sync_0;
    end

    wire freq_in_synced = freq_in_sync_1;

    // ========================================================================
    // EDGE DETECTOR for Input Signal
    // ========================================================================
    //
    // We need to count RISING EDGES of freq_in, not just when it's HIGH.
    // An edge detector compares the current value to the previous value:
    //   Rising edge: previous=0, current=1

    reg freq_in_prev = 0;
    wire rising_edge = (freq_in_synced == 1) && (freq_in_prev == 0);

    always @(posedge clk) begin
        freq_in_prev <= freq_in_synced;
    end

    // ========================================================================
    // FREQUENCY COUNTER
    // ========================================================================
    //
    // This counter accumulates rising edges during the 1-second gate period.
    // When gate_done pulses:
    //   1. Latch the current count to freq_result (for UART transmission)
    //   2. Reset the counter for the next measurement

    reg [23:0] freq_counter = 0;  // Current count (can count up to 16 million)
    reg [23:0] freq_result = 0;   // Latched result for display

    always @(posedge clk) begin
        if (gate_done) begin
            // End of measurement window
            freq_result <= freq_counter;  // Save the result
            freq_counter <= 0;            // Reset for next measurement
        end else begin
            if (rising_edge) begin
                freq_counter <= freq_counter + 1;
            end
        end
    end

    // ========================================================================
    // UART TRANSMITTER
    // ========================================================================
    //
    // When a new measurement is ready, we convert the frequency count to
    // ASCII decimal digits and send them over UART.
    //
    // Message format: "1000000 Hz\r\n"
    //
    // The conversion from binary to decimal ASCII is done digit by digit,
    // starting from the most significant digit.

    // UART transmitter states
    localparam TX_IDLE     = 3'd0;  // Waiting for new measurement
    localparam TX_CONVERT  = 3'd1;  // Converting binary to decimal
    localparam TX_START    = 3'd2;  // Sending start bit
    localparam TX_DATA     = 3'd3;  // Sending data bits
    localparam TX_STOP     = 3'd4;  // Sending stop bit
    localparam TX_NEXT     = 3'd5;  // Move to next character

    reg [2:0]  tx_state = TX_IDLE;
    reg [6:0]  tx_baud_counter = 0;
    reg [2:0]  tx_bit_index = 0;
    reg [7:0]  tx_shift_reg = 0;

    // Message buffer: up to 8 digits + " Hz\r\n" = 13 characters max
    // We'll build the message dynamically based on the frequency value
    reg [7:0]  tx_buffer [0:15];   // Character buffer
    reg [3:0]  tx_char_index = 0;  // Current character being sent
    reg [3:0]  tx_msg_len = 0;     // Total message length

    // Binary to decimal conversion registers
    reg [23:0] convert_value = 0;  // Value being converted
    reg [3:0]  digit_index = 0;    // Which digit we're extracting
    reg        leading_zero = 1;   // Skip leading zeros

    // Trigger transmission when measurement is ready
    reg gate_done_prev = 0;
    wire new_measurement = gate_done && !gate_done_prev;

    always @(posedge clk) begin
        gate_done_prev <= gate_done;
    end

    // ========================================================================
    // BINARY TO DECIMAL CONVERSION
    // ========================================================================
    //
    // Converting binary to decimal ASCII is non-trivial in hardware.
    // We use repeated subtraction: find how many times each power of 10
    // fits into the remaining value.
    //
    // For up to 8 digits (0-99,999,999), we need divisors:
    //   10,000,000 / 1,000,000 / 100,000 / 10,000 / 1,000 / 100 / 10 / 1
    //
    // This implementation uses a lookup table for divisors.

    // Divisor lookup table (powers of 10, largest first)
    wire [23:0] divisors [0:7];
    assign divisors[0] = 24'd10000000;  // 10 million
    assign divisors[1] = 24'd1000000;   // 1 million
    assign divisors[2] = 24'd100000;    // 100 thousand
    assign divisors[3] = 24'd10000;     // 10 thousand
    assign divisors[4] = 24'd1000;      // 1 thousand
    assign divisors[5] = 24'd100;       // 100
    assign divisors[6] = 24'd10;        // 10
    assign divisors[7] = 24'd1;         // 1

    // Current divisor for conversion
    wire [23:0] current_divisor = divisors[digit_index];

    // Digit extraction: count subtractions
    reg [3:0] current_digit = 0;

    // Suffix characters: " Hz\r\n"
    localparam SUFFIX_LEN = 5;

    // ========================================================================
    // UART STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        case (tx_state)
            // ----------------------------------------------------------------
            // TX_IDLE: Wait for a new measurement
            // ----------------------------------------------------------------
            TX_IDLE: begin
                tx <= 1;  // UART idle is HIGH
                tx_baud_counter <= 0;
                tx_bit_index <= 0;
                tx_char_index <= 0;
                tx_msg_len <= 0;
                digit_index <= 0;
                current_digit <= 0;
                leading_zero <= 1;

                if (new_measurement) begin
                    // Start converting the new frequency value
                    convert_value <= freq_result;
                    tx_state <= TX_CONVERT;
                end
            end

            // ----------------------------------------------------------------
            // TX_CONVERT: Extract decimal digits from binary value
            // ----------------------------------------------------------------
            //
            // This state repeatedly subtracts the current divisor until
            // the value goes below zero, counting the subtractions.
            // That count is the current decimal digit.
            //
            TX_CONVERT: begin
                if (digit_index < 8) begin
                    // Still extracting digits
                    if (convert_value >= current_divisor) begin
                        // Can subtract more
                        convert_value <= convert_value - current_divisor;
                        current_digit <= current_digit + 1;
                    end else begin
                        // Done with this digit position
                        // Store digit if non-zero or we've seen a non-zero
                        if (current_digit != 0 || !leading_zero || digit_index == 7) begin
                            // Store ASCII digit ('0' = 0x30)
                            tx_buffer[tx_msg_len] <= 8'h30 + current_digit;
                            tx_msg_len <= tx_msg_len + 1;
                            leading_zero <= 0;  // Found first non-zero digit
                        end

                        // Move to next digit position
                        digit_index <= digit_index + 1;
                        current_digit <= 0;
                    end
                end else begin
                    // All digits extracted, add suffix " Hz\r\n"
                    tx_buffer[tx_msg_len + 0] <= " ";      // Space
                    tx_buffer[tx_msg_len + 1] <= "H";      // H
                    tx_buffer[tx_msg_len + 2] <= "z";      // z
                    tx_buffer[tx_msg_len + 3] <= 8'h0D;    // CR
                    tx_buffer[tx_msg_len + 4] <= 8'h0A;    // LF
                    tx_msg_len <= tx_msg_len + SUFFIX_LEN;

                    // Start transmitting
                    tx_char_index <= 0;
                    tx_shift_reg <= tx_buffer[0];
                    tx_state <= TX_START;
                end
            end

            // ----------------------------------------------------------------
            // TX_START: Send start bit (LOW)
            // ----------------------------------------------------------------
            TX_START: begin
                tx <= 0;  // Start bit

                if (tx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    tx_baud_counter <= 0;
                    tx_state <= TX_DATA;
                    tx_shift_reg <= tx_buffer[tx_char_index];
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // TX_DATA: Send 8 data bits (LSB first)
            // ----------------------------------------------------------------
            TX_DATA: begin
                tx <= tx_shift_reg[0];

                if (tx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    tx_baud_counter <= 0;

                    if (tx_bit_index == 7) begin
                        tx_bit_index <= 0;
                        tx_state <= TX_STOP;
                    end else begin
                        tx_bit_index <= tx_bit_index + 1;
                        tx_shift_reg <= tx_shift_reg >> 1;
                    end
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // TX_STOP: Send stop bit (HIGH)
            // ----------------------------------------------------------------
            TX_STOP: begin
                tx <= 1;  // Stop bit

                if (tx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    tx_baud_counter <= 0;
                    tx_state <= TX_NEXT;
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // TX_NEXT: Move to next character or finish
            // ----------------------------------------------------------------
            TX_NEXT: begin
                if (tx_char_index == tx_msg_len - 1) begin
                    // All characters sent
                    tx_state <= TX_IDLE;
                end else begin
                    // More characters to send
                    tx_char_index <= tx_char_index + 1;
                    tx_shift_reg <= tx_buffer[tx_char_index + 1];
                    tx_state <= TX_START;
                end
            end

            default: begin
                tx_state <= TX_IDLE;
                tx <= 1;
            end
        endcase
    end

endmodule

// ============================================================================
// HOW TO TEST THIS PROJECT
// ============================================================================
//
// 1. Build the project:
//      cd src/freq-counter
//      make
//
// 2. Program the FPGA:
//      make prog
//
// 3. Connect PMOD 1A pin 1 (output) to PMOD 1A pin 7 (input) with a jumper wire.
//    This creates a loopback so the counter measures the generator.
//
//    PMOD 1A pinout:
//      Pin 1 = freq_out (generator output)
//      Pin 7 = freq_in  (counter input)
//      Pin 5 = GND
//      Pin 6 = VCC (3.3V)
//
// 4. Connect to UART (115200 baud):
//      screen /dev/ttyUSB1 115200
//    or:
//      picocom -b 115200 /dev/ttyUSB1
//
// 5. You should see frequency measurements every second:
//      500000 Hz
//      500000 Hz
//      ...
//
// 6. Press buttons to change the generated frequency:
//      Button 1: 500000 Hz (500 kHz)
//      Button 2: 1000000 Hz (1 MHz)
//      Button 3: 2000000 Hz (2 MHz)
//
// 7. To measure an EXTERNAL signal:
//    - Disconnect the loopback wire
//    - Connect your signal source to PMOD 1A pin 7
//    - Make sure the signal is 3.3V logic levels!
//    - The counter will measure whatever frequency is on that pin
//
// 8. To exit screen: Ctrl+A, K, Y
//    To exit picocom: Ctrl+A, Ctrl+X
//
// ============================================================================
// LEARNING EXERCISES
// ============================================================================
//
// 1. ADD MORE FREQUENCIES:
//    Calculate the divider values for other frequencies like 100 kHz or 250 kHz.
//    Add more buttons or use a switch to select between more options.
//
// 2. LONGER GATE TIME:
//    Try a 10-second measurement window for higher resolution (0.1 Hz).
//    Divide the final count by 10 before displaying.
//
// 3. EXTERNAL INPUT:
//    Instead of measuring the internal generator, measure an external signal
//    connected to a PMOD pin. Be sure to synchronize the input!
//
// 4. FREQUENCY RANGE:
//    Add auto-ranging: display in kHz or MHz when the value is large.
//    "1000000 Hz" -> "1.000 MHz"
//
// 5. RECIPROCAL COUNTING:
//    For low frequencies, measure the period instead of counting pulses.
//    Count master clock cycles during N cycles of the input signal.
//
// ============================================================================
