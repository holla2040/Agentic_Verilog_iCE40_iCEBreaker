// =============================================================================
// BLINKY WITH SWITCHES - Variable Speed LED Blinker
// =============================================================================
// This design reads 3 switches and changes the LED blink rate based on
// which switch is pressed. Only one switch should be pressed at a time.
// =============================================================================

module blinky_switches (
    input  clk,         // 12 MHz clock
    input  sw1,         // Switch 1
    input  sw2,         // Switch 2
    input  sw3,         // Switch 3
    output led          // LED output
);

    reg [23:0] counter = 0;

    // Count up every clock cycle
    always @(posedge clk)
        counter <= counter + 1;

    // Select blink rate based on which switch is pressed:
    //   No switch:  counter[23] = ~0.7 Hz  (slow, default)
    //   Switch 1:   counter[21] = ~2.9 Hz  (medium)
    //   Switch 2:   counter[19] = ~11.4 Hz (fast)
    //   Switch 3:   counter[17] = ~46 Hz   (very fast)
    //
    // Note: Switches active HIGH (pressed = 1, released = 0)

    reg led_out;

    always @(*) begin
        if (sw1)
            led_out = counter[21];      // Medium speed
        else if (sw2)
            led_out = counter[19];      // Fast
        else if (sw3)
            led_out = counter[17];      // Very fast
        else
            led_out = counter[23];      // Slow (default)
    end

    assign led = led_out;

endmodule
