// ============================================================================
// DAC Ramp Generator for PMOD DA2 (DAC121S101)
// ============================================================================
//
// This module generates a triangular ramp waveform on the PMOD DA2's DAC
// output. The output voltage ramps from 0V to 3.3V and back down continuously,
// completing a full cycle in approximately 1 second.
//
// HARDWARE: PMOD DA2 (Digilent) connected to iCEBreaker PMOD1A
//   - Contains two DAC121S101 12-bit DACs (we use channel A)
//   - Supply voltage (3.3V) serves as reference, so output range is 0-3.3V
//   - SPI interface: SYNC (chip select), SCLK (clock), DIN (data)
//
// DAC121S101 SPI PROTOCOL:
//   - Data is clocked into the DAC on FALLING edges of SCLK
//   - SYNC must go LOW to start a transfer
//   - 16 bits are shifted in: [X][X][PD1][PD0][D11][D10]...[D1][D0]
//     - Bits 15-14: Don't care (X)
//     - Bits 13-12: Power-down mode (00 = normal operation)
//     - Bits 11-0:  12-bit DAC data (0-4095)
//   - DAC output updates on the 16th falling clock edge
//   - SYNC returns HIGH after transfer completes
//
// TIMING (12 MHz system clock):
//   - SPI clock: 1 MHz (divide by 12)
//   - 16-bit transfer: ~16 microseconds
//   - Ramp step rate: ~8192 steps/second for 1 Hz triangle wave
//
// ============================================================================

module dac_ramp (
    input  wire clk,           // 12 MHz system clock

    // DAC SPI interface (directly active)
    output reg  dac_sync_n,    // Chip select (active LOW)
    output reg  dac_din,       // Serial data out (directly active)
    output reg  dac_sclk       // SPI clock
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    //
    // MAXIMUM SPEED MODE
    //
    // System clock: 12 MHz = 12,000,000 Hz
    // SPI clock: 6 MHz (divide by 2) - fastest possible with 12 MHz system clock
    // DAC121S101 max is 30 MHz, so we're well within spec
    //
    // 16-bit transfer at 6 MHz = ~2.67 µs per update
    // Maximum update rate: ~375,000 updates/second
    //
    // With step size of 16:
    //   Steps per direction: 4096 / 16 = 256
    //   Steps per full cycle: 512
    //   Cycle frequency: 375,000 / 512 ≈ 732 Hz triangle wave
    //
    // The ramp runs as fast as the SPI can transfer!

    localparam SPI_HALF_PERIOD = 1;      // Fastest: toggle every clock (6 MHz SPI)
    localparam RAMP_STEP = 16;           // Increment by 16 for ~700 Hz triangle wave
    // Try these values for different speeds:
    //   RAMP_STEP = 1   -> ~37 Hz  (smooth but slow)
    //   RAMP_STEP = 4   -> ~150 Hz
    //   RAMP_STEP = 16  -> ~700 Hz (default - nice on scope)
    //   RAMP_STEP = 64  -> ~2.8 kHz (very fast)

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // The SPI controller uses a simple state machine:
    //   IDLE:  Waiting for next transfer (SYNC high, counting down interval)
    //   LOAD:  Prepare shift register, assert SYNC low
    //   SHIFT: Clock out 16 bits on falling SCLK edges
    //   DONE:  Release SYNC high, prepare for next transfer

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_LOAD  = 2'd1;
    localparam STATE_SHIFT = 2'd2;
    localparam STATE_DONE  = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // REGISTERS
    // ========================================================================

    // Ramp generator
    reg [11:0] dac_value = 12'd0;        // Current DAC value (0-4095)
    reg        ramp_direction = 1'b1;    // 1 = counting up, 0 = counting down

    // SPI controller
    reg [15:0] shift_reg = 16'd0;        // 16-bit shift register for SPI data
    reg [3:0]  bit_count = 4'd0;         // Count of bits shifted (0-15)
    reg [3:0]  clk_div = 4'd0;           // Clock divider counter

    // Timing
    reg [10:0] interval_count = 11'd0;   // Counter for pacing DAC updates

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE STATE: Wait for interval timer, then start next transfer
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                dac_sync_n <= 1'b1;      // SYNC high (inactive)
                dac_sclk <= 1'b1;        // SCLK idles high (Mode 3 style)

                if (interval_count >= RAMP_INTERVAL - 1) begin
                    interval_count <= 11'd0;
                    state <= STATE_LOAD;
                end else begin
                    interval_count <= interval_count + 1'b1;
                end
            end

            // ----------------------------------------------------------------
            // LOAD STATE: Prepare shift register and assert SYNC low
            // ----------------------------------------------------------------
            // The 16-bit word format for DAC121S101:
            //   [15:14] = XX (don't care, we use 00)
            //   [13:12] = PD1,PD0 (00 = normal operation)
            //   [11:0]  = D11-D0 (12-bit DAC data, MSB first)
            //
            STATE_LOAD: begin
                // Build the 16-bit SPI word
                // Bits 15-12: 0000 (don't care + normal mode)
                // Bits 11-0: DAC value
                shift_reg <= {4'b0000, dac_value};

                bit_count <= 4'd0;
                clk_div <= 4'd0;
                dac_sync_n <= 1'b0;      // Assert SYNC low to start transfer
                dac_sclk <= 1'b1;        // Clock starts high
                dac_din <= 1'b0;         // Will be set properly in SHIFT state

                state <= STATE_SHIFT;
            end

            // ----------------------------------------------------------------
            // SHIFT STATE: Clock out 16 bits, data sampled on falling edge
            // ----------------------------------------------------------------
            // SPI timing for DAC121S101:
            //   - Data must be valid BEFORE falling edge of SCLK
            //   - DAC samples DIN on the FALLING edge of SCLK
            //   - We output data on rising edge, DAC captures on falling edge
            //
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
            // DONE STATE: Release SYNC, update ramp value for next transfer
            // ----------------------------------------------------------------
            STATE_DONE: begin
                dac_sync_n <= 1'b1;      // Release SYNC high
                dac_sclk <= 1'b1;        // SCLK returns to idle high

                // Update ramp value for next transfer
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

                state <= STATE_IDLE;
            end

            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end

endmodule
