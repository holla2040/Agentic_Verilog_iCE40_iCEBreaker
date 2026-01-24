// ============================================================================
// ADS1115 I2C ADC Reader - Top Level Module (Step 4: Continuous Reading)
// ============================================================================
//
// Reads 16-bit ADC values from ADS1115 and outputs via UART.
//
// OPERATION:
//   1. Sends "\r\nads1115\r\n" on startup via UART
//   2. Configures ADS1115 (write to config register 0x01)
//   3. Sets pointer to conversion register (0x00)
//   4. Every 200ms:
//      - Reads 16-bit conversion value
//      - Sends as "0xNNNN\r\n" via UART
//      - On any NACK: sends 'E' instead
//
// ADS1115 CONFIGURATION (0x96D5):
//   - MUX[14:12] = 100: AIN0 single-ended (vs GND)
//   - PGA[11:9]  = 001: +/-4.096V full scale
//   - MODE[8]    = 0:   Continuous conversion
//   - DR[7:5]    = 110: 250 SPS
//   - Rest       = defaults
//
// HARDWARE:
//   - iCEBreaker FPGA (12 MHz clock)
//   - ADS1115 on I2C (SCL=pin 45, SDA=pin 47)
//   - Button on pin 20 -> ADS1115 ADDR pin
//   - UART TX on pin 9 (115200 baud)
//
// ============================================================================

