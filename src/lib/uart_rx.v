// ============================================================================
// UART Receiver - Shared Library Module
// ============================================================================
//
// Canonical UART receiver for the iCEBreaker shared module library.
// Standard 8N1 format: 8 data bits, no parity, 1 stop bit.
//
// INTERFACE CONVENTIONS (library standard):
//   - All inputs use _i suffix, outputs use _o suffix
//   - clk_i: System clock input
//   - rst_i: Synchronous reset (active HIGH)
//   - valid_o: Pulses HIGH for one clock when data_o is valid
//
// UART PROTOCOL:
//   - Idle state is HIGH
//   - Start bit: LOW for one bit period
//   - Data bits: 8 bits, LSB first
//   - Stop bit: HIGH for one bit period
//
// KEY FEATURES:
//   - 2-FF synchronizer for metastability protection
//   - Mid-bit sampling for noise immunity
//   - Glitch rejection (verifies start bit at mid-point)
//
// USAGE:
//   1. Connect rx_i to UART receive pin
//   2. When valid_o pulses HIGH, read data_o for received byte
//   3. valid_o is HIGH for exactly one clock cycle per byte
//
// RESET BEHAVIOR:
//   - valid_o set LOW
//   - Receiver returns to idle state
//
// BAUD RATE:
//   - Configured via CLOCKS_PER_BIT parameter
//   - For 115200 baud at 12 MHz: 12,000,000 / 115200 = 104
//
// ============================================================================

module uart_rx #(
    parameter CLOCKS_PER_BIT = 104   // 12 MHz / 115200 baud = 104
) (
    input  wire       clk_i,         // System clock
    input  wire       rst_i,         // Synchronous reset (active HIGH)
    input  wire       rx_i,          // UART receive line

    output reg  [7:0] data_o,        // Received byte
    output reg        valid_o        // Pulses HIGH for one clock when byte received
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================

    localparam HALF_BIT = CLOCKS_PER_BIT / 2;  // Sample at mid-bit

    // ========================================================================
    // INPUT SYNCHRONIZATION (2-FF Synchronizer)
    // ========================================================================
    //
    // The RX signal comes from outside our clock domain. This can cause
    // "metastability" - a flip-flop getting confused when input changes
    // exactly at a clock edge.
    //
    // Solution: Pass the input through two flip-flops (a "synchronizer").
    // This gives the signal time to settle to a stable 0 or 1.
    //
    //   rx_i -> [FF1] -> [FF2] -> rx_sync (safe to use)

    reg rx_sync_1 = 1'b1;  // First synchronizer stage (init HIGH = idle)
    reg rx_sync_2 = 1'b1;  // Second synchronizer stage

    always @(posedge clk_i) begin
        if (rst_i) begin
            rx_sync_1 <= 1'b1;
            rx_sync_2 <= 1'b1;
        end else begin
            rx_sync_1 <= rx_i;
            rx_sync_2 <= rx_sync_1;
        end
    end

    wire rx_sync = rx_sync_2;

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================

    localparam STATE_IDLE  = 2'd0;  // Waiting for start bit
    localparam STATE_START = 2'd1;  // Confirming start bit, centering
    localparam STATE_DATA  = 2'd2;  // Receiving 8 data bits
    localparam STATE_STOP  = 2'd3;  // Receiving stop bit

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // REGISTERS
    // ========================================================================

    reg [7:0] baud_counter = 8'd0;   // Counts clocks within bit period
    reg [2:0] bit_index = 3'd0;      // Which of 8 data bits (0-7)
    reg [7:0] rx_byte = 8'd0;        // Shift register for incoming bits

    // ========================================================================
    // UART RECEIVE STATE MACHINE
    // ========================================================================

    always @(posedge clk_i) begin
        // Default: valid_o is only high for one clock
        valid_o <= 1'b0;

        if (rst_i) begin
            state <= STATE_IDLE;
            baud_counter <= 8'd0;
            bit_index <= 3'd0;
            rx_byte <= 8'd0;
            data_o <= 8'd0;
            valid_o <= 1'b0;
        end else begin
            case (state)
                // ----------------------------------------------------------------
                // IDLE: Wait for start bit (falling edge)
                // ----------------------------------------------------------------
                STATE_IDLE: begin
                    baud_counter <= 8'd0;
                    bit_index <= 3'd0;

                    if (rx_sync == 1'b0) begin
                        // Start bit detected
                        state <= STATE_START;
                    end
                end

                // ----------------------------------------------------------------
                // START: Center in start bit, verify it's real
                // ----------------------------------------------------------------
                // Wait half a bit period to get to the middle of the start bit.
                // Then verify it's still LOW (not just noise glitch).
                STATE_START: begin
                    if (baud_counter == HALF_BIT - 1) begin
                        baud_counter <= 8'd0;

                        if (rx_sync == 1'b0) begin
                            // Start bit confirmed, proceed to data
                            state <= STATE_DATA;
                        end else begin
                            // False alarm - was just noise
                            state <= STATE_IDLE;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // DATA: Sample 8 data bits at mid-bit
                // ----------------------------------------------------------------
                // UART sends LSB first. We shift bits in from MSB side,
                // so after 8 shifts, bit 0 = first bit received (LSB).
                STATE_DATA: begin
                    if (baud_counter == CLOCKS_PER_BIT - 1) begin
                        baud_counter <= 8'd0;

                        // Shift new bit into MSB, old bits shift right
                        rx_byte <= {rx_sync, rx_byte[7:1]};

                        if (bit_index == 3'd7) begin
                            // All 8 bits received
                            bit_index <= 3'd0;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // STOP: Sample stop bit, output received byte
                // ----------------------------------------------------------------
                STATE_STOP: begin
                    if (baud_counter == CLOCKS_PER_BIT - 1) begin
                        baud_counter <= 8'd0;
                        state <= STATE_IDLE;

                        // Output the received byte
                        // (We could check rx_sync==1 for framing error, but skip for simplicity)
                        data_o <= rx_byte;
                        valid_o <= 1'b1;  // Pulse for one clock
                    end else begin
                        baud_counter <= baud_counter + 1'b1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
