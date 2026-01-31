// ============================================================================
// ADS1115 16-bit I2C ADC - Device Wrapper Module
// ============================================================================
//
// High-level wrapper for the Texas Instruments ADS1115 16-bit ADC.
// Instantiates i2c_master internally and provides a simple read interface.
//
// FEATURES:
//   - 16-bit resolution
//   - 4 single-ended or 2 differential input channels
//   - Programmable gain amplifier (PGA)
//   - Continuous or single-shot conversion mode
//
// INTERFACE:
//   - Set channel_i (0-3 for single-ended)
//   - Pulse start_i to begin conversion
//   - Wait for valid_o pulse
//   - Read 16-bit result from data_o
//
// CONFIGURATION (default):
//   - Single-ended input (AINx vs GND)
//   - +/-4.096V full scale (PGA = 001)
//   - Single-shot mode (one conversion per start)
//   - 128 SPS (conversion time ~8ms)
//
// I2C PROTOCOL SEQUENCE:
//   1. Configure: START -> ADDR_W -> 0x01 -> config_msb -> config_lsb -> STOP
//   2. Wait for conversion (poll or delay)
//   3. Read: START -> ADDR_R -> MSB(ACK) -> LSB(NACK) -> STOP
//
// NOTE: This module uses the library i2c_master which requires SB_IO primitives.
//
// ============================================================================

