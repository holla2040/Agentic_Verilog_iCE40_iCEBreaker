// ============================================================================
// ADS1115 I2C ADC Reader - Top Module (Step 5: Error Handling Complete)
// ============================================================================
//
// Reads analog voltage from ADS1115 16-bit ADC via I2C and outputs hex values
// over UART at 5 readings per second.
//
// BEHAVIOR:
//   1. On power-up, sends "\r\nads1115\r\n" to identify the project
//   2. Configures ADS1115 (writes 0xC2E3 to config register for continuous mode)
//   3. Sets pointer to conversion register (0x00)
//   4. Every 200ms, reads conversion result and outputs as hex
//
// I2C SEQUENCES:
//   Sequence 1 - Configure ADC:
//     START → [0x90] → [0x01] → [0xC2] → [0xE3] → STOP
//             addr+W   ptr=cfg   hi byte   lo byte
//
//   Sequence 2 - Set pointer to conversion register:
//     START → [0x90] → [0x00] → STOP
//             addr+W   ptr=conv
//
//   Sequence 3 - Read conversion (repeated every 200ms):
//     START → [0x91] → [MSB] → ACK → [LSB] → NACK → STOP
//             addr+R   data_hi        data_lo
//
// ERROR HANDLING:
//   - NACK from slave: outputs "E\r\n" and retries after 200ms
//   - Bus timeout (>1ms): outputs "E\r\n" and retries after 200ms
//
// OUTPUT FORMAT:
//   "0xNNNN\r\n" where NNNN is 4 hex digits (16-bit ADC value)
//   "E\r\n" on communication error (NACK or timeout)
//
// EXPECTED VALUES (at ±4.096V full scale, 125µV/LSB):
//   0V    → ~0x0000
//   1.65V → ~0x3390
//   3.3V  → ~0x6720
//
// ============================================================================

