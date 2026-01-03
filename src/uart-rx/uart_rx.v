// ============================================================================
// UART RX - Serial Receiver for iCEBreaker FPGA
// ============================================================================
//
// This module implements a UART receiver that controls an LED based on
// keyboard input:
//   - Type '1' → LED turns ON
//   - Type '0' → LED turns OFF
//   - Other characters are ignored
//
// This is the "companion" to the UART TX project. While TX sends data OUT,
// RX receives data IN. RX is actually slightly harder because we must
// DETECT when data arrives and synchronize to it.
//
// ============================================================================
// UART RECEIVE PROTOCOL
// ============================================================================
//
// The UART frame looks the same as TX, but now we're reading it:
//
//     IDLE   START  D0  D1  D2  D3  D4  D5  D6  D7  STOP  IDLE
//     ____         ___     ___         ___     ___ ___________
//         |_______|   |___|   |_______|   |___|   |
//     HIGH  LOW   <-------- 8 data bits -------->  HIGH
//           ↑
//      We detect this falling edge to know data is coming!
//
// KEY CHALLENGE: The sender (PC) has its own clock. We can't predict
// exactly when data will arrive. We must:
//   1. DETECT the start bit (falling edge from HIGH to LOW)
//   2. SAMPLE each bit at the right moment
//
// ============================================================================
// SAMPLING STRATEGY: Why Sample in the Middle?
// ============================================================================
//
// If we sample too close to bit transitions, noise could cause errors:
//
//     |<-------- one bit period -------->|
//     __________________________________
//                                        |_______________
//     ^                    ^                            ^
//   BAD (too early)    GOOD (middle)              BAD (too late)
//
// By sampling in the MIDDLE of each bit, we have maximum margin for error.
// At 115200 baud with 104 clocks per bit, we sample at clock 52.
//
// ============================================================================

