// ============================================================================
// UART TX - Serial Byte Transmitter
// ============================================================================
//
// This module transmits a single byte over UART when triggered. It's designed
// as a building block that a higher-level state machine uses to send messages.
//
// INTERFACE:
//   - tx_data[7:0]: Byte to transmit (must be stable while tx_busy=1)
//   - tx_start:     Pulse HIGH for one clock to begin transmission
//   - tx_busy:      HIGH while transmission in progress
//   - tx:           UART output pin (connect to FTDI RX)
//
// USAGE PATTERN:
//   1. Wait for tx_busy == 0
//   2. Place byte on tx_data
//   3. Pulse tx_start HIGH for one clock
//   4. Wait for tx_busy to return to 0
//   5. Repeat for next byte
//
// UART FRAME FORMAT (8N1):
//   IDLE(H) -> START(L) -> D0 D1 D2 D3 D4 D5 D6 D7 -> STOP(H) -> IDLE(H)
//
// TIMING:
//   - Baud rate: 115200 bps
//   - Clocks per bit: 12 MHz / 115200 = 104 clocks
//   - Total frame: 10 bits = 1040 clocks = ~87 microseconds
//
// ============================================================================

module uart_tx (
    input  wire       clk,        // 12 MHz system clock
    input  wire [7:0] tx_data,    // Byte to transmit
    input  wire       tx_start,   // Pulse to begin transmission
    output reg        tx_busy,    // HIGH while transmitting
    output reg        tx          // UART output (idle HIGH)
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    // 12 MHz / 115200 baud = 104.166... clocks per bit
    // Using 104 gives 115,384 baud (0.16% error - well within tolerance)

    localparam CLOCKS_PER_BIT = 104;

    // ========================================================================
    // STATE MACHINE
    // ========================================================================
    // Simple 4-state machine for UART transmission:
    //   IDLE -> START -> DATA (x8) -> STOP -> IDLE

    localparam STATE_IDLE  = 2'd0;  // Waiting for tx_start
    localparam STATE_START = 2'd1;  // Sending start bit (LOW)
    localparam STATE_DATA  = 2'd2;  // Sending 8 data bits (LSB first)
    localparam STATE_STOP  = 2'd3;  // Sending stop bit (HIGH)

    reg [1:0] state;

    // ========================================================================
    // INTERNAL REGISTERS
    // ========================================================================

    // Baud rate counter - counts clocks within each bit period
    reg [6:0] baud_counter;  // 7 bits for 0-127 range (need 0-103)

    // Bit counter - which of the 8 data bits we're sending
    reg [2:0] bit_index;

    // Shift register - holds data being transmitted, shifts right for LSB-first
    reg [7:0] shift_reg;

    // ========================================================================
    // TRANSMIT STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE: Wait for transmission request
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                tx <= 1'b1;           // UART idle is HIGH
                baud_counter <= 0;
                bit_index <= 0;

                if (tx_start) begin
                    // Capture data and start transmitting
                    shift_reg <= tx_data;
                    tx_busy <= 1'b1;
                    state <= STATE_START;
                end else begin
                    tx_busy <= 1'b0;
                end
            end

            // ----------------------------------------------------------------
            // START: Send start bit (LOW) for one bit period
            // ----------------------------------------------------------------
            STATE_START: begin
                tx <= 1'b0;  // Start bit is always LOW

                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    baud_counter <= 0;
                    state <= STATE_DATA;
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DATA: Send 8 bits LSB first
            // ----------------------------------------------------------------
            // We send shift_reg[0], then shift right. This sends LSB first
            // as required by UART protocol.
            STATE_DATA: begin
                tx <= shift_reg[0];  // Output LSB

                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    baud_counter <= 0;

                    if (bit_index == 7) begin
                        // All 8 bits sent, move to stop bit
                        state <= STATE_STOP;
                    end else begin
                        // Shift to get next bit
                        bit_index <= bit_index + 1;
                        shift_reg <= shift_reg >> 1;
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // STOP: Send stop bit (HIGH) for one bit period
            // ----------------------------------------------------------------
            STATE_STOP: begin
                tx <= 1'b1;  // Stop bit is always HIGH

                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    // Transmission complete
                    state <= STATE_IDLE;
                    tx_busy <= 1'b0;
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DEFAULT: Safety - return to idle
            // ----------------------------------------------------------------
            default: begin
                state <= STATE_IDLE;
                tx <= 1'b1;
                tx_busy <= 1'b0;
            end
        endcase
    end

endmodule
