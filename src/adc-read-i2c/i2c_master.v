// ============================================================================
// I2C Master - Low-Level I2C Operations for iCE40 UP5K
// ============================================================================
//
// This module implements basic I2C master operations using the iCE40's SB_IO
// primitive configured for tristate operation to emulate open-drain signaling.
//
// OPEN-DRAIN EMULATION:
//   I2C requires open-drain outputs where:
//   - To output LOW:  Enable output (drives pin to ground via DOUT=0)
//   - To output HIGH: Disable output (external pull-up pulls pin high)
//   This allows multiple devices to share the bus and enables clock stretching.
//
//   We use SB_IO with PIN_TYPE=6'b1010_01 (tristate output + simple input)
//   and always drive 0, using OUTPUT_ENABLE to control the line.
//
// COMMAND INTERFACE:
//   cmd[2:0]    - Command to execute:
//                   000 = IDLE (do nothing)
//                   001 = START (generate start condition)
//                   010 = WRITE (transmit byte, check ACK from slave)
//                   011 = READ (receive byte, send ACK/NACK to slave)
//                   100 = STOP (generate stop condition)
//   cmd_start   - Pulse HIGH for one clock to begin command
//   busy        - HIGH while command is executing
//   ack_error   - HIGH if NACK received after WRITE
//   timeout     - HIGH if command did not complete within timeout period
//   tx_data     - Byte to transmit (for WRITE command)
//   rx_data     - Byte received (from READ command)
//   send_nack   - For READ: 1=send NACK after read, 0=send ACK
//
// TIMEOUT DETECTION:
//   If any command takes longer than ~1ms (12000 clocks), the timeout flag
//   is set and the module returns to IDLE. This detects stuck bus conditions
//   such as a slave holding SCL low indefinitely (clock stretching gone wrong).
//
// I2C TIMING (Fast Mode 400 kHz):
//   Clock period: 2.5 µs = 30 system clocks at 12 MHz
//   Half period:  1.25 µs = 15 system clocks
//
// ============================================================================