module top (
    input  wire clk,        // 12 MHz system clock (pin 35)
    output wire tx,         // UART transmit (pin 9)

    // I2C bus
    inout  wire scl,        // I2C clock (pin 45)
    inout  wire sda,        // I2C data (pin 47)

    // Button and address control
    input  wire btn_n,      // Button (pin 20)
    output wire addr_out    // Drives ADS1115 ADDR pin (pin 2)
);

    // ========================================================================
    // BUTTON TO ADDR DIRECT CONNECTION
    // ========================================================================
    // Per PLAN.md - button directly drives ADDR pin

    assign addr_out = btn_n;

    // ========================================================================
    // TIMING CONSTANTS
    // ========================================================================

    localparam CLOCKS_PER_200MS = 24'd2_400_000;  // 12 MHz * 0.2s

    // ========================================================================
    // I2C CONSTANTS
    // ========================================================================

    localparam I2C_ADDR_WRITE  = 8'h90;  // 0x48 + write bit
    localparam I2C_ADDR_READ   = 8'h91;  // 0x48 + read bit
    localparam CONFIG_POINTER  = 8'h01;  // Config register pointer
    localparam CONVERT_POINTER = 8'h00;  // Conversion register pointer
    localparam CONFIG_HI       = 8'hC2;  // Config high byte (MODE=0 continuous)
    localparam CONFIG_LO       = 8'hE3;  // Config low byte

    // I2C commands (3-bit)
    localparam CMD_IDLE  = 3'b000;
    localparam CMD_START = 3'b001;
    localparam CMD_WRITE = 3'b010;
    localparam CMD_READ  = 3'b011;
    localparam CMD_STOP  = 3'b100;

    // ========================================================================
    // STARTUP MESSAGE: "\r\nads1115\r\n"
    // ========================================================================

    localparam STARTUP_MSG_LEN = 11;

    reg [7:0] startup_msg [0:STARTUP_MSG_LEN-1];

    initial begin
        startup_msg[0]  = 8'h0D;  // \r
        startup_msg[1]  = 8'h0A;  // \n
        startup_msg[2]  = "a";
        startup_msg[3]  = "d";
        startup_msg[4]  = "s";
        startup_msg[5]  = "1";
        startup_msg[6]  = "1";
        startup_msg[7]  = "1";
        startup_msg[8]  = "5";
        startup_msg[9]  = 8'h0D;  // \r
        startup_msg[10] = 8'h0A;  // \n
    end

    // ========================================================================
    // HEX OUTPUT MESSAGE: "0xNNNN\r\n" (8 characters)
    // ========================================================================

    localparam HEX_MSG_LEN = 8;

    reg [7:0] hex_msg [0:HEX_MSG_LEN-1];

    initial begin
        hex_msg[0] = "0";
        hex_msg[1] = "x";
        hex_msg[2] = "0";  // Will be set to hex digit
        hex_msg[3] = "0";  // Will be set to hex digit
        hex_msg[4] = "0";  // Will be set to hex digit
        hex_msg[5] = "0";  // Will be set to hex digit
        hex_msg[6] = 8'h0D;  // \r
        hex_msg[7] = 8'h0A;  // \n
    end

    // ========================================================================
    // ERROR MESSAGE: "E\r\n"
    // ========================================================================

    localparam ERROR_MSG_LEN = 3;

    reg [7:0] error_msg [0:ERROR_MSG_LEN-1];

    initial begin
        error_msg[0] = "E";
        error_msg[1] = 8'h0D;
        error_msg[2] = 8'h0A;
    end

    // ========================================================================
    // STATE MACHINE
    // ========================================================================

    localparam STATE_STARTUP_SEND    = 6'd0;
    localparam STATE_STARTUP_WAIT    = 6'd1;
    // Config write states: START → 0x90 → 0x01 → 0xC3 → 0xE3 → STOP
    localparam STATE_CFG_START_CMD   = 6'd2;
    localparam STATE_CFG_START_WAIT  = 6'd3;
    localparam STATE_CFG_ADDR_CMD    = 6'd4;
    localparam STATE_CFG_ADDR_WAIT   = 6'd5;
    localparam STATE_CFG_PTR_CMD     = 6'd6;
    localparam STATE_CFG_PTR_WAIT    = 6'd7;
    localparam STATE_CFG_HI_CMD      = 6'd8;
    localparam STATE_CFG_HI_WAIT     = 6'd9;
    localparam STATE_CFG_LO_CMD      = 6'd10;
    localparam STATE_CFG_LO_WAIT     = 6'd11;
    localparam STATE_CFG_STOP_CMD    = 6'd12;
    localparam STATE_CFG_STOP_WAIT   = 6'd13;
    // Set pointer to conversion register: START → 0x90 → 0x00 → STOP
    localparam STATE_PTR_START_CMD   = 6'd14;
    localparam STATE_PTR_START_WAIT  = 6'd15;
    localparam STATE_PTR_ADDR_CMD    = 6'd16;
    localparam STATE_PTR_ADDR_WAIT   = 6'd17;
    localparam STATE_PTR_REG_CMD     = 6'd18;
    localparam STATE_PTR_REG_WAIT    = 6'd19;
    localparam STATE_PTR_STOP_CMD    = 6'd20;
    localparam STATE_PTR_STOP_WAIT   = 6'd21;
    // Idle / wait for timer
    localparam STATE_IDLE            = 6'd22;
    // Read states: START → 0x91 → [MSB] → ACK → [LSB] → NACK → STOP
    localparam STATE_RD_START_CMD    = 6'd23;
    localparam STATE_RD_START_WAIT   = 6'd24;
    localparam STATE_RD_ADDR_CMD     = 6'd25;
    localparam STATE_RD_ADDR_WAIT    = 6'd26;
    localparam STATE_RD_MSB_CMD      = 6'd27;
    localparam STATE_RD_MSB_WAIT     = 6'd28;
    localparam STATE_RD_LSB_CMD      = 6'd29;
    localparam STATE_RD_LSB_WAIT     = 6'd30;
    localparam STATE_RD_STOP_CMD     = 6'd31;
    localparam STATE_RD_STOP_WAIT    = 6'd32;
    // Output states
    localparam STATE_HEX_SEND        = 6'd33;
    localparam STATE_HEX_WAIT        = 6'd34;
    localparam STATE_ERR_SEND        = 6'd35;
    localparam STATE_ERR_WAIT        = 6'd36;

    reg [5:0] state;

    // ========================================================================
    // INTERNAL REGISTERS
    // ========================================================================

    reg [3:0] char_index;       // For UART message transmission
    reg [23:0] delay_counter;
    reg       got_nack;         // Set if any NACK received during transaction
    reg [15:0] adc_value;       // 16-bit ADC result

    // I2C control
    reg [2:0] i2c_cmd;
    reg       i2c_cmd_start;
    wire      i2c_busy;
    wire      i2c_ack_error;
    wire      i2c_timeout;
    reg [7:0] i2c_tx_data;
    wire [7:0] i2c_rx_data;
    reg       i2c_send_nack;

    // For detecting I2C command completion
    reg i2c_busy_prev;
    wire i2c_done = i2c_busy_prev & ~i2c_busy;

    // UART control
    reg [7:0] uart_tx_data;
    reg       uart_tx_start;
    wire      uart_tx_busy;

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    initial begin
        state = STATE_STARTUP_SEND;
        char_index = 0;
        delay_counter = 0;
        got_nack = 0;
        adc_value = 0;
        i2c_cmd = CMD_IDLE;
        i2c_cmd_start = 0;
        i2c_tx_data = 0;
        i2c_send_nack = 0;
        i2c_busy_prev = 0;
        uart_tx_data = 0;
        uart_tx_start = 0;
    end

    // ========================================================================
    // NIBBLE TO HEX ASCII CONVERSION
    // ========================================================================
    // Convert 4-bit value to ASCII hex character

    function [7:0] nibble_to_hex;
        input [3:0] nibble;
        begin
            if (nibble < 10)
                nibble_to_hex = 8'h30 + nibble;  // '0'-'9'
            else
                nibble_to_hex = 8'h41 + (nibble - 10);  // 'A'-'F'
        end
    endfunction

    // ========================================================================
    // I2C MASTER INSTANCE
    // ========================================================================

    i2c_master i2c_inst (
        .clk(clk),
        .scl(scl),
        .sda(sda),
        .cmd(i2c_cmd),
        .cmd_start(i2c_cmd_start),
        .busy(i2c_busy),
        .ack_error(i2c_ack_error),
        .timeout(i2c_timeout),
        .tx_data(i2c_tx_data),
        .rx_data(i2c_rx_data),
        .send_nack(i2c_send_nack)
    );

    // ========================================================================
    // UART TRANSMITTER INSTANCE
    // ========================================================================

    uart_tx uart_inst (
        .clk(clk),
        .tx_data(uart_tx_data),
        .tx_start(uart_tx_start),
        .tx_busy(uart_tx_busy),
        .tx(tx)
    );

    // ========================================================================
    // I2C BUSY EDGE DETECTION
    // ========================================================================

    always @(posedge clk) begin
        i2c_busy_prev <= i2c_busy;
    end

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk) begin
        // Default: clear start pulses after one clock
        uart_tx_start <= 1'b0;
        i2c_cmd_start <= 1'b0;

        case (state)
            // ================================================================
            // STARTUP MESSAGE TRANSMISSION
            // ================================================================

            STATE_STARTUP_SEND: begin
                if (!uart_tx_busy) begin
                    uart_tx_data <= startup_msg[char_index];
                    uart_tx_start <= 1'b1;
                    state <= STATE_STARTUP_WAIT;
                end
            end

            STATE_STARTUP_WAIT: begin
                if (!uart_tx_busy && !uart_tx_start) begin
                    if (char_index == STARTUP_MSG_LEN - 1) begin
                        char_index <= 0;
                        got_nack <= 1'b0;
                        state <= STATE_CFG_START_CMD;
                    end else begin
                        char_index <= char_index + 1;
                        state <= STATE_STARTUP_SEND;
                    end
                end
            end

            // ================================================================
            // CONFIGURATION WRITE SEQUENCE
            // START → 0x90 → 0x01 → 0xC3 → 0xE3 → STOP
            // ================================================================

            STATE_CFG_START_CMD: begin
                i2c_cmd <= CMD_START;
                i2c_cmd_start <= 1'b1;
                state <= STATE_CFG_START_WAIT;
            end

            STATE_CFG_START_WAIT: begin
                if (i2c_done) state <= STATE_CFG_ADDR_CMD;
            end

            STATE_CFG_ADDR_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= I2C_ADDR_WRITE;
                i2c_cmd_start <= 1'b1;
                state <= STATE_CFG_ADDR_WAIT;
            end

            STATE_CFG_ADDR_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_CFG_PTR_CMD;
                end
            end

            STATE_CFG_PTR_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= CONFIG_POINTER;
                i2c_cmd_start <= 1'b1;
                state <= STATE_CFG_PTR_WAIT;
            end

            STATE_CFG_PTR_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_CFG_HI_CMD;
                end
            end

            STATE_CFG_HI_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= CONFIG_HI;
                i2c_cmd_start <= 1'b1;
                state <= STATE_CFG_HI_WAIT;
            end

            STATE_CFG_HI_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_CFG_LO_CMD;
                end
            end

            STATE_CFG_LO_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= CONFIG_LO;
                i2c_cmd_start <= 1'b1;
                state <= STATE_CFG_LO_WAIT;
            end

            STATE_CFG_LO_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_CFG_STOP_CMD;
                end
            end

            STATE_CFG_STOP_CMD: begin
                i2c_cmd <= CMD_STOP;
                i2c_cmd_start <= 1'b1;
                state <= STATE_CFG_STOP_WAIT;
            end

            STATE_CFG_STOP_WAIT: begin
                if (i2c_done) begin
                    // If config failed, go to error, else set pointer to conversion reg
                    if (got_nack) begin
                        char_index <= 0;
                        state <= STATE_ERR_SEND;
                    end else begin
                        state <= STATE_PTR_START_CMD;
                    end
                end
            end

            // ================================================================
            // SET POINTER TO CONVERSION REGISTER
            // START → 0x90 → 0x00 → STOP
            // ================================================================

            STATE_PTR_START_CMD: begin
                i2c_cmd <= CMD_START;
                i2c_cmd_start <= 1'b1;
                state <= STATE_PTR_START_WAIT;
            end

            STATE_PTR_START_WAIT: begin
                if (i2c_done) state <= STATE_PTR_ADDR_CMD;
            end

            STATE_PTR_ADDR_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= I2C_ADDR_WRITE;
                i2c_cmd_start <= 1'b1;
                state <= STATE_PTR_ADDR_WAIT;
            end

            STATE_PTR_ADDR_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_PTR_REG_CMD;
                end
            end

            STATE_PTR_REG_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= CONVERT_POINTER;  // 0x00
                i2c_cmd_start <= 1'b1;
                state <= STATE_PTR_REG_WAIT;
            end

            STATE_PTR_REG_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_PTR_STOP_CMD;
                end
            end

            STATE_PTR_STOP_CMD: begin
                i2c_cmd <= CMD_STOP;
                i2c_cmd_start <= 1'b1;
                state <= STATE_PTR_STOP_WAIT;
            end

            STATE_PTR_STOP_WAIT: begin
                if (i2c_done) begin
                    if (got_nack) begin
                        char_index <= 0;
                        state <= STATE_ERR_SEND;
                    end else begin
                        // Pointer set, now read the conversion data
                        state <= STATE_RD_START_CMD;
                    end
                end
            end

            // ================================================================
            // IDLE: Wait for 200ms timer
            // ================================================================

            STATE_IDLE: begin
                if (delay_counter == CLOCKS_PER_200MS - 1) begin
                    delay_counter <= 0;
                    got_nack <= 1'b0;
                    // Set pointer to conversion register before each read
                    state <= STATE_PTR_START_CMD;
                end else begin
                    delay_counter <= delay_counter + 1;
                end
            end

            // ================================================================
            // READ CONVERSION SEQUENCE
            // START → 0x91 → [MSB] ACK → [LSB] NACK → STOP
            // ================================================================

            STATE_RD_START_CMD: begin
                i2c_cmd <= CMD_START;
                i2c_cmd_start <= 1'b1;
                state <= STATE_RD_START_WAIT;
            end

            STATE_RD_START_WAIT: begin
                if (i2c_done) state <= STATE_RD_ADDR_CMD;
            end

            STATE_RD_ADDR_CMD: begin
                i2c_cmd <= CMD_WRITE;
                i2c_tx_data <= I2C_ADDR_READ;
                i2c_cmd_start <= 1'b1;
                state <= STATE_RD_ADDR_WAIT;
            end

            STATE_RD_ADDR_WAIT: begin
                if (i2c_done) begin
                    if (i2c_ack_error || i2c_timeout) got_nack <= 1'b1;
                    state <= STATE_RD_MSB_CMD;
                end
            end

            STATE_RD_MSB_CMD: begin
                i2c_cmd <= CMD_READ;
                i2c_send_nack <= 1'b0;  // Send ACK after MSB
                i2c_cmd_start <= 1'b1;
                state <= STATE_RD_MSB_WAIT;
            end

            STATE_RD_MSB_WAIT: begin
                if (i2c_done) begin
                    adc_value[15:8] <= i2c_rx_data;
                    state <= STATE_RD_LSB_CMD;
                end
            end

            STATE_RD_LSB_CMD: begin
                i2c_cmd <= CMD_READ;
                i2c_send_nack <= 1'b1;  // Send NACK after LSB (end of read)
                i2c_cmd_start <= 1'b1;
                state <= STATE_RD_LSB_WAIT;
            end

            STATE_RD_LSB_WAIT: begin
                if (i2c_done) begin
                    adc_value[7:0] <= i2c_rx_data;
                    state <= STATE_RD_STOP_CMD;
                end
            end

            STATE_RD_STOP_CMD: begin
                i2c_cmd <= CMD_STOP;
                i2c_cmd_start <= 1'b1;
                state <= STATE_RD_STOP_WAIT;
            end

            STATE_RD_STOP_WAIT: begin
                if (i2c_done) begin
                    char_index <= 0;
                    if (got_nack) begin
                        state <= STATE_ERR_SEND;
                    end else begin
                        // Convert ADC value to hex string
                        hex_msg[2] <= nibble_to_hex(adc_value[15:12]);
                        hex_msg[3] <= nibble_to_hex(adc_value[11:8]);
                        hex_msg[4] <= nibble_to_hex(adc_value[7:4]);
                        hex_msg[5] <= nibble_to_hex(adc_value[3:0]);
                        state <= STATE_HEX_SEND;
                    end
                end
            end

            // ================================================================
            // HEX OUTPUT: "0xNNNN\r\n"
            // ================================================================

            STATE_HEX_SEND: begin
                if (!uart_tx_busy) begin
                    uart_tx_data <= hex_msg[char_index];
                    uart_tx_start <= 1'b1;
                    state <= STATE_HEX_WAIT;
                end
            end

            STATE_HEX_WAIT: begin
                if (!uart_tx_busy && !uart_tx_start) begin
                    if (char_index == HEX_MSG_LEN - 1) begin
                        char_index <= 0;
                        delay_counter <= 0;
                        state <= STATE_IDLE;
                    end else begin
                        char_index <= char_index + 1;
                        state <= STATE_HEX_SEND;
                    end
                end
            end

            // ================================================================
            // ERROR OUTPUT: "E\r\n"
            // ================================================================

            STATE_ERR_SEND: begin
                if (!uart_tx_busy) begin
                    uart_tx_data <= error_msg[char_index];
                    uart_tx_start <= 1'b1;
                    state <= STATE_ERR_WAIT;
                end
            end

            STATE_ERR_WAIT: begin
                if (!uart_tx_busy && !uart_tx_start) begin
                    if (char_index == ERROR_MSG_LEN - 1) begin
                        char_index <= 0;
                        delay_counter <= 0;
                        state <= STATE_IDLE;
                    end else begin
                        char_index <= char_index + 1;
                        state <= STATE_ERR_SEND;
                    end
                end
            end

            // ================================================================
            // DEFAULT: Start from beginning
            // ================================================================

            default: begin
                state <= STATE_STARTUP_SEND;
                char_index <= 0;
            end
        endcase
    end

endmodule
