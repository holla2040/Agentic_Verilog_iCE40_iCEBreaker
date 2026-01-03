// =============================================================================
// PWM BREATHE - LED Pulsating Glow for iCEBreaker FPGA
// =============================================================================
//
// This design uses Pulse Width Modulation (PWM) to create a smooth "breathing"
// effect on an LED - gradually fading in and out like a sleeping indicator.
//
// WHAT IS PWM?
// Pulse Width Modulation rapidly switches the LED on and off at a frequency
// too fast for the eye to see (~47 kHz). By varying the ratio of ON time to
// OFF time (the "duty cycle"), we control perceived brightness:
//
//   100% duty: |████████████████| = Full brightness (always ON)
//    50% duty: |████████        | = Half brightness
//    25% duty: |████            | = Quarter brightness
//     0% duty: |                | = Off (always OFF)
//
// The eye averages these rapid pulses, perceiving smooth brightness levels.
//
// =============================================================================

module pwm_breathe (
    input  clk,     // 12 MHz clock
    output led      // PWM-controlled LED output
);

// -----------------------------------------------------------------------------
// PWM COUNTER - Creates the PWM timebase
// -----------------------------------------------------------------------------
// This 8-bit counter cycles 0->255 continuously at high speed.
// At 12 MHz clock, it completes a full cycle every 256 clocks:
//   12,000,000 / 256 = 46,875 Hz (PWM frequency)
//
// This is fast enough that the human eye cannot perceive flicker.

    reg [7:0] pwm_counter = 0;

    always @(posedge clk)
        pwm_counter <= pwm_counter + 1;

// -----------------------------------------------------------------------------
// BRIGHTNESS LEVEL - Current duty cycle (0-255)
// -----------------------------------------------------------------------------
// This register holds the current brightness level.
//   0   = LED always off (0% duty cycle)
//   127 = LED on half the time (50% duty cycle)
//   255 = LED always on (100% duty cycle)
//
// The breathing logic below slowly ramps this value up and down.

    reg [7:0] brightness = 0;

// -----------------------------------------------------------------------------
// BREATHING RATE DIVIDER
// -----------------------------------------------------------------------------
// We need to change brightness slowly enough to see a smooth fade.
// Target: ~2 second full cycle (fade up + fade down)
//
// Math:
//   - 512 brightness changes per cycle (0->255->0)
//   - 2 seconds = 24,000,000 clock cycles
//   - 24,000,000 / 512 = 46,875 clocks per brightness step
//
// We use a 16-bit counter that overflows at 65,536 clocks, giving us
// a slightly slower ~2.8 second cycle (65536 * 512 / 12M = 2.8s).
// This creates a relaxed, calming breathing effect.

    reg [15:0] breath_counter = 0;

// -----------------------------------------------------------------------------
// DIRECTION FLAG - Fading up or down?
// -----------------------------------------------------------------------------
// 0 = brightness increasing (fading in)
// 1 = brightness decreasing (fading out)

    reg direction = 0;

// -----------------------------------------------------------------------------
// BREATHING LOGIC - Slowly ramp brightness up and down
// -----------------------------------------------------------------------------
// Every time breath_counter overflows (65536 clocks), we either increment
// or decrement brightness depending on the direction. When brightness hits
// the limits (0 or 255), we reverse direction.

    always @(posedge clk) begin
        breath_counter <= breath_counter + 1;

        // When breath_counter wraps around to 0, update brightness
        if (breath_counter == 0) begin
            if (direction == 0) begin
                // Fading in (getting brighter)
                if (brightness == 255)
                    direction <= 1;         // Hit max, start fading out
                else
                    brightness <= brightness + 1;
            end else begin
                // Fading out (getting dimmer)
                if (brightness == 0)
                    direction <= 0;         // Hit min, start fading in
                else
                    brightness <= brightness - 1;
            end
        end
    end

// -----------------------------------------------------------------------------
// PWM OUTPUT - Generate the LED signal
// -----------------------------------------------------------------------------
// The LED is ON when pwm_counter is less than brightness.
// This creates a pulse whose width (duty cycle) matches the brightness level.
//
// Example with brightness = 64 (25% duty):
//   pwm_counter:  0  1  2 ... 63 64 65 ... 255
//   LED output:   1  1  1 ...  1  0  0 ...   0
//                 |<-- ON -->|<--- OFF --->|
//
// Higher brightness = wider ON pulse = brighter LED

    assign led = (pwm_counter < brightness);

endmodule

// =============================================================================
// HOW THE BREATHING EFFECT WORKS
// =============================================================================
//
// Time →
//
// Brightness:  0 ──────────── 255 ──────────── 0 ──────────── 255 ...
//              │    fade in    │   fade out    │    fade in    │
//              |<──── ~1.4s ───>|<──── ~1.4s ──>|
//              |<────────── ~2.8s cycle ───────>|
//
// The LED smoothly transitions from off to full brightness and back,
// creating a calming "breathing" or "pulsing" glow effect.
//
// =============================================================================
