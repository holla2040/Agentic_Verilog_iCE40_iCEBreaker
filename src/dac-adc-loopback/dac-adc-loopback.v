// ============================================================================
// DAC-ADC Loopback - Phase 1: DAC Triangle Wave Generator
// ============================================================================
//
// This module generates a slow triangle wave on the PMOD DA2's DAC output.
// The output voltage ramps from 0V to 3.3V over 30 seconds, then back down
// to 0V over another 30 seconds (60 second total cycle).
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
// TIMING (12 MHz system clock, NO PLL):
//   - SPI clock: 6 MHz (12 MHz / 2)
//   - Ramp duration: 30 seconds per direction (60 second cycle)
//   - Steps: 4096 per direction (0 to 4095, then 4095 to 0)
//   - Clocks per step: 12,000,000 * 30 / 4096 = 87,890.625 ≈ 87,891
//
// ============================================================================

module dac_adc_loopback (
    input  wire clk,           // 12 MHz system clock

    // DAC SPI interface (PMOD DA2 on PMOD1A)
    output reg  dac_sync_n,    // Chip select (active LOW)
    output reg  dac_din,       // Serial data out
    output reg  dac_sclk       // SPI clock
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
    // REGISTERS
    // ========================================================================

    // Triangle wave generator (updated by step timer, not SPI transfers)
    reg [11:0] dac_value = 12'd0;        // Current DAC value (0-4095)
    reg        ramp_direction = 1'b1;    // 1 = counting up, 0 = counting down

    // Step timer - controls how often dac_value changes
    reg [16:0] step_timer = 17'd0;       // Counts clocks between DAC value changes

    // SPI controller
    reg [15:0] shift_reg = 16'd0;        // 16-bit shift register for SPI data
    reg [3:0]  bit_count = 4'd0;         // Count of bits shifted (0-15)
    reg [3:0]  clk_div = 4'd0;           // Clock divider counter

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

endmodule
