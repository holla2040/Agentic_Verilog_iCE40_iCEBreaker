// ============================================================================
// UART TX - Serial Transmitter for iCEBreaker FPGA
// ============================================================================
//
// This module implements a UART (Universal Asynchronous Receiver/Transmitter)
// transmitter that sends "Hello from iCEBreaker!" to your PC every second.
//
// WHAT IS UART?
// -------------
// UART is one of the oldest and simplest serial communication protocols.
// It sends data one bit at a time over a single wire. Unlike SPI or I2C,
// UART doesn't need a clock wire - both sides agree on a "baud rate"
// (bits per second) ahead of time.
//
// THE UART FRAME FORMAT:
// ----------------------
//     IDLE    START   D0  D1  D2  D3  D4  D5  D6  D7   STOP   IDLE
//     ____          ___     ___         ___     ___ ___________
//         |________|   |___|   |_______|   |___|   |
//     HIGH  LOW    <-------- 8 data bits -------->  HIGH
//
//   - IDLE: Line sits HIGH when nothing is being sent
//   - START bit: Always LOW, tells receiver "data is coming!"
//   - DATA bits: 8 bits sent LSB (least significant bit) first
//   - STOP bit: Always HIGH, gives receiver time to process
//
// BAUD RATE:
// ----------
// We use 115200 baud (bits per second), a very common rate.
// Each bit lasts: 1/115200 seconds ≈ 8.68 microseconds
// With a 12 MHz clock: 12,000,000 / 115200 ≈ 104 clock cycles per bit
//
// HOW THIS MODULE WORKS:
// ----------------------
// 1. A timer counts to ~1 second, then triggers transmission
// 2. Characters are stored in a ROM (read-only memory) array
// 3. A state machine sends each character bit-by-bit
// 4. After all characters are sent, wait for the next 1-second trigger
// 5. An LED blinks each time a message is sent
//
// ============================================================================

