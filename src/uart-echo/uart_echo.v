// ============================================================================
// UART ECHO with Case Toggle - for iCEBreaker FPGA
// ============================================================================
//
// This module combines UART RX and TX to create an echo server with a twist:
//   - Receives a character from the PC via UART
//   - Toggles the case (lowercase → uppercase, uppercase → lowercase)
//   - Transmits the modified character back to the PC
//
// For example:
//   - Type 'h' → receive 'H'
//   - Type 'H' → receive 'h'
//   - Type '5' → receive '5' (non-letters unchanged)
//
// ============================================================================
// HOW CASE TOGGLING WORKS (ASCII Trick)
// ============================================================================
//
// In ASCII, uppercase and lowercase letters differ only in bit 5:
//
//   'A' = 0x41 = 0100_0001     'a' = 0x61 = 0110_0001
//   'B' = 0x42 = 0100_0010     'b' = 0x62 = 0110_0010
//   'Z' = 0x5A = 0101_1010     'z' = 0x7A = 0111_1010
//                  ↑                          ↑
//               bit 5 = 0               bit 5 = 1
//
// So XOR-ing with 0x20 (which is just bit 5) toggles the case!
//   'A' ^ 0x20 = 'a'
//   'a' ^ 0x20 = 'A'
//
// We just need to check if the character is a letter first (A-Z or a-z).
//
// ============================================================================
// ARCHITECTURE OVERVIEW
// ============================================================================
//
// The module contains three main sections:
//   1. UART RECEIVER - Captures incoming bytes from the PC
//   2. CASE TOGGLE - Converts the received character
//   3. UART TRANSMITTER - Sends the modified character back
//
// Data flow:
//   RX pin → [Receiver] → rx_byte → [Case Toggle] → tx_byte → [Transmitter] → TX pin
//                            ↓
//                      rx_ready pulse
//                            ↓
//                      triggers TX
//
// ============================================================================

