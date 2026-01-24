// ============================================================================
// I2C Master Controller (with Synchronous Reset)
// ============================================================================
//
// A simple I2C master for communicating with I2C slave devices.
// Uses SB_IO primitives for proper open-drain signaling on iCE40.
//
// I2C BASICS:
//   - Two wires: SCL (clock) and SDA (data)
//   - Both are open-drain with external pull-ups
//   - Master controls SCL, both master and slave can pull SDA low
//   - Data changes when SCL is LOW, sampled when SCL is HIGH
//
// OPEN-DRAIN IMPLEMENTATION:
//   - To drive LOW:  output_enable = 1, output = 0
//   - To release (HIGH via pull-up): output_enable = 0
//   - Never actively drive HIGH!
//
// RESET BEHAVIOR:
//   - When rst is HIGH, module returns to idle state
//   - SCL and SDA are released (output_enable = 0), allowing pull-ups
//     to bring lines HIGH for bus recovery
//   - busy_o is cleared to indicate ready state
//
// COMMAND INTERFACE:
//   - Load cmd_i and data_i, assert start_i for one clock
//   - busy_o goes HIGH while command executes
//   - When busy_o falls, check ack_o for write commands
//
// COMMANDS:
//   CMD_START (1): Generate START condition (SDA falls while SCL HIGH)
//   CMD_STOP  (2): Generate STOP condition (SDA rises while SCL HIGH)
//   CMD_WRITE (3): Write 8 bits, return ACK status in ack_o
//   CMD_READ  (4): Read 8 bits into data_o, send ACK/NACK based on ack_i
//
// TIMING:
//   - I2C standard mode: 100 kHz
//   - At 12 MHz system clock: half-period = 60 clocks (120 clocks per bit)
//
// ============================================================================

