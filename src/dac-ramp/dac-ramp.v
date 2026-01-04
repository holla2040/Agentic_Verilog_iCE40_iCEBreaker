// ============================================================================
// DAC Ramp Generator for PMOD DA2 (DAC121S101)
// ============================================================================
//
// This module generates a triangular ramp waveform on the PMOD DA2's DAC
// output. The output voltage ramps from 0V to 3.3V and back down continuously.
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
// TIMING (60 MHz PLL clock, 30 MHz SPI):
//   - PLL generates 60 MHz from 12 MHz input
//   - SPI clock: 30 MHz (DAC121S101 max is 30 MHz)
//   - 16-bit transfer: ~533 nanoseconds
//   - Update rate: ~1,660,000 updates/second
//   - Triangle wave frequency: ~200 Hz (8192 steps per cycle)
//
// ============================================================================

module dac_ramp (
    input  wire clk,           // 12 MHz system clock (feeds PLL)

    // DAC SPI interface (directly active)
    output reg  dac_sync_n,    // Chip select (active LOW)
    output reg  dac_din,       // Serial data out (directly active)
    output reg  dac_sclk       // SPI clock
);

    // ========================================================================
    // PLL: Generate 60 MHz from 12 MHz input
    // ========================================================================
    //
    // The iCE40 UP5K has a single PLL that can multiply/divide the input clock.
    // We use SB_PLL40_PAD since the clock comes directly from an input pad.
    //
    // PLL Parameters (calculated by icepll -i 12 -o 60):
    //   DIVR = 0   (reference divider)
    //   DIVF = 79  (feedback divider)
    //   DIVQ = 4   (output divider = 2^4 = 16)
    //   F_VCO = 960 MHz (within 533-1066 MHz range)
    //   F_OUT = 12 MHz * 80 / 16 = 60 MHz
    //
    // With 60 MHz clock, we can run SPI at 30 MHz (toggle every clock).
    //

    wire clk_60mhz;            // 60 MHz PLL output
    wire pll_locked;           // PLL lock indicator

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),        // DIVR = 0
        .DIVF(7'b1001111),     // DIVF = 79
        .DIVQ(3'b100),         // DIVQ = 4
        .FILTER_RANGE(3'b001)  // FILTER_RANGE = 1
    ) pll_inst (
        .PACKAGEPIN(clk),      // Clock input from package pin
        .PLLOUTCORE(clk_60mhz),
        .LOCK(pll_locked),
        .RESETB(1'b1),
        .BYPASS(1'b0)
    );

    // ========================================================================
    // TIMING PARAMETERS - 30 MHz SPI MODE
    // ========================================================================
    //
    // PLL output clock: 60 MHz
    // SPI clock: 30 MHz (divide by 2) - maximum for DAC121S101
    //
    // Timing calculation:
    //   - SPI half-period: 1 PLL clock (16.7 ns)
    //   - Full SPI clock cycle: 2 PLL clocks (33.3 ns)
    //   - 16 bits per transfer: 32 PLL clocks
    //   - State machine overhead: ~4 clocks
    //   - Total per transfer: ~36 clocks = 600 ns
    //   - Update rate: 60 MHz / 36 ≈ 1,660,000 updates/sec
    //
    // Triangle wave (step by 1):
    //   - Steps per cycle: 8192 (4096 up + 4096 down)
    //   - Frequency: 1,660,000 / 8192 ≈ 200 Hz
    //
    // Expected on oscilloscope: ~200 Hz triangle wave, 0V to 3.3V

    localparam SPI_HALF_PERIOD = 1;      // Toggle every clock (30 MHz SPI from 60 MHz)

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // The SPI controller uses a simple state machine running at max speed:
    //   IDLE:  Brief pause, SYNC high (1 clock)
    //   LOAD:  Prepare shift register, assert SYNC low (1 clock)
    //   SHIFT: Clock out 16 bits on falling SCLK edges (32 clocks)
    //   DONE:  Release SYNC high, update ramp value (1 clock)

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

    // ========================================================================
    // MAIN STATE MACHINE (runs on 60 MHz PLL clock)
    // ========================================================================

    always @(posedge clk_60mhz) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE STATE: Immediately start next transfer (max speed mode)
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                dac_sync_n <= 1'b1;      // SYNC high (inactive)
                dac_sclk <= 1'b1;        // SCLK idles high (Mode 3 style)
                state <= STATE_LOAD;     // Go immediately to next transfer
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
