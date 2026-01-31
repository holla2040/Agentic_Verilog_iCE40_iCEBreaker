// ============================================================================
// AD7476A 12-bit SPI ADC - Device Wrapper Module
// ============================================================================
//
// High-level wrapper for the Analog Devices AD7476A 12-bit SAR ADC.
// Instantiates spi_master internally with correct timing parameters.
//
// FEATURES:
//   - 12-bit resolution
//   - Up to 1 MSPS sampling rate
//   - Single-ended input
//   - SPI Mode 0 (CPOL=0, CPHA=0)
//
// DATA FORMAT:
//   The AD7476A sends 16 bits on each conversion:
//   - Bits 15-14: Leading zeros
//   - Bits 13-2:  12-bit ADC result (MSB first)
//   - Bits 1-0:   Trailing zeros
//
//   So we extract bits [13:2] from the received 16-bit word.
//
// SPI TIMING:
//   - CS falls -> conversion starts
//   - Data appears on SDATA after CS falls (before first clock!)
//   - SCLK samples data on rising edge (Mode 0)
//   - 16 clock cycles per conversion
//
// INTERFACE:
//   - Pulse start_i to begin conversion
//   - Wait for valid_o pulse
//   - Read 12-bit result from data_o
//
// NOTE: This uses spi_master with CPOL=0, CPHA=0 which correctly handles
//       the case where data appears on CS fall before the first clock edge.
//
// ============================================================================

module ad7476a #(
    parameter HALF_PERIOD = 6        // SPI timing (1 MHz @ 12 MHz sys clock)
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // SPI bus
    output wire        sclk_o,
    input  wire        sdata_i,      // ADC data out (MISO)
    output wire        cs_n_o,

    // User interface
    input  wire        start_i,      // Start conversion
    output reg  [11:0] data_o,       // 12-bit ADC result
    output wire        ready_o,
    output reg         valid_o
);

    // ========================================================================
    // SPI MASTER INSTANCE
    // ========================================================================
    //
    // AD7476A uses SPI Mode 0:
    //   CPOL = 0 (clock idles LOW)
    //   CPHA = 0 (data sampled on rising edge)
    //
    // WIDTH = 16 because AD7476A sends 16 bits per conversion

    wire [15:0] spi_data_out;
    wire        spi_ready;

    spi_master #(
        .CPOL(0),
        .CPHA(0),
        .WIDTH(16),
        .HALF_PERIOD(HALF_PERIOD)
    ) spi_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .data_i(16'd0),              // Don't care for read-only ADC
        .start_i(start_i),
        .data_o(spi_data_out),
        .ready_o(spi_ready),
        .sclk_o(sclk_o),
        .mosi_o(),                   // Not connected (ADC is read-only)
        .miso_i(sdata_i),
        .cs_n_o(cs_n_o)
    );

    // ========================================================================
    // READY SIGNAL
    // ========================================================================

    assign ready_o = spi_ready;

    // ========================================================================
    // DATA EXTRACTION AND VALID PULSE
    // ========================================================================
    //
    // When SPI transfer completes, extract 12-bit result from bits [13:2]
    // and pulse valid_o.

    reg spi_ready_prev = 1'b1;

    always @(posedge clk_i) begin
        valid_o <= 1'b0;
        spi_ready_prev <= spi_ready;

        if (rst_i) begin
            data_o <= 12'd0;
            valid_o <= 1'b0;
            spi_ready_prev <= 1'b1;
        end else begin
            // Detect rising edge of spi_ready (transfer complete)
            if (spi_ready && !spi_ready_prev) begin
                // Extract 12-bit result from 16-bit word
                // Bits [15:14] = leading zeros
                // Bits [13:2]  = 12-bit ADC value
                // Bits [1:0]   = trailing zeros
                data_o <= spi_data_out[13:2];
                valid_o <= 1'b1;
            end
        end
    end

endmodule
