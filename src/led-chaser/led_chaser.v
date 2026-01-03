// =============================================================================
// LED CHASER - A "Knight Rider" Running Light Effect for iCEBreaker FPGA
// =============================================================================
//
// This project creates a classic LED chaser (running lights) effect using the
// 5 LEDs on the iCEBreaker breakout board. The light appears to sweep back and
// forth, like the iconic Knight Rider car from the 1980s TV show.
//
// NEW CONCEPTS IN THIS PROJECT:
// - Multi-bit output buses (controlling multiple LEDs)
// - Position tracking with a counter
// - Bidirectional movement using a direction flag
// - Boundary detection for reversing direction
//
// =============================================================================

// -----------------------------------------------------------------------------
// MODULE DECLARATION
// -----------------------------------------------------------------------------
// Our module has one input (clock) and five outputs (one for each LED).
// We declare the LEDs as separate outputs rather than a bus for clarity in
// the PCF file, where each LED maps to a different physical pin.

module led_chaser (
    input  clk,         // 12 MHz clock input from the iCEBreaker board

    // Five LEDs on the breakout board (active HIGH - 1 = on, 0 = off)
    // Physical arrangement: LED1 LED2 LED3 LED4 LED5
    //                       (grn) (grn) (grn) (grn) (red)
    output LED1,
    output LED2,
    output LED3,
    output LED4,
    output LED5
);

// -----------------------------------------------------------------------------
// CLOCK DIVIDER
// -----------------------------------------------------------------------------
// At 12 MHz, we need to slow things down dramatically for visible movement.
// A 24-bit counter gives us plenty of range to experiment with speeds.
//
// We'll use bit 21 of the counter as our "step" signal:
//   12 MHz / 2^22 = ~2.86 Hz = ~350ms per LED position
//
// This gives a nice, visible sweep rate.

    reg [23:0] counter = 0;

    always @(posedge clk)
        counter <= counter + 1;

// -----------------------------------------------------------------------------
// POSITION REGISTER
// -----------------------------------------------------------------------------
// This 3-bit register tracks which LED is currently lit (0-4 for 5 LEDs).
// We only need 3 bits because 2^3 = 8 values, which covers 0-4 easily.
//
// WHY A POSITION COUNTER INSTEAD OF A SHIFT REGISTER?
// A shift register physically shifts bits left/right, which is elegant but
// requires extra logic to reverse direction. Using a position counter is
// more intuitive for beginners: we just count up or down and decode the
// position into which LED to light.

    reg [2:0] position = 0;     // Which LED is lit (0=LED1, 1=LED2, etc.)

// -----------------------------------------------------------------------------
// DIRECTION FLAG
// -----------------------------------------------------------------------------
// This single bit controls whether we're moving left-to-right or right-to-left.
//   direction = 0: Moving right (position increasing: 0 -> 1 -> 2 -> 3 -> 4)
//   direction = 1: Moving left  (position decreasing: 4 -> 3 -> 2 -> 1 -> 0)
//
// When we hit either end, we flip this flag to reverse direction.

    reg direction = 0;          // 0 = moving right, 1 = moving left

// -----------------------------------------------------------------------------
// PREVIOUS CLOCK STATE (EDGE DETECTION)
// -----------------------------------------------------------------------------
// To move the LED position only once per slow clock cycle, we need to detect
// when our divided clock (counter[21]) transitions from 0 to 1.
//
// We store the previous value and compare it to the current value.
// When prev=0 and current=1, that's a rising edge - time to move!

    reg prev_slow_clk = 0;
    wire slow_clk = counter[21];    // Our divided clock signal (~2.86 Hz)

// -----------------------------------------------------------------------------
// MOVEMENT LOGIC (SEQUENTIAL)
// -----------------------------------------------------------------------------
// On each rising edge of the slow clock:
// 1. Check if we've hit a boundary (position 0 or 4)
// 2. If so, reverse direction
// 3. Move to the next position based on current direction

    always @(posedge clk) begin
        // Store previous slow clock state for edge detection
        prev_slow_clk <= slow_clk;

        // Detect rising edge of slow clock (transition from 0 to 1)
        if (slow_clk && !prev_slow_clk) begin
            // BOUNDARY DETECTION AND DIRECTION REVERSAL
            // When moving right and we reach position 4, reverse to go left
            // When moving left and we reach position 0, reverse to go right
            if (direction == 0) begin
                // Moving right
                if (position == 4) begin
                    direction <= 1;         // Start moving left
                    position <= 3;          // Move to position 3
                end else begin
                    position <= position + 1;   // Continue right
                end
            end else begin
                // Moving left
                if (position == 0) begin
                    direction <= 0;         // Start moving right
                    position <= 1;          // Move to position 1
                end else begin
                    position <= position - 1;   // Continue left
                end
            end
        end
    end

// -----------------------------------------------------------------------------
// OUTPUT DECODING (COMBINATIONAL)
// -----------------------------------------------------------------------------
// Convert the position number into individual LED outputs.
// Only one LED is on at a time - the one matching the current position.
//
// This is a simple "decoder" - it decodes a binary number (position) into
// a "one-hot" output (only one LED active at a time).
//
// == is the equality comparison operator:
//   (position == 0) returns 1 if position equals 0, otherwise 0

    assign LED1 = (position == 0);  // LED1 on when position is 0
    assign LED2 = (position == 1);  // LED2 on when position is 1
    assign LED3 = (position == 2);  // LED3 on when position is 2
    assign LED4 = (position == 3);  // LED4 on when position is 3
    assign LED5 = (position == 4);  // LED5 on when position is 4

endmodule

// =============================================================================
// HOW IT WORKS - TIMING DIAGRAM
// =============================================================================
//
// Time -->
// Position:  0   1   2   3   4   3   2   1   0   1   2   3   4   3 ...
// Direction: R   R   R   R   R   L   L   L   L   R   R   R   R   L ...
//
// LED1:      *   .   .   .   .   .   .   .   *   .   .   .   .   .
// LED2:      .   *   .   .   .   .   .   *   .   *   .   .   .   .
// LED3:      .   .   *   .   .   .   *   .   .   .   *   .   .   *
// LED4:      .   .   .   *   .   *   .   .   .   .   .   *   .   .
// LED5:      .   .   .   .   *   .   .   .   .   .   .   .   *   .
//
// The light sweeps: 1-2-3-4-5-4-3-2-1-2-3-4-5-4-3-2-1 ... (bouncing pattern)
//
// =============================================================================
// EXERCISES TO TRY
// =============================================================================
//
// 1. CHANGE THE SPEED: Try counter[20] for faster or counter[22] for slower
//
// 2. ADD BUTTON CONTROL: Use BTN1 to pause/resume the animation
//
// 3. REVERSE DEFAULT: Start with direction = 1 to begin moving left
//
// 4. MULTIPLE LEDS: Modify the decoder to light 2 adjacent LEDs at once
//    for a "wider" light effect
//
// =============================================================================