module i2c_master (
    input  wire       clk,          // 12 MHz system clock

    // I2C bus pins
    inout  wire       scl,          // I2C clock (package pin)
    inout  wire       sda,          // I2C data (package pin)

    // Command interface
    input  wire [2:0] cmd,          // Command to execute
    input  wire       cmd_start,    // Pulse to begin command
    output reg        busy,         // HIGH while executing
    output reg        ack_error,    // HIGH if NACK received (WRITE)
    output reg        timeout,      // HIGH if command timed out (bus stuck)

    // Data interface
    input  wire [7:0] tx_data,      // Byte to transmit (WRITE)
    output reg  [7:0] rx_data,      // Byte received (READ)
    input  wire       send_nack     // For READ: 1=NACK, 0=ACK
);

    // ========================================================================
    // COMMAND DEFINITIONS
    // ========================================================================

    localparam CMD_IDLE  = 3'b000;
    localparam CMD_START = 3'b001;
    localparam CMD_WRITE = 3'b010;
    localparam CMD_READ  = 3'b011;
    localparam CMD_STOP  = 3'b100;

    // ========================================================================
    // I2C TIMING PARAMETERS
    // ========================================================================
    // 12 MHz / 400 kHz = 30 clocks per I2C bit
    // We use slightly slower timing for reliability

    localparam HALF_PERIOD = 15;    // Clocks for SCL low or high phase
    localparam QUARTER_PERIOD = 7;  // For setup/hold times

    // ========================================================================
    // TIMEOUT PARAMETER
    // ========================================================================
    // If a command takes longer than TIMEOUT_CLOCKS, abort and set timeout flag.
    // At 400kHz, a single byte (8 bits + ACK) takes ~22.5µs.
    // 1ms timeout (12000 clocks) gives plenty of margin for clock stretching.

    localparam TIMEOUT_CLOCKS = 14'd12000;  // ~1ms at 12 MHz

    // ========================================================================
    // OPEN-DRAIN I/O PRIMITIVES (using SB_IO in tristate mode)
    // ========================================================================
    // SB_IO configured for tristate output emulates open-drain:
    // - OUTPUT_ENABLE=1, D_OUT_0=0: Pin driven LOW
    // - OUTPUT_ENABLE=0: Pin floats, external pull-up brings it HIGH
    //
    // PIN_TYPE = 6'b1010_01:
    //   [1:0] = 01: Simple (non-registered) input
    //   [5:2] = 1010: Tristate output, directly from D_OUT_0/OUTPUT_ENABLE

    reg scl_oe;     // 1=drive LOW, 0=release to pull-up
    reg sda_oe;     // 1=drive LOW, 0=release to pull-up
    wire scl_in;    // Read actual SCL state
    wire sda_in;    // Read actual SDA state

    SB_IO #(
        .PIN_TYPE(6'b1010_01)  // Tristate output + simple input
    ) scl_io (
        .PACKAGE_PIN(scl),
        .OUTPUT_ENABLE(scl_oe),
        .D_OUT_0(1'b0),        // Always drive 0 when enabled
        .D_IN_0(scl_in)
    );

    SB_IO #(
        .PIN_TYPE(6'b1010_01)
    ) sda_io (
        .PACKAGE_PIN(sda),
        .OUTPUT_ENABLE(sda_oe),
        .D_OUT_0(1'b0),
        .D_IN_0(sda_in)
    );

    // ========================================================================
    // STATE MACHINE
    // ========================================================================

    localparam STATE_IDLE           = 5'd0;
    localparam STATE_START_1        = 5'd1;   // SDA goes LOW while SCL HIGH
    localparam STATE_START_2        = 5'd2;   // SCL goes LOW
    localparam STATE_WRITE_BIT      = 5'd3;   // Set SDA, then raise SCL
    localparam STATE_WRITE_HIGH     = 5'd4;   // SCL HIGH period
    localparam STATE_WRITE_LOW      = 5'd5;   // SCL LOW, prepare next bit
    localparam STATE_ACK_SETUP      = 5'd6;   // Release SDA for ACK
    localparam STATE_ACK_HIGH       = 5'd7;   // SCL HIGH, sample ACK
    localparam STATE_ACK_LOW        = 5'd8;   // SCL LOW after ACK
    localparam STATE_STOP_1         = 5'd9;   // SDA LOW, SCL LOW
    localparam STATE_STOP_2         = 5'd10;  // SCL goes HIGH
    localparam STATE_STOP_3         = 5'd11;  // SDA goes HIGH (stop condition)
    // READ states
    localparam STATE_READ_BIT       = 5'd12;  // Release SDA, prepare to read
    localparam STATE_READ_HIGH      = 5'd13;  // SCL HIGH, sample SDA
    localparam STATE_READ_LOW       = 5'd14;  // SCL LOW, shift in bit
    localparam STATE_SEND_ACK_SETUP = 5'd15;  // Set SDA for ACK/NACK
    localparam STATE_SEND_ACK_HIGH  = 5'd16;  // SCL HIGH for ACK/NACK
    localparam STATE_SEND_ACK_LOW   = 5'd17;  // SCL LOW, complete

    reg [4:0] state;

    // ========================================================================
    // INTERNAL REGISTERS
    // ========================================================================

    reg [4:0] clk_count;    // Clock divider counter (0-31)
    reg [2:0] bit_count;    // Bit counter for byte transmission (0-7)
    reg [7:0] shift_reg;    // Shift register for data
    reg [2:0] cmd_latch;    // Latched command
    reg       nack_latch;   // Latched send_nack value
    reg [13:0] timeout_cnt; // Timeout counter (counts clocks since command started)

    // ========================================================================
    // INITIALIZATION
    // ========================================================================
    // At power-up, release both lines so bus starts in idle state (both HIGH)

    initial begin
        scl_oe = 1'b0;      // Released (HIGH via pull-up)
        sda_oe = 1'b0;      // Released (HIGH via pull-up)
        state = STATE_IDLE;
        busy = 1'b0;
        ack_error = 1'b0;
        timeout = 1'b0;
        rx_data = 8'b0;
        clk_count = 0;
        bit_count = 0;
        shift_reg = 0;
        cmd_latch = 0;
        nack_latch = 0;
        timeout_cnt = 0;
    end

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        // --------------------------------------------------------------------
        // TIMEOUT DETECTION
        // --------------------------------------------------------------------
        // If not idle, increment timeout counter. If it overflows, abort.
        // This catches stuck bus conditions (e.g., slave holding SCL low).
        if (state != STATE_IDLE) begin
            if (timeout_cnt == TIMEOUT_CLOCKS - 1) begin
                // Timeout! Release bus and return to IDLE
                timeout <= 1'b1;
                scl_oe <= 1'b0;
                sda_oe <= 1'b0;
                busy <= 1'b0;
                state <= STATE_IDLE;
                timeout_cnt <= 0;
            end else begin
                timeout_cnt <= timeout_cnt + 1;
            end
        end

        case (state)
            // ----------------------------------------------------------------
            // IDLE: Wait for command
            // ----------------------------------------------------------------
            // IMPORTANT: Do NOT release lines here unconditionally!
            // After START, SCL must stay LOW. After WRITE/READ, SCL must stay LOW.
            // Lines are only released after STOP or at power-up (via initial).
            STATE_IDLE: begin
                busy <= 1'b0;
                clk_count <= 0;
                timeout_cnt <= 0;  // Reset timeout counter when idle

                // Note: scl_oe and sda_oe maintain their current state
                // They are only changed when starting a new command

                if (cmd_start) begin
                    cmd_latch <= cmd;
                    busy <= 1'b1;
                    timeout <= 1'b0;  // Clear timeout flag on new command

                    case (cmd)
                        CMD_START: begin
                            // For START, first release both lines to ensure bus is idle
                            // (This is a repeated START if we're mid-transaction)
                            scl_oe <= 1'b0;
                            sda_oe <= 1'b0;
                            state <= STATE_START_1;
                        end

                        CMD_WRITE: begin
                            // SCL should already be LOW from previous START or WRITE
                            shift_reg <= tx_data;
                            bit_count <= 0;
                            state <= STATE_WRITE_BIT;
                        end

                        CMD_READ: begin
                            // SCL should already be LOW
                            // Release SDA so slave can drive it
                            sda_oe <= 1'b0;
                            shift_reg <= 8'b0;
                            bit_count <= 0;
                            nack_latch <= send_nack;
                            state <= STATE_READ_BIT;
                        end

                        CMD_STOP: begin
                            // Ensure SDA is LOW before STOP sequence
                            sda_oe <= 1'b1;
                            scl_oe <= 1'b1;
                            state <= STATE_STOP_1;
                        end

                        default: begin
                            busy <= 1'b0;
                        end
                    endcase
                end
            end

            // ================================================================
            // START CONDITION: SDA HIGH->LOW while SCL is HIGH
            // ================================================================

            // STATE_START_1: SDA goes LOW while SCL stays HIGH
            STATE_START_1: begin
                scl_oe <= 1'b0;  // SCL HIGH (released)

                if (clk_count < QUARTER_PERIOD) begin
                    // Setup time - ensure SCL is HIGH
                    clk_count <= clk_count + 1;
                end else begin
                    // Pull SDA LOW - this is the START condition
                    sda_oe <= 1'b1;
                    clk_count <= 0;
                    state <= STATE_START_2;
                end
            end

            // STATE_START_2: Hold SDA LOW, then pull SCL LOW
            STATE_START_2: begin
                sda_oe <= 1'b1;  // Keep SDA LOW

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    // Pull SCL LOW to complete START
                    scl_oe <= 1'b1;
                    clk_count <= 0;
                    state <= STATE_IDLE;
                end
            end

            // ================================================================
            // WRITE BYTE: Send 8 bits MSB first, then read ACK from slave
            // ================================================================

            // STATE_WRITE_BIT: Set SDA to bit value, SCL stays LOW
            STATE_WRITE_BIT: begin
                scl_oe <= 1'b1;  // SCL LOW

                // Set SDA to MSB of shift register
                // sda_oe=1 drives LOW, sda_oe=0 releases HIGH
                sda_oe <= ~shift_reg[7];

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_WRITE_HIGH;
                end
            end

            // STATE_WRITE_HIGH: SCL goes HIGH, hold data
            STATE_WRITE_HIGH: begin
                scl_oe <= 1'b0;  // Release SCL (goes HIGH)

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_WRITE_LOW;
                end
            end

            // STATE_WRITE_LOW: SCL goes LOW, prepare next bit
            STATE_WRITE_LOW: begin
                scl_oe <= 1'b1;  // Pull SCL LOW

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;

                    if (bit_count == 7) begin
                        // All 8 bits sent, now read ACK
                        state <= STATE_ACK_SETUP;
                    end else begin
                        // More bits to send
                        bit_count <= bit_count + 1;
                        shift_reg <= shift_reg << 1;
                        state <= STATE_WRITE_BIT;
                    end
                end
            end

            // STATE_ACK_SETUP: Release SDA so slave can respond
            STATE_ACK_SETUP: begin
                scl_oe <= 1'b1;  // SCL LOW
                sda_oe <= 1'b0;  // Release SDA (slave will pull LOW for ACK)

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_ACK_HIGH;
                end
            end

            // STATE_ACK_HIGH: SCL HIGH, sample SDA for ACK/NACK
            STATE_ACK_HIGH: begin
                scl_oe <= 1'b0;  // Release SCL (goes HIGH)

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;

                    // Sample ACK near middle of HIGH period
                    if (clk_count == QUARTER_PERIOD) begin
                        // SDA LOW = ACK, SDA HIGH = NACK
                        ack_error <= sda_in;  // sda_in=1 means NACK (error)
                    end
                end else begin
                    clk_count <= 0;
                    state <= STATE_ACK_LOW;
                end
            end

            // STATE_ACK_LOW: SCL goes LOW, byte complete
            STATE_ACK_LOW: begin
                scl_oe <= 1'b1;  // Pull SCL LOW

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    state <= STATE_IDLE;
                end
            end

            // ================================================================
            // READ BYTE: Receive 8 bits MSB first, then send ACK/NACK to slave
            // ================================================================

            // STATE_READ_BIT: SCL LOW, SDA released, prepare to sample
            STATE_READ_BIT: begin
                scl_oe <= 1'b1;  // SCL LOW
                sda_oe <= 1'b0;  // Release SDA (slave drives it)

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_READ_HIGH;
                end
            end

            // STATE_READ_HIGH: SCL goes HIGH, sample SDA
            STATE_READ_HIGH: begin
                scl_oe <= 1'b0;  // Release SCL (goes HIGH)

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;

                    // Sample data near middle of HIGH period
                    if (clk_count == QUARTER_PERIOD) begin
                        // Shift in the bit (MSB first)
                        shift_reg <= {shift_reg[6:0], sda_in};
                    end
                end else begin
                    clk_count <= 0;
                    state <= STATE_READ_LOW;
                end
            end

            // STATE_READ_LOW: SCL goes LOW, check if more bits
            STATE_READ_LOW: begin
                scl_oe <= 1'b1;  // Pull SCL LOW

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;

                    if (bit_count == 7) begin
                        // All 8 bits received, copy to rx_data
                        rx_data <= shift_reg;
                        // Now send ACK or NACK
                        state <= STATE_SEND_ACK_SETUP;
                    end else begin
                        // More bits to read
                        bit_count <= bit_count + 1;
                        state <= STATE_READ_BIT;
                    end
                end
            end

            // STATE_SEND_ACK_SETUP: Set SDA for ACK (LOW) or NACK (HIGH)
            STATE_SEND_ACK_SETUP: begin
                scl_oe <= 1'b1;  // SCL LOW

                // For ACK: pull SDA LOW (sda_oe=1)
                // For NACK: release SDA HIGH (sda_oe=0)
                sda_oe <= ~nack_latch;

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_SEND_ACK_HIGH;
                end
            end

            // STATE_SEND_ACK_HIGH: SCL HIGH, hold ACK/NACK
            STATE_SEND_ACK_HIGH: begin
                scl_oe <= 1'b0;  // Release SCL (goes HIGH)

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_SEND_ACK_LOW;
                end
            end

            // STATE_SEND_ACK_LOW: SCL goes LOW, read complete
            STATE_SEND_ACK_LOW: begin
                scl_oe <= 1'b1;  // Pull SCL LOW

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    state <= STATE_IDLE;
                end
            end

            // ================================================================
            // STOP CONDITION: SDA LOW->HIGH while SCL is HIGH
            // ================================================================

            // STATE_STOP_1: Ensure SDA LOW, SCL LOW
            STATE_STOP_1: begin
                sda_oe <= 1'b1;  // SDA LOW
                scl_oe <= 1'b1;  // SCL LOW

                if (clk_count < QUARTER_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_STOP_2;
                end
            end

            // STATE_STOP_2: Release SCL (goes HIGH), keep SDA LOW
            STATE_STOP_2: begin
                sda_oe <= 1'b1;  // Keep SDA LOW
                scl_oe <= 1'b0;  // Release SCL (goes HIGH)

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    clk_count <= 0;
                    state <= STATE_STOP_3;
                end
            end

            // STATE_STOP_3: Release SDA (goes HIGH) - STOP condition
            STATE_STOP_3: begin
                scl_oe <= 1'b0;  // Keep SCL HIGH
                sda_oe <= 1'b0;  // Release SDA (goes HIGH) - STOP!

                if (clk_count < HALF_PERIOD) begin
                    clk_count <= clk_count + 1;
                end else begin
                    state <= STATE_IDLE;
                end
            end

            // ----------------------------------------------------------------
            // DEFAULT: Return to idle
            // ----------------------------------------------------------------
            default: begin
                state <= STATE_IDLE;
                scl_oe <= 1'b0;
                sda_oe <= 1'b0;
                busy <= 1'b0;
            end
        endcase
    end

endmodule
