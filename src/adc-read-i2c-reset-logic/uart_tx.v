// ============================================================================
// UART Transmitter (with Synchronous Reset)
// ============================================================================
//
// This module provides a reusable UART transmitter for sending bytes serially.
// Standard 8N1 format: 8 data bits, no parity, 1 stop bit.
//
// UART PROTOCOL:
//   - Idle state is HIGH
//   - Start bit: LOW for one bit period
//   - Data bits: 8 bits, LSB first
//   - Stop bit: HIGH for one bit period
//
// INTERFACE:
//   - Load data_i and assert start_i for one clock to begin transmission
//   - busy_o is high during transmission
//   - When busy_o falls, transmitter is ready for next byte
//
// RESET BEHAVIOR:
//   - When rst is HIGH, module returns to idle state
//   - tx_o is set HIGH (UART idle) to avoid spurious data
//   - busy_o is cleared to indicate ready state
//
// BAUD RATE:
//   - Configured via CLOCKS_PER_BIT parameter
//   - For 115200 baud at 12 MHz: 12,000,000 / 115200 = 104
//
// ============================================================================

module uart_tx #(
    parameter CLOCKS_PER_BIT = 104   // 12 MHz / 115200 baud = 104
) (
    input  wire       clk,           // System clock
    input  wire       rst,           // Synchronous reset (active HIGH)
    input  wire [7:0] data_i,        // Byte to transmit
    input  wire       start_i,       // Start transmission (single clock pulse)

    output reg        busy_o,        // High during transmission
    output reg        tx_o           // UART transmit line
);

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // States for UART transmission:
    //   IDLE  -> Waiting for data to send
    //   START -> Send start bit (LOW)
    //   DATA  -> Send 8 data bits (LSB first)
    //   STOP  -> Send stop bit (HIGH)

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_START = 2'd1;
    localparam STATE_DATA  = 2'd2;
    localparam STATE_STOP  = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // REGISTERS
    // ========================================================================

    reg [7:0] tx_byte = 8'd0;        // Current byte being transmitted
    reg [7:0] baud_counter = 8'd0;   // Baud rate counter (needs log2(CLOCKS_PER_BIT) bits)
    reg [2:0] bit_index = 3'd0;      // Which bit we're sending (0-7)

    // ========================================================================
    // UART TRANSMITTER STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        // ----------------------------------------------------------------
        // SYNCHRONOUS RESET
        // ----------------------------------------------------------------
        // On reset: return to idle state with tx_o HIGH (UART idle)
        // This ensures no spurious data is transmitted during reset
        if (rst) begin
            state <= STATE_IDLE;
            tx_o <= 1'b1;            // UART idle is HIGH
            busy_o <= 1'b0;
            tx_byte <= 8'd0;
            baud_counter <= 8'd0;
            bit_index <= 3'd0;
        end else begin
            case (state)
                // ----------------------------------------------------------------
                // IDLE: Wait for transmission request
                // ----------------------------------------------------------------
                STATE_IDLE: begin
                    tx_o <= 1'b1;            // UART idle is HIGH
                    baud_counter <= 8'd0;
                    bit_index <= 3'd0;
                    busy_o <= 1'b0;

                    if (start_i) begin
                        tx_byte <= data_i;   // Latch the data
                        busy_o <= 1'b1;
                        state <= STATE_START;
                    end
                end

                // ----------------------------------------------------------------
                // START: Send start bit (LOW) for one bit period
                // ----------------------------------------------------------------
                STATE_START: begin
                    tx_o <= 1'b0;            // Start bit is LOW

                    if (baud_counter == CLOCKS_PER_BIT - 1) begin
                        baud_counter <= 8'd0;
                        state <= STATE_DATA;
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // DATA: Send 8 data bits, LSB first
                // ----------------------------------------------------------------
                STATE_DATA: begin
                    tx_o <= tx_byte[0];      // Send LSB

                    if (baud_counter == CLOCKS_PER_BIT - 1) begin
                        baud_counter <= 8'd0;

                        if (bit_index == 3'd7) begin
                            // All 8 bits sent
                            bit_index <= 3'd0;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx_byte <= tx_byte >> 1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // STOP: Send stop bit (HIGH) for one bit period
                // ----------------------------------------------------------------
                STATE_STOP: begin
                    tx_o <= 1'b1;            // Stop bit is HIGH

                    if (baud_counter == CLOCKS_PER_BIT - 1) begin
                        baud_counter <= 8'd0;
                        busy_o <= 1'b0;
                        state <= STATE_IDLE;
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    tx_o <= 1'b1;
                end
            endcase
        end
    end

endmodule
