// ============================================================================
// Triangle Wave Generator
// ============================================================================
//
// This module generates a 12-bit triangle wave that ramps up and down.
// The speed is controlled by the CLOCKS_PER_STEP parameter.
//
// WAVEFORM:
//   - Ramps from 0 to 4095, then back down to 0
//   - Each step takes CLOCKS_PER_STEP clock cycles
//   - Full cycle = 2 * 4096 * CLOCKS_PER_STEP clocks
//
// TIMING EXAMPLE (12 MHz clock, 60-second cycle):
//   - 30 seconds up, 30 seconds down
//   - CLOCKS_PER_STEP = 12,000,000 * 30 / 4096 ≈ 87,891
//
// ============================================================================

module triangle_gen #(
    parameter CLOCKS_PER_STEP = 17'd87891   // Clocks between value changes
) (
    input  wire        clk,          // System clock
    output reg  [11:0] value_o       // Current triangle wave value (0-4095)
);

    // ========================================================================
    // REGISTERS
    // ========================================================================

    reg [16:0] step_timer = 17'd0;       // Counts clocks between DAC value changes
    reg        ramp_direction = 1'b1;    // 1 = counting up, 0 = counting down

    // ========================================================================
    // TRIANGLE WAVE GENERATOR
    // ========================================================================
    //
    // This timer runs independently, incrementing or decrementing value_o
    // every CLOCKS_PER_STEP clock cycles.

    initial begin
        value_o = 12'd0;
    end

    always @(posedge clk) begin
        if (step_timer == CLOCKS_PER_STEP - 1) begin
            step_timer <= 17'd0;

            // Update DAC value based on direction
            if (ramp_direction) begin
                // Counting up
                if (value_o == 12'd4095) begin
                    ramp_direction <= 1'b0;  // Switch to counting down
                    value_o <= 12'd4094;
                end else begin
                    value_o <= value_o + 1'b1;
                end
            end else begin
                // Counting down
                if (value_o == 12'd0) begin
                    ramp_direction <= 1'b1;  // Switch to counting up
                    value_o <= 12'd1;
                end else begin
                    value_o <= value_o - 1'b1;
                end
            end
        end else begin
            step_timer <= step_timer + 1'b1;
        end
    end

endmodule