module uart_rx (
    input  wire clk,    // 12 MHz clock from pin 35
    input  wire rx,     // UART receive pin (from FTDI chip)
    output reg  led = 1 // LED controlled by received '0' or '1' (active LOW, init OFF)
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    //
    // Same baud rate as our TX project: 115200 bps
    // Clocks per bit = 12,000,000 / 115,200 ≈ 104

    localparam CLOCKS_PER_BIT = 104;
    localparam HALF_BIT = 52;  // Half of 104 - used to sample in the middle

    // ========================================================================
    // INPUT SYNCHRONIZATION
    // ========================================================================
    //
    // IMPORTANT: The RX signal comes from outside our clock domain (the FTDI
    // chip has its own timing). This can cause "metastability" - a flip-flop
    // getting confused when input changes exactly at a clock edge.
    //
    // Solution: Pass the input through two flip-flops (a "synchronizer").
    // This gives the signal time to settle to a stable 0 or 1.
    //
    //   rx_pin → [FF1] → [FF2] → rx_sync (safe to use)
    //
    // This adds 2 clock cycles of delay (~167ns) which is negligible.

    reg rx_sync_1 = 1;  // First synchronizer stage (initialize HIGH = idle)
    reg rx_sync_2 = 1;  // Second synchronizer stage (this is our safe signal)

    always @(posedge clk) begin
        rx_sync_1 <= rx;         // Capture raw input
        rx_sync_2 <= rx_sync_1;  // Delay by one more clock
    end

    // Use rx_sync_2 for all our logic - it's now safely synchronized
    wire rx_sync = rx_sync_2;

    // ========================================================================
    // STATE MACHINE STATES
    // ========================================================================
    //
    // The receiver cycles through these states:
    //
    //   IDLE ──(rx goes LOW)──> START ──(half bit)──> DATA ──(8 bits)──> STOP
    //     ↑                                                                │
    //     └────────────────────(process byte)──────────────────────────────┘

    localparam STATE_IDLE  = 2'd0;  // Waiting for start bit
    localparam STATE_START = 2'd1;  // Confirming start bit, centering
    localparam STATE_DATA  = 2'd2;  // Receiving 8 data bits
    localparam STATE_STOP  = 2'd3;  // Receiving stop bit, processing byte

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // COUNTERS AND REGISTERS
    // ========================================================================

    // Baud counter - counts clock cycles within each bit period
    reg [6:0] baud_counter = 0;

    // Bit counter - which of the 8 data bits we're receiving (0-7)
    reg [2:0] bit_index = 0;

    // Shift register - holds the byte being received
    // Bits shift in from the MSB side, so after 8 bits, bit 0 = first received
    reg [7:0] rx_byte = 0;

    // ========================================================================
    // UART RECEIVE STATE MACHINE
    // ========================================================================
    //
    // This state machine handles the receive process:
    //   1. Wait for the line to go LOW (start bit detected)
    //   2. Wait half a bit period to center ourselves in the start bit
    //   3. Verify start bit is still LOW (filters out noise glitches)
    //   4. Sample 8 data bits, each at the middle of its bit period
    //   5. Sample stop bit, process the received byte

    always @(posedge clk) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE STATE: Wait for start bit (falling edge)
            // ----------------------------------------------------------------
            // The line idles HIGH. When we see it go LOW, a start bit has begun.
            // We don't need explicit edge detection here - just checking for LOW
            // is sufficient since we return to IDLE after each byte.
            STATE_IDLE: begin
                baud_counter <= 0;
                bit_index <= 0;

                if (rx_sync == 0) begin
                    // Start bit detected! Begin receiving.
                    state <= STATE_START;
                end
            end

            // ----------------------------------------------------------------
            // START STATE: Center ourselves in the start bit
            // ----------------------------------------------------------------
            // We detected the falling edge, but we're at the very beginning of
            // the start bit. We need to wait until we're in the MIDDLE of the
            // start bit, then verify it's still LOW (not just noise).
            //
            // Why half a bit period? We want to sample all future bits in their
            // middle. If we start counting from the middle of the start bit,
            // then after 104 clocks we'll be in the middle of D0, etc.
            //
            //   Start bit    D0       D1      ...
            //   |<--104-->|<--104-->|<--104-->|
            //       ↑          ↑        ↑
            //      here     sample   sample
            //     (52 clks)
            STATE_START: begin
                if (baud_counter == HALF_BIT - 1) begin
                    // We're now in the middle of the start bit
                    baud_counter <= 0;

                    if (rx_sync == 0) begin
                        // Start bit confirmed! Proceed to receive data bits.
                        state <= STATE_DATA;
                    end else begin
                        // False alarm - line went HIGH. Was just noise.
                        state <= STATE_IDLE;
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DATA STATE: Sample 8 data bits
            // ----------------------------------------------------------------
            // Now we're synchronized. Every 104 clocks, we sample a bit.
            // Since we started in the middle of the start bit, we'll hit the
            // middle of each data bit too.
            //
            // UART sends LSB first, so the first bit we receive is bit 0.
            // We shift bits into rx_byte from the MSB side:
            //   rx_byte = {rx_sync, rx_byte[7:1]}
            // After 8 shifts, bit 0 contains the first bit received (LSB).
            STATE_DATA: begin
                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    // Time to sample!
                    baud_counter <= 0;

                    // Shift the new bit into the MSB, old bits shift right
                    rx_byte <= {rx_sync, rx_byte[7:1]};

                    if (bit_index == 7) begin
                        // All 8 bits received, move to stop bit
                        bit_index <= 0;
                        state <= STATE_STOP;
                    end else begin
                        bit_index <= bit_index + 1;
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // STOP STATE: Sample stop bit and process the byte
            // ----------------------------------------------------------------
            // The stop bit should be HIGH. We sample it to complete the frame,
            // then process the received byte.
            STATE_STOP: begin
                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    baud_counter <= 0;
                    state <= STATE_IDLE;

                    // Process the received byte!
                    // Check if it's '0' (ASCII 48 = 0x30) or '1' (ASCII 49 = 0x31)
                    //
                    // NOTE: The accent LED on pin 37 is ACTIVE LOW on the iCEBreaker.
                    // Output 0 = LED ON, Output 1 = LED OFF
                    if (rx_byte == 8'h31) begin
                        // Received '1' - turn LED ON (active low: output 0)
                        led <= 0;
                    end else if (rx_byte == 8'h30) begin
                        // Received '0' - turn LED OFF (active low: output 1)
                        led <= 1;
                    end
                    // Any other character is ignored - LED stays as-is

                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DEFAULT: Safety net
            // ----------------------------------------------------------------
            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end

endmodule

// ============================================================================
// HOW TO TEST THIS PROJECT:
// ============================================================================
//
// 1. Build the project:
//      cd src/uart-rx
//      make
//
// 2. Program the FPGA:
//      make prog
//
// 3. Find the serial port (on Linux):
//      ls /dev/ttyUSB*
//    Usually it's /dev/ttyUSB1 (USB0 is for programming, USB1 is UART)
//
// 4. Open a terminal program at 115200 baud:
//      screen /dev/ttyUSB1 115200
//    Or:
//      picocom -b 115200 /dev/ttyUSB1
//
// 5. Type '1' - the accent LED should turn ON
//    Type '0' - the accent LED should turn OFF
//    Type anything else - LED stays unchanged
//
// 6. To exit screen: Ctrl+A, then K, then Y
//    To exit picocom: Ctrl+A, then Ctrl+X
//
// ============================================================================
// LEARNING EXERCISES:
// ============================================================================
//
// 1. ADD MORE CONTROLS:
//    Make '2' blink the LED, or 'r'/'g'/'b' control an RGB LED.
//
// 2. ECHO BACK:
//    Combine with UART TX to echo received characters back to the terminal.
//    This requires connecting both uart_tx and uart_rx modules.
//
// 3. CONTROL MULTIPLE LEDS:
//    Use '1'-'5' to toggle the 5 breakout board LEDs individually.
//
// 4. ADD ERROR DETECTION:
//    Check that the stop bit is actually HIGH. If not, signal an error
//    (framing error) by blinking an LED rapidly.
//
// ============================================================================
// COMMON ISSUES AND DEBUGGING:
// ============================================================================
//
// LED doesn't respond:
//   - Make sure you're using the right serial port (/dev/ttyUSB1, not USB0)
//   - Verify baud rate is 115200 in your terminal program
//   - Check that the FPGA is programmed (iceprog should show success)
//
// LED responds erratically:
//   - Could be noise on the RX line - the synchronizer should handle this
//   - Try a different USB cable or port
//
// Terminal shows garbage:
//   - Baud rate mismatch - both sides must be 115200
//
// ============================================================================