module top (
    input  wire clk,           // 12 MHz system clock

    // I2C interface
    inout  wire scl,           // I2C clock
    inout  wire sda,           // I2C data

    // Button and address passthrough
    input  wire btn_addr,      // Button directly to ADS1115 ADDR
    output wire ads_addr,      // ADS1115 ADDR pin (directly from button)

    // UART output
    output wire uart_tx        // UART transmit pin
);

    // ========================================================================
    // BUTTON DIRECTLY TO ADS1115 ADDR
    // ========================================================================

    assign ads_addr = btn_addr;

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================

    // 200ms interval at 12 MHz = 2,400,000 clocks (5 readings/sec)
    localparam CLOCKS_PER_INTERVAL = 24'd2400000;

    // Startup message: "\r\nads1115\r\n" = 10 characters
    localparam STARTUP_MSG_LEN = 10;

    // ADC output message: "0xNNNN\r\n" = 8 characters
    localparam ADC_MSG_LEN = 8;

    // ========================================================================
    // ADS1115 I2C PARAMETERS
    // ========================================================================

    // I2C addresses (7-bit: 0x48)
    localparam ADS1115_ADDR_W = 8'h90;  // 0x48 << 1 | 0 (write)
    localparam ADS1115_ADDR_R = 8'h91;  // 0x48 << 1 | 1 (read)

    // Register addresses
    localparam REG_CONVERSION = 8'h00;
    localparam REG_CONFIG     = 8'h01;

    // Config value: 0xC2C3
    // Bit 15:    OS=1 (start conversion)
    // Bit 14-12: MUX=100 (AIN0 vs GND, single-ended)
    // Bit 11-9:  PGA=001 (+/-4.096V full scale)
    // Bit 8:     MODE=0 (continuous conversion)
    // Bit 7-5:   DR=110 (250 SPS)
    // Bit 4-2:   COMP_MODE=0, COMP_POL=0, COMP_LAT=0
    // Bit 1-0:   COMP_QUE=11 (comparator disabled)
    //
    // MSB: 1100 0010 = 0xC2
    // LSB: 1100 0011 = 0xC3
    localparam CONFIG_MSB = 8'hC2;
    localparam CONFIG_LSB = 8'hC3;

    // ========================================================================
    // I2C COMMAND DEFINITIONS
    // ========================================================================

    localparam CMD_NONE  = 3'd0;
    localparam CMD_START = 3'd1;
    localparam CMD_STOP  = 3'd2;
    localparam CMD_WRITE = 3'd3;
    localparam CMD_READ  = 3'd4;

    // ========================================================================
    // INTERNAL SIGNALS
    // ========================================================================

    // UART interface signals
    reg  [7:0] uart_data = 8'd0;
    reg        uart_start = 1'b0;
    wire       uart_busy;

    // I2C interface signals
    reg  [2:0] i2c_cmd = CMD_NONE;
    reg  [7:0] i2c_data_out = 8'd0;
    reg        i2c_ack_send = 1'b1;    // ACK to send on read (0=ACK, 1=NACK)
    reg        i2c_start = 1'b0;
    wire [7:0] i2c_data_in;
    wire       i2c_ack;
    wire       i2c_busy;

    // Startup message buffer
    reg [7:0] startup_msg [0:9];

    // ADC message buffer: "0xNNNN\r\n"
    reg [7:0] adc_msg [0:7];

    // Main state machine
    localparam ST_STARTUP       = 5'd0;
    localparam ST_CFG_START     = 5'd1;
    localparam ST_CFG_ADDR      = 5'd2;
    localparam ST_CFG_REG       = 5'd3;
    localparam ST_CFG_MSB       = 5'd4;
    localparam ST_CFG_LSB       = 5'd5;
    localparam ST_CFG_STOP      = 5'd6;
    localparam ST_PTR_START     = 5'd7;
    localparam ST_PTR_ADDR      = 5'd8;
    localparam ST_PTR_REG       = 5'd9;
    localparam ST_PTR_STOP      = 5'd10;
    localparam ST_IDLE          = 5'd11;
    localparam ST_RD_START      = 5'd12;
    localparam ST_RD_ADDR       = 5'd13;
    localparam ST_RD_MSB        = 5'd14;
    localparam ST_RD_LSB        = 5'd15;
    localparam ST_RD_STOP       = 5'd16;
    localparam ST_SEND_ADC      = 5'd17;
    localparam ST_ERROR         = 5'd18;

    reg [4:0] state = ST_STARTUP;
    reg [3:0] msg_index = 4'd0;
    reg       seen_busy = 1'b0;
    reg       error_flag = 1'b0;

    // ADC reading storage
    reg [15:0] adc_value = 16'd0;

    // Interval timer
    reg [23:0] interval_counter = 24'd0;
    reg        interval_tick = 1'b0;

    // ========================================================================
    // HEX TO ASCII CONVERSION
    // ========================================================================

    function [7:0] hex_to_ascii;
        input [3:0] nibble;
        begin
            if (nibble < 10)
                hex_to_ascii = 8'h30 + nibble;  // '0' + value
            else
                hex_to_ascii = 8'h41 + (nibble - 10);  // 'A' + (value - 10)
        end
    endfunction

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    initial begin
        startup_msg[0] = 8'h0D;  // \r
        startup_msg[1] = 8'h0A;  // \n
        startup_msg[2] = "a";
        startup_msg[3] = "d";
        startup_msg[4] = "s";
        startup_msg[5] = "1";
        startup_msg[6] = "1";
        startup_msg[7] = "1";
        startup_msg[8] = "5";
        startup_msg[9] = 8'h0A;  // \n
    end

    // ========================================================================
    // MODULE INSTANTIATIONS
    // ========================================================================

    uart_tx #(
        .CLOCKS_PER_BIT(104)
    ) u_uart (
        .clk(clk),
        .data_i(uart_data),
        .start_i(uart_start),
        .busy_o(uart_busy),
        .tx_o(uart_tx)
    );

    i2c_master u_i2c (
        .clk(clk),
        .scl(scl),
        .sda(sda),
        .cmd_i(i2c_cmd),
        .data_i(i2c_data_out),
        .ack_i(i2c_ack_send),
        .start_i(i2c_start),
        .data_o(i2c_data_in),
        .ack_o(i2c_ack),
        .busy_o(i2c_busy)
    );

    // ========================================================================
    // INTERVAL TIMER (200ms = 5 readings/sec)
    // ========================================================================

    always @(posedge clk) begin
        interval_tick <= 1'b0;

        if (interval_counter == CLOCKS_PER_INTERVAL - 1) begin
            interval_counter <= 24'd0;
            interval_tick <= 1'b1;
        end else begin
            interval_counter <= interval_counter + 1'b1;
        end
    end

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        // Defaults
        uart_start <= 1'b0;
        i2c_start <= 1'b0;

        // Track I2C command completion
        if (i2c_busy) begin
            seen_busy <= 1'b1;
        end

        case (state)
            // ================================================================
            // STARTUP: Send startup message
            // ================================================================
            ST_STARTUP: begin
                if (!uart_busy && !uart_start) begin
                    if (msg_index < STARTUP_MSG_LEN) begin
                        uart_data <= startup_msg[msg_index];
                        uart_start <= 1'b1;
                        msg_index <= msg_index + 1'b1;
                    end else begin
                        msg_index <= 4'd0;
                        state <= ST_CFG_START;
                    end
                end
            end

            // ================================================================
            // CONFIGURE ADS1115: Write config register
            // Sequence: START -> 0x90 -> 0x01 -> 0x96 -> 0xD5 -> STOP
            // ================================================================

            ST_CFG_START: begin
                i2c_cmd <= CMD_START;
                i2c_start <= 1'b1;
                seen_busy <= 1'b0;
                error_flag <= 1'b0;
                state <= ST_CFG_ADDR;
            end

            ST_CFG_ADDR: begin
                if (!i2c_busy && seen_busy) begin
                    i2c_cmd <= CMD_WRITE;
                    i2c_data_out <= ADS1115_ADDR_W;
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    state <= ST_CFG_REG;
                end
            end

            ST_CFG_REG: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin  // NACK
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= REG_CONFIG;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_CFG_MSB;
                    end
                end
            end

            ST_CFG_MSB: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= CONFIG_MSB;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_CFG_LSB;
                    end
                end
            end

            ST_CFG_LSB: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= CONFIG_LSB;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_CFG_STOP;
                    end
                end
            end

            ST_CFG_STOP: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_PTR_START;
                    end
                end
            end

            // ================================================================
            // SET POINTER: Point to conversion register
            // Sequence: START -> 0x90 -> 0x00 -> STOP
            // ================================================================

            ST_PTR_START: begin
                if (!i2c_busy && seen_busy) begin
                    i2c_cmd <= CMD_START;
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    state <= ST_PTR_ADDR;
                end
            end

            ST_PTR_ADDR: begin
                if (!i2c_busy && seen_busy) begin
                    i2c_cmd <= CMD_WRITE;
                    i2c_data_out <= ADS1115_ADDR_W;
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    state <= ST_PTR_REG;
                end
            end

            ST_PTR_REG: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_WRITE;
                        i2c_data_out <= REG_CONVERSION;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_PTR_STOP;
                    end
                end
            end

            ST_PTR_STOP: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
            end

            // ================================================================
            // IDLE: Wait for interval tick, then read ADC
            // ================================================================

            ST_IDLE: begin
                if (!i2c_busy && seen_busy) begin
                    // STOP from previous operation completed
                    seen_busy <= 1'b0;
                end

                if (interval_tick && !seen_busy) begin
                    i2c_cmd <= CMD_START;
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    error_flag <= 1'b0;
                    state <= ST_RD_START;
                end
            end

            // ================================================================
            // READ ADC: Read 16-bit conversion value
            // Sequence: START -> 0x91 -> MSB(ACK) -> LSB(NACK) -> STOP
            // ================================================================

            ST_RD_START: begin
                if (!i2c_busy && seen_busy) begin
                    i2c_cmd <= CMD_WRITE;
                    i2c_data_out <= ADS1115_ADDR_R;
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    state <= ST_RD_ADDR;
                end
            end

            ST_RD_ADDR: begin
                if (!i2c_busy && seen_busy) begin
                    if (i2c_ack) begin
                        error_flag <= 1'b1;
                        i2c_cmd <= CMD_STOP;
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_ERROR;
                    end else begin
                        i2c_cmd <= CMD_READ;
                        i2c_ack_send <= 1'b0;  // Send ACK after MSB
                        i2c_start <= 1'b1;
                        seen_busy <= 1'b0;
                        state <= ST_RD_MSB;
                    end
                end
            end

            ST_RD_MSB: begin
                if (!i2c_busy && seen_busy) begin
                    adc_value[15:8] <= i2c_data_in;
                    i2c_cmd <= CMD_READ;
                    i2c_ack_send <= 1'b1;  // Send NACK after LSB (last byte)
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    state <= ST_RD_LSB;
                end
            end

            ST_RD_LSB: begin
                if (!i2c_busy && seen_busy) begin
                    adc_value[7:0] <= i2c_data_in;
                    i2c_cmd <= CMD_STOP;
                    i2c_start <= 1'b1;
                    seen_busy <= 1'b0;
                    state <= ST_RD_STOP;
                end
            end

            ST_RD_STOP: begin
                if (!i2c_busy && seen_busy) begin
                    // Format message: "0xNNNN\r\n"
                    adc_msg[0] <= "0";
                    adc_msg[1] <= "x";
                    adc_msg[2] <= hex_to_ascii(adc_value[15:12]);
                    adc_msg[3] <= hex_to_ascii(adc_value[11:8]);
                    adc_msg[4] <= hex_to_ascii(adc_value[7:4]);
                    adc_msg[5] <= hex_to_ascii(adc_value[3:0]);
                    adc_msg[6] <= 8'h0D;  // \r
                    adc_msg[7] <= 8'h0A;  // \n

                    msg_index <= 4'd0;
                    seen_busy <= 1'b0;
                    state <= ST_SEND_ADC;
                end
            end

            // ================================================================
            // SEND ADC VALUE: Transmit "0xNNNN\r\n" via UART
            // ================================================================

            ST_SEND_ADC: begin
                if (!uart_busy && !uart_start) begin
                    if (msg_index < ADC_MSG_LEN) begin
                        uart_data <= adc_msg[msg_index];
                        uart_start <= 1'b1;
                        msg_index <= msg_index + 1'b1;
                    end else begin
                        msg_index <= 4'd0;
                        state <= ST_IDLE;
                    end
                end
            end

            // ================================================================
            // ERROR: Send 'E' and return to idle
            // ================================================================

            ST_ERROR: begin
                if (!i2c_busy && seen_busy) begin
                    // STOP completed
                    seen_busy <= 1'b0;
                end

                if (!uart_busy && !uart_start && !seen_busy) begin
                    uart_data <= "E";
                    uart_start <= 1'b1;
                    state <= ST_IDLE;
                end
            end

            default: begin
                state <= ST_STARTUP;
            end
        endcase
    end

endmodule
