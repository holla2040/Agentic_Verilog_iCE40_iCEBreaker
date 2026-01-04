// ============================================================================
// SPI DAC Driver for DAC121S101
// ============================================================================
//
// This module provides a reusable SPI interface for the DAC121S101 12-bit DAC.
// It accepts a 12-bit value and transmits it over SPI continuously.
//
// DAC121S101 SPI PROTOCOL:
//   - Data clocked into DAC on FALLING edges of SCLK
//   - 16-bit frame: [X][X][PD1][PD0][D11][D10]...[D1][D0]
//   - PD1:PD0 = 00 for normal operation
//   - SYNC (chip select) is active LOW
//
// ACTIVE-LOW ACCENT ACCENT:
//   - SCLK idles HIGH
//   - Data changes on rising edge, sampled by DAC on falling edge
//
// ============================================================================

module spi_dac #(
    parameter SPI_HALF_PERIOD = 1    // Clock divider for SPI speed
) (
    input  wire        clk,          // System clock
    input  wire [11:0] data_i,       // 12-bit DAC value to send

    // SPI interface
    output reg         sync_n_o,     // Chip select (active LOW)
    output reg         sclk_o,       // SPI clock
    output reg         din_o         // Serial data to DAC
);

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // Simple state machine for SPI transmission:
    //   IDLE:  SYNC high, brief pause between transfers
    //   LOAD:  Prepare shift register, assert SYNC low
    //   SHIFT: Clock out 16 bits on falling SCLK edges
    //   DONE:  Release SYNC high

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_LOAD  = 2'd1;
    localparam STATE_SHIFT = 2'd2;
    localparam STATE_DONE  = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // REGISTERS
    // ========================================================================

    reg [15:0] shift_reg = 16'd0;    // 16-bit shift register for SPI data
    reg [3:0]  bit_count = 4'd0;     // Count of bits shifted (0-15)
    reg [3:0]  clk_div = 4'd0;       // Clock divider counter

    // ========================================================================
    // SPI STATE MACHINE
    // ========================================================================
    //
    // Continuously sends data_i to the DAC. The DAC will update its output
    // whenever a complete 16-bit frame is received.

    always @(posedge clk) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE STATE: Brief pause, then start next transfer
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                sync_n_o <= 1'b1;        // SYNC high (inactive)
                sclk_o <= 1'b1;          // SCLK idles high
                state <= STATE_LOAD;
            end

            // ----------------------------------------------------------------
            // LOAD STATE: Prepare shift register and assert SYNC low
            // ----------------------------------------------------------------
            STATE_LOAD: begin
                // Build the 16-bit SPI word
                // Bits 15-12: 0000 (don't care + normal mode)
                // Bits 11-0: DAC value
                shift_reg <= {4'b0000, data_i};

                bit_count <= 4'd0;
                clk_div <= 4'd0;
                sync_n_o <= 1'b0;        // Assert SYNC low to start transfer
                sclk_o <= 1'b1;          // Clock starts high
                din_o <= 1'b0;

                state <= STATE_SHIFT;
            end

            // ----------------------------------------------------------------
            // SHIFT STATE: Clock out 16 bits, data sampled on falling edge
            // ----------------------------------------------------------------
            STATE_SHIFT: begin
                if (clk_div == SPI_HALF_PERIOD - 1) begin
                    clk_div <= 4'd0;

                    if (sclk_o == 1'b1) begin
                        // Falling edge of SCLK - data is captured by DAC
                        sclk_o <= 1'b0;
                    end else begin
                        // Rising edge of SCLK - advance to next bit
                        sclk_o <= 1'b1;

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
                din_o <= shift_reg[15];
            end

            // ----------------------------------------------------------------
            // DONE STATE: Release SYNC, go back to IDLE
            // ----------------------------------------------------------------
            STATE_DONE: begin
                sync_n_o <= 1'b1;        // Release SYNC high
                sclk_o <= 1'b1;          // SCLK returns to idle high
                state <= STATE_IDLE;
            end

            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end

endmodule