module uart_echo (
    input  wire clk,    // 12 MHz clock from pin 35
    input  wire rx,     // UART receive pin (from FTDI chip)
    output reg  tx,     // UART transmit pin (to FTDI chip)
    output reg  led     // Activity LED - blinks when echoing
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    //
    // 115200 baud with 12 MHz clock:
    //   Clocks per bit = 12,000,000 / 115,200 ≈ 104

    localparam CLOCKS_PER_BIT = 104;
    localparam HALF_BIT = 52;

    // ========================================================================
    // RX INPUT SYNCHRONIZATION
    // ========================================================================
    //
    // The RX signal comes from outside our clock domain. Pass it through
    // two flip-flops to prevent metastability issues.

    reg rx_sync_1 = 1;
    reg rx_sync_2 = 1;

    always @(posedge clk) begin
        rx_sync_1 <= rx;
        rx_sync_2 <= rx_sync_1;
    end

    wire rx_sync = rx_sync_2;

    // ========================================================================
    // UART RECEIVER STATE MACHINE
    // ========================================================================

    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg [1:0]  rx_state = RX_IDLE;
    reg [6:0]  rx_baud_counter = 0;
    reg [2:0]  rx_bit_index = 0;
    reg [7:0]  rx_shift_reg = 0;     // Shift register for incoming bits
    reg [7:0]  rx_byte = 0;          // Complete received byte
    reg        rx_ready = 0;         // Pulse HIGH for one clock when byte ready

    always @(posedge clk) begin
        // Default: rx_ready is only HIGH for one clock cycle
        rx_ready <= 0;

        case (rx_state)
            // ----------------------------------------------------------------
            // RX IDLE: Wait for start bit (line goes LOW)
            // ----------------------------------------------------------------
            RX_IDLE: begin
                rx_baud_counter <= 0;
                rx_bit_index <= 0;

                if (rx_sync == 0) begin
                    // Start bit detected
                    rx_state <= RX_START;
                end
            end

            // ----------------------------------------------------------------
            // RX START: Wait half bit period, verify start bit
            // ----------------------------------------------------------------
            RX_START: begin
                if (rx_baud_counter == HALF_BIT - 1) begin
                    rx_baud_counter <= 0;

                    if (rx_sync == 0) begin
                        // Start bit confirmed, proceed to data
                        rx_state <= RX_DATA;
                    end else begin
                        // False alarm (noise), go back to idle
                        rx_state <= RX_IDLE;
                    end
                end else begin
                    rx_baud_counter <= rx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // RX DATA: Sample 8 data bits
            // ----------------------------------------------------------------
            RX_DATA: begin
                if (rx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    rx_baud_counter <= 0;

                    // Shift in the new bit (LSB first, so shift from MSB side)
                    rx_shift_reg <= {rx_sync, rx_shift_reg[7:1]};

                    if (rx_bit_index == 7) begin
                        rx_bit_index <= 0;
                        rx_state <= RX_STOP;
                    end else begin
                        rx_bit_index <= rx_bit_index + 1;
                    end
                end else begin
                    rx_baud_counter <= rx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // RX STOP: Sample stop bit, signal byte ready
            // ----------------------------------------------------------------
            RX_STOP: begin
                if (rx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    rx_baud_counter <= 0;
                    rx_state <= RX_IDLE;

                    // Transfer received byte and signal it's ready
                    rx_byte <= rx_shift_reg;
                    rx_ready <= 1;
                end else begin
                    rx_baud_counter <= rx_baud_counter + 1;
                end
            end

            default: rx_state <= RX_IDLE;
        endcase
    end

    // ========================================================================
    // CASE TOGGLE LOGIC
    // ========================================================================
    //
    // When a byte is received (rx_ready pulse), we check if it's a letter:
    //   - Lowercase 'a'-'z': ASCII 0x61 to 0x7A (97 to 122)
    //   - Uppercase 'A'-'Z': ASCII 0x41 to 0x5A (65 to 90)
    //
    // If it's a letter, XOR with 0x20 to toggle bit 5 (changes case).
    // If it's not a letter, pass through unchanged.
    //
    // Special case: When we receive \r (Enter key), we send \r\n for proper
    // line endings in the terminal.
    //
    // The result is stored in tx_byte and tx_start triggers transmission.

    reg [7:0] tx_byte = 0;
    reg       tx_start = 0;
    reg       send_lf = 0;      // Flag: need to send \n after current TX completes
    wire      tx_done;          // Pulse when TX finishes (defined later, directly wired)

    // Combinational logic to detect letter and toggle case
    wire is_lowercase = (rx_byte >= 8'h61) && (rx_byte <= 8'h7A);  // 'a' to 'z'
    wire is_uppercase = (rx_byte >= 8'h41) && (rx_byte <= 8'h5A);  // 'A' to 'Z'
    wire is_letter = is_lowercase || is_uppercase;
    wire is_cr = (rx_byte == 8'h0D);  // Carriage return

    // Case-toggled byte: XOR with 0x20 if letter, otherwise unchanged
    wire [7:0] toggled_byte = is_letter ? (rx_byte ^ 8'h20) : rx_byte;

    always @(posedge clk) begin
        // Default: tx_start is only HIGH for one clock
        tx_start <= 0;

        if (rx_ready) begin
            // New byte received! Toggle case and trigger transmit
            tx_byte <= toggled_byte;
            tx_start <= 1;
            led <= ~led;  // Toggle LED on each character (visual feedback)

            // If it's a carriage return, flag that we need to send LF next
            if (is_cr) begin
                send_lf <= 1;
            end
        end else if (send_lf && tx_done) begin
            // Previous TX finished and we need to send LF
            tx_byte <= 8'h0A;  // Line feed
            tx_start <= 1;
            send_lf <= 0;
        end
    end

    // ========================================================================
    // UART TRANSMITTER STATE MACHINE
    // ========================================================================

    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    reg [1:0]  tx_state = TX_IDLE;
    reg [6:0]  tx_baud_counter = 0;
    reg [2:0]  tx_bit_index = 0;
    reg [7:0]  tx_shift_reg = 0;     // Shift register for outgoing bits
    reg        tx_done_reg = 0;      // Pulses HIGH when TX completes

    // Connect tx_done wire to the register (used by case toggle logic above)
    assign tx_done = tx_done_reg;

    always @(posedge clk) begin
        // Default: tx_done only pulses for one clock
        tx_done_reg <= 0;

        case (tx_state)
            // ----------------------------------------------------------------
            // TX IDLE: Wait for tx_start trigger
            // ----------------------------------------------------------------
            TX_IDLE: begin
                tx <= 1;  // UART idle is HIGH
                tx_baud_counter <= 0;
                tx_bit_index <= 0;

                if (tx_start) begin
                    // Load byte and start transmitting
                    tx_shift_reg <= tx_byte;
                    tx_state <= TX_START;
                end
            end

            // ----------------------------------------------------------------
            // TX START: Send start bit (LOW)
            // ----------------------------------------------------------------
            TX_START: begin
                tx <= 0;  // Start bit is always LOW

                if (tx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    tx_baud_counter <= 0;
                    tx_state <= TX_DATA;
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // TX DATA: Send 8 data bits (LSB first)
            // ----------------------------------------------------------------
            TX_DATA: begin
                tx <= tx_shift_reg[0];  // Send LSB

                if (tx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    tx_baud_counter <= 0;

                    if (tx_bit_index == 7) begin
                        tx_bit_index <= 0;
                        tx_state <= TX_STOP;
                    end else begin
                        tx_bit_index <= tx_bit_index + 1;
                        tx_shift_reg <= tx_shift_reg >> 1;  // Shift right for next bit
                    end
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // TX STOP: Send stop bit (HIGH)
            // ----------------------------------------------------------------
            TX_STOP: begin
                tx <= 1;  // Stop bit is always HIGH

                if (tx_baud_counter == CLOCKS_PER_BIT - 1) begin
                    tx_baud_counter <= 0;
                    tx_state <= TX_IDLE;
                    tx_done_reg <= 1;  // Signal that transmission is complete
                end else begin
                    tx_baud_counter <= tx_baud_counter + 1;
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
// HOW TO TEST THIS PROJECT:
// ============================================================================
//
// 1. Build the project:
//      cd src/uart_echo
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
// 5. Type letters and watch them come back with toggled case!
//      Type 'h' → see 'H'
//      Type 'H' → see 'h'
//      Type 'hello' → see 'HELLO'
//      Type '123' → see '123' (numbers unchanged)
//
// 6. The LED on the board will toggle with each character received.
//
// 7. To exit screen: Ctrl+A, K, Y
//    To exit picocom: Ctrl+A, Ctrl+X
//
// ============================================================================
// LEARNING EXERCISES:
// ============================================================================
//
// 1. ROT13 CIPHER:
//    Instead of case toggle, implement ROT13 - rotate letters by 13 positions.
//    'a' → 'n', 'n' → 'a', 'A' → 'N', etc.
//
// 2. UPPERCASE ONLY:
//    Always convert to uppercase (never send lowercase).
//    Hint: For lowercase, subtract 0x20 instead of XOR.
//
// 3. ADD NEWLINE:
//    When you receive '\r' (Enter key), also send '\n' for proper line endings.
//
// 4. BUFFER MULTIPLE CHARACTERS:
//    Add a FIFO buffer so you can receive the next character while still
//    transmitting the previous one. This allows faster typing.
//
// ============================================================================
