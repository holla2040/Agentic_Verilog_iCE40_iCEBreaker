// =============================================================================
// BLINKY - A Simple LED Blinker for the iCEBreaker FPGA Board
// =============================================================================
//
// WHAT IS VERILOG?
// Verilog is a Hardware Description Language (HDL). Unlike software programming
// languages (C, Python, etc.) that describe sequential instructions for a CPU,
// Verilog describes physical hardware circuits. When you "compile" Verilog,
// you're actually configuring real transistors and logic gates inside the FPGA.
//
// WHAT IS AN FPGA?
// An FPGA (Field-Programmable Gate Array) is a chip containing thousands of
// configurable logic blocks and interconnects. You can "program" it to become
// any digital circuit you describe in Verilog.
//
// =============================================================================

// -----------------------------------------------------------------------------
// MODULE DECLARATION
// -----------------------------------------------------------------------------
// A "module" is the basic building block in Verilog - think of it like a chip
// or component with inputs and outputs. Every Verilog design is made of modules.
//
// Syntax: module <name> ( <port_list> );
//
// This module is named "blinky" and has two ports (connections to the outside):
//   - clk: the input clock signal (a wire coming INTO the chip)
//   - led: the output signal (a wire going OUT to an LED)

module blinky (
    input  clk,     // INPUT: Clock signal - a square wave that toggles between
                    // 0 and 1 at 12 MHz (12 million times per second).
                    // This is the "heartbeat" that drives all timing in the circuit.

    output led      // OUTPUT: Controls the LED. When 1, LED is on. When 0, LED is off.
                    // This wire connects to a physical LED on the board.
);

// -----------------------------------------------------------------------------
// REGISTER DECLARATION
// -----------------------------------------------------------------------------
// In Verilog, there are two main data types:
//   - "wire": A physical connection, like a copper trace. Cannot store values.
//   - "reg": A register that can store a value (like a flip-flop circuit).
//
// [23:0] defines a 24-bit wide register (bits numbered 23 down to 0).
// This gives us 2^24 = 16,777,216 possible values (0 to 16,777,215).
//
// "= 0" initializes the counter to zero when the FPGA powers on.
//
// WHY 24 BITS?
// We need to divide the 12 MHz clock down to a human-visible blink rate.
// A 24-bit counter lets us divide by up to 16 million, giving us:
//   12,000,000 Hz / 16,777,216 = ~0.7 Hz (visible blinking)

    reg [23:0] counter = 0;

// -----------------------------------------------------------------------------
// SEQUENTIAL LOGIC BLOCK (The Counter)
// -----------------------------------------------------------------------------
// "always @(posedge clk)" means: "Execute this block every time the clock
// signal transitions from 0 to 1 (the positive/rising edge)."
//
// This is SEQUENTIAL logic - it happens in a specific order, synchronized
// to the clock. Every clock cycle (every 1/12,000,000th of a second), this
// block runs once.
//
// "<=" is the NON-BLOCKING assignment operator. In sequential logic, always
// use "<=" (not "="). This ensures all assignments happen simultaneously
// at the clock edge, which models how real flip-flops work.
//
// "counter + 1" increments the counter. When it reaches its maximum value
// (16,777,215), it wraps around to 0 and starts over.

    always @(posedge clk)
        counter <= counter + 1;

// -----------------------------------------------------------------------------
// COMBINATIONAL LOGIC (The Output)
// -----------------------------------------------------------------------------
// "assign" creates COMBINATIONAL logic - a direct wire connection that
// updates instantly (no clock needed). It's like connecting two wires together.
//
// "counter[21]" extracts bit 21 from the counter (the 22nd bit, since we
// count from 0). This single bit toggles between 0 and 1.
//
// WHY BIT 21?
// Each bit in the counter toggles at a different rate:
//   - Bit 0:  toggles at 12 MHz / 2^1  = 6,000,000 Hz (way too fast to see)
//   - Bit 10: toggles at 12 MHz / 2^11 = ~5,859 Hz   (still too fast)
//   - Bit 21: toggles at 12 MHz / 2^22 = ~2.86 Hz    (visible blinking!)
//   - Bit 23: toggles at 12 MHz / 2^24 = ~0.71 Hz    (slow blinking)
//
// The LED output directly follows bit 21 of the counter, so the LED blinks
// at approximately 2.86 Hz (about 3 times per second).

    assign led = counter[21];

// -----------------------------------------------------------------------------
// END OF MODULE
// -----------------------------------------------------------------------------
// "endmodule" marks the end of our module definition.
// Everything between "module" and "endmodule" describes the blinky circuit.

endmodule

// =============================================================================
// HOW THIS BECOMES HARDWARE
// =============================================================================
//
// When you run "make", the following happens:
//
// 1. SYNTHESIS (yosys): Converts this Verilog into a netlist of logic gates
//    (AND, OR, NOT, flip-flops, etc.)
//
// 2. PLACE & ROUTE (nextpnr): Decides which physical logic blocks inside the
//    FPGA will implement each gate, and how to connect them with wires.
//
// 3. BITSTREAM GENERATION (icepack): Creates a binary file that configures
//    the FPGA's switches to create your circuit.
//
// 4. PROGRAMMING (iceprog): Uploads the bitstream to the FPGA. The circuit
//    starts running immediately - there's no CPU executing instructions,
//    just electrons flowing through the logic gates you designed!
//
// =============================================================================