module ads1115 #(
    parameter I2C_ADDR = 7'h48,      // Default I2C address (ADDR pin to GND)
    parameter HALF_PERIOD = 60       // I2C timing (100 kHz @ 12 MHz)
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // I2C bus
    inout  wire        scl_io,
    inout  wire        sda_io,

    // User interface
    input  wire [1:0]  channel_i,    // ADC channel (0-3 for single-ended)
    input  wire        start_i,      // Start conversion
    output reg  [15:0] data_o,       // 16-bit ADC result
    output wire        ready_o,      // HIGH when idle
    output reg         valid_o       // Pulses HIGH when data_o is valid
);

    // ========================================================================
    // I2C ADDRESS BYTES
    // ========================================================================

    wire [7:0] addr_w = {I2C_ADDR, 1'b0};  // Write address
    wire [7:0] addr_r = {I2C_ADDR, 1'b1};  // Read address

    // ========================================================================
    // REGISTER ADDRESSES
    // ========================================================================

    localparam REG_CONVERSION = 8'h00;
    localparam REG_CONFIG     = 8'h01;

    // ========================================================================
    // CONFIGURATION REGISTER
    // ========================================================================
    //
    // Bit 15:    OS = 1 (start single conversion)
    // Bit 14-12: MUX = channel + 100 (single-ended vs GND)
    // Bit 11-9:  PGA = 001 (+/-4.096V)
    // Bit 8:     MODE = 1 (single-shot)
    // Bit 7-5:   DR = 100 (128 SPS, ~8ms conversion)
    // Bit 4-0:   Defaults (comparator disabled)
    //
    // MSB: 1 + MUX[2:0] + PGA[2:0] + MODE = 1_1xx_001_1
    // LSB: DR[2:0] + defaults = 100_00011 = 0x83

    wire [2:0] mux = {1'b1, channel_i};  // 100, 101, 110, 111 for ch 0-3
    wire [7:0] config_msb = {1'b1, mux, 3'b001, 1'b1};  // OS + MUX + PGA + MODE
    wire [7:0] config_lsb = 8'h83;  // 128 SPS, comparator disabled

    // ========================================================================
    // I2C COMMAND DEFINITIONS
    // ========================================================================

    localparam CMD_NONE  = 3'd0;
    localparam CMD_START = 3'd1;
    localparam CMD_STOP  = 3'd2;
    localparam CMD_WRITE = 3'd3;
    localparam CMD_READ  = 3'd4;

    // ========================================================================
    // I2C MASTER INSTANCE
    // ========================================================================

    reg  [2:0] i2c_cmd = CMD_NONE;
    reg  [7:0] i2c_data_out = 8'd0;
    reg        i2c_ack_send = 1'b1;
    reg        i2c_start = 1'b0;
    wire [7:0] i2c_data_in;
    wire       i2c_ack;
    wire       i2c_ready;

    i2c_master #(
        .HALF_PERIOD(HALF_PERIOD)
    ) i2c_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .scl_io(scl_io),
        .sda_io(sda_io),
        .cmd_i(i2c_cmd),
        .data_i(i2c_data_out),
        .ack_i(i2c_ack_send),
        .start_i(i2c_start),
        .data_o(i2c_data_in),
        .ack_o(i2c_ack),
        .ready_o(i2c_ready)
    );

    // ========================================================================
    // STATE MACHINE
    // ========================================================================

    localparam S_IDLE       = 4'd0;
    localparam S_CFG_START  = 4'd1;
    localparam S_CFG_ADDR   = 4'd2;
    localparam S_CFG_REG    = 4'd3;
    localparam S_CFG_MSB    = 4'd4;
    localparam S_CFG_LSB    = 4'd5;
    localparam S_CFG_STOP   = 4'd6;
    localparam S_WAIT       = 4'd7;   // Wait for conversion
    localparam S_RD_START   = 4'd8;
    localparam S_RD_ADDR    = 4'd9;
    localparam S_RD_MSB     = 4'd10;
    localparam S_RD_LSB     = 4'd11;
    localparam S_RD_STOP    = 4'd12;
    localparam S_DONE       = 4'd13;

    reg [3:0] state = S_IDLE;
    reg       busy = 1'b0;
    reg       cmd_pending = 1'b0;

    assign ready_o = ~busy;

    // Wait counter for conversion time (~8ms at 128 SPS)
    // At 12 MHz, 8ms = 96,000 clocks
    localparam CONV_WAIT = 100000;  // ~8.3ms with margin
    reg [16:0] wait_counter = 0;

    // Stored ADC value
    reg [15:0] adc_value = 16'd0;

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk_i) begin
        // Defaults
        i2c_start <= 1'b0;
        valid_o <= 1'b0;

        if (rst_i) begin
            state <= S_IDLE;
            busy <= 1'b0;
            cmd_pending <= 1'b0;
            i2c_cmd <= CMD_NONE;
            i2c_data_out <= 8'd0;
            i2c_ack_send <= 1'b1;
            data_o <= 16'd0;
            adc_value <= 16'd0;
            wait_counter <= 0;
        end else begin
            case (state)
                // ----------------------------------------------------------------
                // IDLE: Wait for start signal
                // ----------------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start_i) begin
                        busy <= 1'b1;
                        state <= S_CFG_START;
                    end
                end

                // ----------------------------------------------------------------
                // CONFIGURE: Write config register
                // ----------------------------------------------------------------
                S_CFG_START: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_START;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        state <= S_CFG_ADDR;
                    end
                end

                S_CFG_ADDR: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= addr_w;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        if (i2c_ack) begin  // NACK - error
                            state <= S_IDLE;
                        end else begin
                            state <= S_CFG_REG;
                        end
                    end
                end

                S_CFG_REG: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= REG_CONFIG;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        if (i2c_ack) begin
                            state <= S_IDLE;
                        end else begin
                            state <= S_CFG_MSB;
                        end
                    end
                end

                S_CFG_MSB: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= config_msb;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        if (i2c_ack) begin
                            state <= S_IDLE;
                        end else begin
                            state <= S_CFG_LSB;
                        end
                    end
                end

                S_CFG_LSB: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= config_lsb;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        if (i2c_ack) begin
                            state <= S_IDLE;
                        end else begin
                            state <= S_CFG_STOP;
                        end
                    end
                end

                S_CFG_STOP: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        wait_counter <= 0;
                        state <= S_WAIT;
                    end
                end

                // ----------------------------------------------------------------
                // WAIT: Wait for conversion to complete
                // ----------------------------------------------------------------
                S_WAIT: begin
                    if (wait_counter >= CONV_WAIT) begin
                        state <= S_RD_START;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // READ: Read conversion result
                // ----------------------------------------------------------------
                S_RD_START: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_START;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        state <= S_RD_ADDR;
                    end
                end

                S_RD_ADDR: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= addr_r;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        if (i2c_ack) begin
                            state <= S_IDLE;
                        end else begin
                            state <= S_RD_MSB;
                        end
                    end
                end

                S_RD_MSB: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_READ;
                        i2c_ack_send <= 1'b0;  // ACK after MSB
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        adc_value[15:8] <= i2c_data_in;
                        state <= S_RD_LSB;
                    end
                end

                S_RD_LSB: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_READ;
                        i2c_ack_send <= 1'b1;  // NACK after LSB (last byte)
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        adc_value[7:0] <= i2c_data_in;
                        state <= S_RD_STOP;
                    end
                end

                S_RD_STOP: begin
                    if (i2c_ready && !cmd_pending) begin
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        cmd_pending <= 1'b1;
                    end else if (i2c_ready && cmd_pending) begin
                        cmd_pending <= 1'b0;
                        state <= S_DONE;
                    end
                end

                // ----------------------------------------------------------------
                // DONE: Output result
                // ----------------------------------------------------------------
                S_DONE: begin
                    data_o <= adc_value;
                    valid_o <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