module uart_tx (
    input  wire clk,    // 12 MHz clock from pin 35
    output reg  tx,     // UART transmit pin (directly to FTDI chip)
    output reg  led     // Activity LED - blinks when sending
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    //
    // These are calculated for 12 MHz clock and 115200 baud:
    //   Clocks per bit = 12,000,000 / 115,200 = 104.166...
    //   We use 104, which gives us 115,384 baud (0.16% error - acceptable)
    //
    // The FTDI chip is very tolerant of timing errors up to ~3%, so this
    // slight deviation is fine.

    localparam CLOCKS_PER_BIT = 104;        // Clock cycles for one UART bit
    localparam CLOCKS_PER_SECOND = 12000000; // 12 MHz = 12 million clocks/sec

    // ========================================================================
    // THE MESSAGE TO SEND
    // ========================================================================
    //
    // In Verilog, we can create a ROM by initializing a reg array.
    // This stores the ASCII codes for each character.
    //
    // ASCII reminder: 'H' = 72, 'e' = 101, 'l' = 108, etc.
    // \r = 13 (carriage return), \n = 10 (newline)
    //
    // The message ends with \r\n so it displays nicely in terminals.

    localparam MSG_LEN = 24;  // "Hello from iCEBreaker!\r\n" = 24 characters

    // ROM storing our message - each entry is 8 bits (one ASCII character)
    // Index:  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22  23
    // Char:   H   e   l   l   o       f   r   o   m       i   C   E   B   r   e   a   k   e   r   !  \r  \n
    reg [7:0] message [0:MSG_LEN-1];

    initial begin
        message[0]  = "H";
        message[1]  = "e";
        message[2]  = "l";
        message[3]  = "l";
        message[4]  = "o";
        message[5]  = " ";
        message[6]  = "f";
        message[7]  = "r";
        message[8]  = "o";
        message[9]  = "m";
        message[10] = " ";
        message[11] = "i";
        message[12] = "C";
        message[13] = "E";
        message[14] = "B";
        message[15] = "r";
        message[16] = "e";
        message[17] = "a";
        message[18] = "k";
        message[19] = "e";
        message[20] = "r";
        message[21] = "!";
        message[22] = 8'h0D;  // \r (carriage return)
        message[23] = 8'h0A;  // \n (newline)
    end

    // ========================================================================
    // STATE MACHINE STATES
    // ========================================================================
    //
    // The transmitter is a state machine that cycles through these states:
    //
    //   IDLE ──(timer expires)──> START ──> DATA ──> STOP ──> IDLE
    //                                         │        │
    //                                         └──(next char if more)──┘
    //
    // Using localparam for states makes the code self-documenting.

    localparam STATE_IDLE  = 3'd0;  // Waiting for trigger
    localparam STATE_START = 3'd1;  // Sending start bit (LOW)
    localparam STATE_DATA  = 3'd2;  // Sending 8 data bits
    localparam STATE_STOP  = 3'd3;  // Sending stop bit (HIGH)

    reg [2:0] state;  // Current state (needs 3 bits for 4 states)

    // ========================================================================
    // COUNTERS AND REGISTERS
    // ========================================================================

    // Baud rate counter - counts clock cycles within each bit period
    // Needs to count up to 104, so 7 bits is enough (0-127)
    reg [6:0] baud_counter;

    // Bit counter - which bit of the byte we're sending (0-7)
    reg [2:0] bit_index;

    // Character index - which character in the message we're sending
    reg [4:0] char_index;  // 5 bits can count 0-31, enough for 24 chars

    // Current character being transmitted
    reg [7:0] tx_byte;

    // Timer for 1-second delay between messages
    // Needs to count to 12 million, so 24 bits required (2^24 = 16 million)
    reg [23:0] delay_counter;

    // Flag indicating we should start transmitting
    reg tx_trigger;

    // ========================================================================
    // 1-SECOND DELAY TIMER
    // ========================================================================
    //
    // This creates a trigger pulse every second to start a new message.
    // The counter counts from 0 to CLOCKS_PER_SECOND-1, then resets.

    always @(posedge clk) begin
        if (delay_counter == CLOCKS_PER_SECOND - 1) begin
            delay_counter <= 0;
            tx_trigger <= 1;  // Trigger transmission
        end else begin
            delay_counter <= delay_counter + 1;
            tx_trigger <= 0;  // Clear trigger after one clock
        end
    end

    // ========================================================================
    // UART TRANSMIT STATE MACHINE
    // ========================================================================
    //
    // This is the heart of the UART transmitter. It handles:
    //   1. Waiting for a trigger to start
    //   2. Sending start bit
    //   3. Sending 8 data bits (LSB first)
    //   4. Sending stop bit
    //   5. Moving to next character or returning to idle
    //
    // KEY CONCEPT: The 'tx' output directly drives the TX pin.
    // Whatever value we assign to 'tx' appears on the wire immediately.

    always @(posedge clk) begin
        case (state)
            // ----------------------------------------------------------------
            // IDLE STATE: Wait for trigger, keep TX line HIGH
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                tx <= 1;          // UART idle state is HIGH
                baud_counter <= 0;
                bit_index <= 0;

                if (tx_trigger) begin
                    // Start sending! Load first character and begin
                    char_index <= 0;
                    tx_byte <= message[0];
                    state <= STATE_START;
                    led <= 1;     // Turn on LED to show we're transmitting
                end else begin
                    led <= 0;     // LED off when idle
                end
            end

            // ----------------------------------------------------------------
            // START STATE: Send start bit (LOW) for one bit period
            // ----------------------------------------------------------------
            STATE_START: begin
                tx <= 0;  // Start bit is always LOW

                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    // Start bit complete, move to data
                    baud_counter <= 0;
                    state <= STATE_DATA;
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DATA STATE: Send 8 data bits, LSB first
            // ----------------------------------------------------------------
            //
            // LSB first means we send bit 0 first, then bit 1, etc.
            // tx_byte[0] is sent, then we shift right to get the next bit.
            //
            STATE_DATA: begin
                tx <= tx_byte[0];  // Send the LSB

                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    baud_counter <= 0;

                    if (bit_index == 7) begin
                        // All 8 bits sent, move to stop bit
                        bit_index <= 0;
                        state <= STATE_STOP;
                    end else begin
                        // More bits to send - shift right to get next bit
                        bit_index <= bit_index + 1;
                        tx_byte <= tx_byte >> 1;  // Shift right by 1
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // STOP STATE: Send stop bit (HIGH) for one bit period
            // ----------------------------------------------------------------
            STATE_STOP: begin
                tx <= 1;  // Stop bit is always HIGH

                if (baud_counter == CLOCKS_PER_BIT - 1) begin
                    baud_counter <= 0;

                    if (char_index == MSG_LEN - 1) begin
                        // All characters sent! Return to idle
                        state <= STATE_IDLE;
                    end else begin
                        // More characters to send - load next one
                        char_index <= char_index + 1;
                        tx_byte <= message[char_index + 1];
                        state <= STATE_START;
                    end
                end else begin
                    baud_counter <= baud_counter + 1;
                end
            end

            // ----------------------------------------------------------------
            // DEFAULT: Safety net - shouldn't happen but go to idle if it does
            // ----------------------------------------------------------------
            default: begin
                state <= STATE_IDLE;
                tx <= 1;
            end
        endcase
    end

endmodule

// ============================================================================
// HOW TO TEST THIS PROJECT:
// ============================================================================
//
// 1. Build the project:
//      make
//
// 2. Program the FPGA:
//      make prog
//
// 3. Find the serial port (on Linux):
//      ls /dev/ttyUSB*
//    Usually it's /dev/ttyUSB1 (USB0 is for programming, USB1 is UART)
//
// 4. Open a terminal program at 115200 baud:
//      screen /dev/ttyUSB1 115200
//    Or:
//      picocom -b 115200 /dev/ttyUSB1
//    Or:
//      minicom -D /dev/ttyUSB1 -b 115200
//
// 5. You should see "Hello from iCEBreaker!" appearing every second!
//    The accent LED on the board will blink each time a message is sent.
//
// 6. To exit screen, press Ctrl+A then K, then Y to confirm.
//    To exit picocom, press Ctrl+A then Ctrl+X.
//
// ============================================================================
// LEARNING EXERCISES:
// ============================================================================
//
// 1. CHANGE THE MESSAGE:
//    Modify the message[] array to send your own text. Remember to update
//    MSG_LEN to match your new message length!
//
// 2. CHANGE THE BAUD RATE:
//    Try 9600 baud: CLOCKS_PER_BIT = 12000000 / 9600 = 1250
//    Don't forget to change your terminal settings to match!
//
// 3. SEND FASTER:
//    Reduce CLOCKS_PER_SECOND to make messages appear more frequently.
//    Try 6000000 for 2 messages per second.
//
// 4. ADD A COUNTER:
//    Instead of a fixed message, send an incrementing number like "Count: 42"
//    This requires converting binary to ASCII digits (more advanced!)
//
// ============================================================================
