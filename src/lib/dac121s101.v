// ============================================================================
// DAC121S101 12-bit SPI DAC - Device Wrapper Module
// ============================================================================
//
// High-level wrapper for the Texas Instruments DAC121S101 12-bit DAC.
// Instantiates spi_master internally with correct timing parameters.
//
// FEATURES:
//   - 12-bit resolution
//   - Up to 30 MHz SPI clock
//   - Rail-to-rail output
//   - Power-down modes available
//
// DATA FORMAT:
//   The DAC121S101 expects 16 bits on each write:
//   - Bits 15-14: Don't care (we send 00)
//   - Bits 13-12: Mode (00 = normal operation)
//   - Bits 11-0:  12-bit DAC value (MSB first)
//
//   So we format the data as: {2'b00, 2'b00, data_i[11:0]}
//
// SPI TIMING:
//   - Uses SPI Mode 1 (CPOL=0, CPHA=1)
//   - Data captured on falling edge of SCLK
//   - SYNC (CS) must go low before first clock
//   - 16 clock cycles per update
//
// INTERFACE:
//   - Load data_i with 12-bit value
//   - Pulse start_i to begin transfer
//   - Wait for ready_o to go HIGH
//
// ============================================================================

module dac121s101 #(
    parameter HALF_PERIOD = 6        // SPI timing (1 MHz @ 12 MHz sys clock)
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // SPI bus
    output wire        sclk_o,
    output wire        mosi_o,       // DAC data in
    output wire        cs_n_o,       // Called SYNC on DAC datasheet

    // User interface
    input  wire [11:0] data_i,       // 12-bit value to output
    input  wire        start_i,
    output wire        ready_o
);

    // ========================================================================
    // DATA FORMATTING
    // ========================================================================
    //
    // Format 16-bit word for DAC:
    //   Bits 15-14: Don't care (00)
    //   Bits 13-12: Mode (00 = normal operation, 01 = power-down 1k, etc.)
    //   Bits 11-0:  DAC data value

    wire [15:0] dac_word = {2'b00, 2'b00, data_i};

    // ========================================================================
    // SPI MASTER INSTANCE
    // ========================================================================
    //
    // DAC121S101 uses SPI Mode 1:
    //   CPOL = 0 (clock idles LOW)
    //   CPHA = 1 (data sampled on falling edge)
    //
    // Note: CPHA=1 means data changes on rising edge, sampled on falling.
    // This matches the DAC121S101 timing requirement.

    spi_master #(
        .CPOL(0),
        .CPHA(1),
        .WIDTH(16),
        .HALF_PERIOD(HALF_PERIOD)
    ) spi_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .data_i(dac_word),
        .start_i(start_i),
        .data_o(),                   // Not used (DAC is write-only)
        .ready_o(ready_o),
        .sclk_o(sclk_o),
        .mosi_o(mosi_o),
        .miso_i(1'b0),               // Not connected (DAC is write-only)
        .cs_n_o(cs_n_o)
    );

endmodule
