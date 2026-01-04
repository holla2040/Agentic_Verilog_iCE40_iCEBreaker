// ============================================================================
// DAC-ADC Loopback - Top Level Module
// ============================================================================
//
// This top-level module connects all the submodules together:
//   - triangle_gen: Generates a slow triangle wave
//   - spi_dac: Sends the wave to the DAC
//   - spi_adc: Reads the signal back from the ADC
//   - uart_tx: Sends the ADC reading over serial
//
// HARDWARE:
//   - PMOD DA2 (Digilent) on PMOD1A - DAC121S101 12-bit DAC
//   - PMOD AD1 (Digilent) on PMOD1B - AD7476A 12-bit ADC
//   - Physical wire connecting DAC output to ADC input
//
// TIMING (12 MHz system clock):
//   - Triangle wave: 60-second full cycle (30s up, 30s down)
//   - ADC sampling: 10 Hz (every 100ms)
//   - UART: 115200 baud
//
// ============================================================================

module top (
    input  wire clk,           // 12 MHz system clock

    // DAC SPI interface (PMOD DA2 on PMOD1A)
    output wire dac_sync_n,    // Chip select (active LOW)
    output wire dac_din,       // Serial data out
    output wire dac_sclk,      // SPI clock

    // ADC SPI interface (PMOD AD1 on PMOD1B)
    output wire adc_cs_n,      // Chip select (active LOW)
    input  wire adc_sdata,     // Serial data FROM ADC (MISO)
    output wire adc_sclk,      // SPI clock to ADC

    // UART output
    output wire uart_tx        // UART transmit pin
);

    // ========================================================================
    // TIMING PARAMETERS
    // ========================================================================

    // ADC sample interval (10 Hz = 100ms = 1,200,000 clocks)
    localparam CLOCKS_PER_INTERVAL = 21'd1200000;

    // Message length for UART output: "0xNNN\r\n" = 7 characters
    localparam MSG_LEN = 7;

    // ========================================================================
    // INTERNAL SIGNALS
    // ========================================================================

    // Triangle wave generator output
    wire [11:0] triangle_value;

    // ADC interface signals
    reg         adc_start = 1'b0;
    wire [11:0] adc_data;
    wire        adc_busy;
    wire        adc_done;

    // UART interface signals
    reg  [7:0]  uart_data = 8'd0;
    reg         uart_start = 1'b0;
    wire        uart_busy;

    // Sample interval timer
    reg [20:0] interval_counter = 21'd0;

    // Message buffer and transmission state
    reg [7:0] message [0:6];
    reg [2:0] msg_index = 3'd0;
    reg       sending_message = 1'b0;

    // ========================================================================
    // HEX DIGIT TO ASCII CONVERSION
    // ========================================================================
    //
    // Function to convert a 4-bit value to ASCII hex character:
    //   0-9 → '0'-'9' (0x30-0x39)
    //   A-F → 'A'-'F' (0x41-0x46)

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
    // MODULE INSTANTIATIONS
    // ========================================================================

    // Triangle wave generator - creates slow ramp for DAC
    triangle_gen #(
        .CLOCKS_PER_STEP(17'd87891)  // ~30 seconds per 4096 steps
    ) u_triangle (
        .clk(clk),
        .value_o(triangle_value)
    );

    // DAC SPI driver - continuously sends triangle value
    spi_dac #(
        .SPI_HALF_PERIOD(1)          // 6 MHz SPI clock
    ) u_dac (
        .clk(clk),
        .data_i(triangle_value),
        .sync_n_o(dac_sync_n),
        .sclk_o(dac_sclk),
        .din_o(dac_din)
    );

    // ADC SPI driver - triggered by sample interval timer
    spi_adc u_adc (
        .clk(clk),
        .start_i(adc_start),
        .data_o(adc_data),
        .busy_o(adc_busy),
        .done_o(adc_done),
        .cs_n_o(adc_cs_n),
        .sclk_o(adc_sclk),
        .sdata_i(adc_sdata)
    );

    // UART transmitter - sends ADC readings as hex
    uart_tx #(
        .CLOCKS_PER_BIT(104)         // 115200 baud at 12 MHz
    ) u_uart (
        .clk(clk),
        .data_i(uart_data),
        .start_i(uart_start),
        .busy_o(uart_busy),
        .tx_o(uart_tx)
    );

    // ========================================================================
    // ADC SAMPLE INTERVAL TIMER (10 Hz)
    // ========================================================================
    //
    // Generates a single-clock pulse every 100ms to trigger ADC sampling.
    // Only triggers if ADC is idle and we're not currently sending a message.

    always @(posedge clk) begin
        // Default: adc_start is only high for one clock
        adc_start <= 1'b0;

        if (interval_counter == CLOCKS_PER_INTERVAL - 1) begin
            interval_counter <= 21'd0;

            // Only trigger if ADC is idle and not sending message
            if (!adc_busy && !sending_message) begin
                adc_start <= 1'b1;
            end
        end else begin
            interval_counter <= interval_counter + 1'b1;
        end
    end

    // ========================================================================
    // MESSAGE FORMATTING AND UART CONTROL
    // ========================================================================
    //
    // When ADC completes, format the result as "0xNNN\r\n" and send via UART.
    // Uses a simple state machine to send each character in sequence.

    always @(posedge clk) begin
        // Default: uart_start is only high for one clock
        uart_start <= 1'b0;

        if (adc_done) begin
            // ADC conversion complete - build the message
            message[0] <= "0";
            message[1] <= "x";
            message[2] <= hex_to_ascii(adc_data[11:8]);
            message[3] <= hex_to_ascii(adc_data[7:4]);
            message[4] <= hex_to_ascii(adc_data[3:0]);
            message[5] <= 8'h0D;     // \r (carriage return)
            message[6] <= 8'h0A;     // \n (newline)

            // Start sending
            msg_index <= 3'd0;
            sending_message <= 1'b1;
            uart_data <= "0";        // First character
            uart_start <= 1'b1;
        end
        else if (sending_message && !uart_busy && !uart_start) begin
            // UART finished sending previous character
            if (msg_index == MSG_LEN - 1) begin
                // All characters sent
                sending_message <= 1'b0;
            end else begin
                // Send next character
                msg_index <= msg_index + 1'b1;
                uart_data <= message[msg_index + 1];
                uart_start <= 1'b1;
            end
        end
    end

endmodule