module i2c_master (
    input  wire       clk,           // System clock (12 MHz)
    input  wire       rst,           // Synchronous reset (active HIGH)

    // I2C bus (directly to package pins)
    inout  wire       scl,           // I2C clock line
    inout  wire       sda,           // I2C data line

    // Command interface
    input  wire [2:0] cmd_i,         // Command to execute
    input  wire [7:0] data_i,        // Data byte to write
    input  wire       ack_i,         // ACK to send on read (0=ACK, 1=NACK)
    input  wire       start_i,       // Start command execution

    output reg  [7:0] data_o,        // Data byte read
    output reg        ack_o,         // ACK received (0=ACK, 1=NACK)
    output reg        busy_o         // High while executing command
);

    // ========================================================================
    // COMMAND DEFINITIONS
    // ========================================================================

    localparam CMD_NONE  = 3'd0;
    localparam CMD_START = 3'd1;
    localparam CMD_STOP  = 3'd2;
    localparam CMD_WRITE = 3'd3;
    localparam CMD_READ  = 3'd4;

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================
    //
    // I2C standard mode is 100 kHz.
    // At 12 MHz system clock:
    //   Full bit period = 12,000,000 / 100,000 = 120 clocks
    //   Half period = 60 clocks

    localparam HALF_PERIOD = 60;

    // ========================================================================
    // SB_IO PRIMITIVES FOR OPEN-DRAIN I/O
    // ========================================================================
    //
    // The iCE40 SB_IO primitive allows us to control the output enable
    // separately from the output value. For open-drain:
    //   - D_OUT_0 is always 0 (we only ever drive LOW)
    //   - OUTPUT_ENABLE controls whether we drive or release
    //
    // PIN_TYPE = 6'b101001:
    //   - Output: DDR (registered on OUTPUT_CLK)
    //   - Input: Direct (no register)

    reg scl_oe = 1'b0;   // SCL output enable (1 = drive LOW, 0 = release)
    reg sda_oe = 1'b0;   // SDA output enable (1 = drive LOW, 0 = release)
    wire scl_in;         // SCL input (directly sampled)
    wire sda_in;         // SDA input (directly sampled)

    SB_IO #(
        .PIN_TYPE(6'b101001),
        .PULLUP(1'b0)
    ) scl_io (
        .PACKAGE_PIN(scl),
        .OUTPUT_CLK(clk),
        .OUTPUT_ENABLE(scl_oe),
        .D_OUT_0(1'b0),
        .D_IN_0(scl_in)
    );

    SB_IO #(
        .PIN_TYPE(6'b101001),
        .PULLUP(1'b0)
    ) sda_io (
        .PACKAGE_PIN(sda),
        .OUTPUT_CLK(clk),
        .OUTPUT_ENABLE(sda_oe),
        .D_OUT_0(1'b0),
        .D_IN_0(sda_in)
    );

    // ========================================================================
    // STATE MACHINE
    // ========================================================================

    localparam S_IDLE       = 4'd0;
    localparam S_START_1    = 4'd1;   // SDA goes LOW while SCL HIGH
    localparam S_START_2    = 4'd2;   // SCL goes LOW
    localparam S_STOP_1     = 4'd3;   // SDA goes LOW while SCL LOW
    localparam S_STOP_2     = 4'd4;   // SCL goes HIGH
    localparam S_STOP_3     = 4'd5;   // SDA goes HIGH while SCL HIGH
    localparam S_WRITE_BIT  = 4'd6;   // Set SDA, then pulse SCL
    localparam S_WRITE_SCL_H= 4'd7;   // SCL HIGH period
    localparam S_WRITE_ACK  = 4'd8;   // Release SDA, clock in ACK
    localparam S_WRITE_ACK_H= 4'd9;   // SCL HIGH, sample ACK
    localparam S_READ_BIT   = 4'd10;  // Release SDA, clock in data
    localparam S_READ_SCL_H = 4'd11;  // SCL HIGH, sample data
    localparam S_READ_ACK   = 4'd12;  // Send ACK/NACK
    localparam S_READ_ACK_H = 4'd13;  // SCL HIGH for ACK

    reg [3:0] state = S_IDLE;
    reg [6:0] timer = 7'd0;
    reg [7:0] shift_reg = 8'd0;
    reg [2:0] bit_count = 3'd0;
    reg       send_ack = 1'b0;        // ACK to send on read

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        // ----------------------------------------------------------------
        // SYNCHRONOUS RESET
        // ----------------------------------------------------------------
        // On reset: return to idle state and release I2C bus lines
        // Releasing both lines (scl_oe=0, sda_oe=0) allows external pull-ups
        // to bring SCL and SDA HIGH, which is the I2C bus idle state.
        // This enables bus recovery if reset occurs mid-transaction.
        if (rst) begin
            state <= S_IDLE;
            scl_oe <= 1'b0;          // Release SCL (goes HIGH via pull-up)
            sda_oe <= 1'b0;          // Release SDA (goes HIGH via pull-up)
            busy_o <= 1'b0;
            timer <= 7'd0;
            shift_reg <= 8'd0;
            bit_count <= 3'd0;
            send_ack <= 1'b0;
            data_o <= 8'd0;
            ack_o <= 1'b0;
        end else begin
            case (state)
                // ----------------------------------------------------------------
                // IDLE: Wait for command
                // ----------------------------------------------------------------
                S_IDLE: begin
                    busy_o <= 1'b0;
                    timer <= 7'd0;

                    if (start_i) begin
                        busy_o <= 1'b1;

                        case (cmd_i)
                            CMD_START: begin
                                // START: SDA must be HIGH, SCL must be HIGH
                                // Then SDA goes LOW while SCL stays HIGH
                                sda_oe <= 1'b0;  // Release SDA (goes HIGH)
                                scl_oe <= 1'b0;  // Release SCL (goes HIGH)
                                state <= S_START_1;
                            end

                            CMD_STOP: begin
                                // STOP: SDA LOW, SCL LOW -> SCL HIGH -> SDA HIGH
                                sda_oe <= 1'b1;  // Drive SDA LOW
                                scl_oe <= 1'b1;  // Drive SCL LOW
                                state <= S_STOP_1;
                            end

                            CMD_WRITE: begin
                                shift_reg <= data_i;
                                bit_count <= 3'd0;
                                state <= S_WRITE_BIT;
                            end

                            CMD_READ: begin
                                send_ack <= ack_i;
                                shift_reg <= 8'd0;
                                bit_count <= 3'd0;
                                sda_oe <= 1'b0;  // Release SDA for slave to drive
                                state <= S_READ_BIT;
                            end

                            default: begin
                                busy_o <= 1'b0;
                            end
                        endcase
                    end
                end

                // ----------------------------------------------------------------
                // START CONDITION
                // ----------------------------------------------------------------
                // START = SDA falls while SCL is HIGH

                S_START_1: begin
                    // Wait for lines to stabilize HIGH, then pull SDA LOW
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        sda_oe <= 1'b1;  // Pull SDA LOW (START condition)
                        state <= S_START_2;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_START_2: begin
                    // Hold SDA LOW, then pull SCL LOW
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b1;  // Pull SCL LOW
                        state <= S_IDLE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // STOP CONDITION
                // ----------------------------------------------------------------
                // STOP = SDA rises while SCL is HIGH

                S_STOP_1: begin
                    // SDA LOW, SCL LOW - wait, then release SCL
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b0;  // Release SCL (goes HIGH)
                        state <= S_STOP_2;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_STOP_2: begin
                    // SCL HIGH, SDA still LOW - wait, then release SDA
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        sda_oe <= 1'b0;  // Release SDA (goes HIGH = STOP)
                        state <= S_STOP_3;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_STOP_3: begin
                    // Hold for a moment, then done
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        state <= S_IDLE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // WRITE BYTE (MSB first)
                // ----------------------------------------------------------------

                S_WRITE_BIT: begin
                    // Set SDA based on MSB, SCL is LOW
                    scl_oe <= 1'b1;                    // Keep SCL LOW
                    sda_oe <= ~shift_reg[7];          // Drive LOW if bit=0, release if bit=1

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b0;                // Release SCL (goes HIGH)
                        state <= S_WRITE_SCL_H;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_WRITE_SCL_H: begin
                    // SCL HIGH - slave samples SDA
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b1;                // Pull SCL LOW
                        shift_reg <= {shift_reg[6:0], 1'b0};

                        if (bit_count == 3'd7) begin
                            // All 8 bits sent, get ACK
                            state <= S_WRITE_ACK;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                            state <= S_WRITE_BIT;
                        end
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_WRITE_ACK: begin
                    // Release SDA for slave to send ACK
                    sda_oe <= 1'b0;                    // Release SDA
                    scl_oe <= 1'b1;                    // Keep SCL LOW

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b0;                // Release SCL (goes HIGH)
                        state <= S_WRITE_ACK_H;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_WRITE_ACK_H: begin
                    // SCL HIGH - sample ACK from slave
                    // ACK = SDA LOW, NACK = SDA HIGH
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        ack_o <= sda_in;               // 0 = ACK, 1 = NACK
                        scl_oe <= 1'b1;                // Pull SCL LOW
                        state <= S_IDLE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // READ BYTE (MSB first)
                // ----------------------------------------------------------------

                S_READ_BIT: begin
                    // SDA released, SCL LOW - wait, then raise SCL
                    scl_oe <= 1'b1;                    // Keep SCL LOW
                    sda_oe <= 1'b0;                    // Keep SDA released

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b0;                // Release SCL (goes HIGH)
                        state <= S_READ_SCL_H;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_READ_SCL_H: begin
                    // SCL HIGH - sample SDA
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        shift_reg <= {shift_reg[6:0], sda_in};
                        scl_oe <= 1'b1;                // Pull SCL LOW

                        if (bit_count == 3'd7) begin
                            // All 8 bits received, send ACK/NACK
                            data_o <= {shift_reg[6:0], sda_in};
                            state <= S_READ_ACK;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                            state <= S_READ_BIT;
                        end
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_READ_ACK: begin
                    // Send ACK (SDA LOW) or NACK (SDA HIGH)
                    scl_oe <= 1'b1;                    // Keep SCL LOW
                    sda_oe <= ~send_ack;              // ACK=0 drives LOW, NACK=1 releases

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b0;                // Release SCL (goes HIGH)
                        state <= S_READ_ACK_H;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                S_READ_ACK_H: begin
                    // SCL HIGH for ACK
                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 7'd0;
                        scl_oe <= 1'b1;                // Pull SCL LOW
                        sda_oe <= 1'b0;                // Release SDA
                        state <= S_IDLE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
