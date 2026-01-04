// ============================================================================
// SPI ADC Driver for AD7476A
// ============================================================================
//
// This module provides a reusable SPI interface for the AD7476A 12-bit ADC.
// It performs a conversion when triggered and outputs the 12-bit result.
//
// AD7476A SPI PROTOCOL:
//   - CS falling edge starts conversion (~800ns)
//   - Data clocked out on FALLING edges of SCLK
//   - We sample data on RISING edges (when stable)
//   - 16-bit frame: [0][0][0][0][DB11][DB10]...[DB1][DB0]
//
// ACTIVE-LOW ACCENT:
//   - SCLK idles HIGH
//   - CS is active LOW
//
// INTERFACE:
//   - Assert start_i for one clock to begin conversion
//   - busy_o goes high during conversion
//   - When busy_o falls, data_o contains valid 12-bit result
//   - done_o pulses high for one clock when conversion completes
//
// ============================================================================

module spi_adc (
    input  wire        clk,          // System clock
    input  wire        start_i,      // Start conversion (single clock pulse)

    output reg  [11:0] data_o,       // 12-bit ADC result
    output reg         busy_o,       // High during conversion
    output reg         done_o,       // Pulses high when conversion complete

    // SPI interface
    output reg         cs_n_o,       // Chip select (active LOW)
    output reg         sclk_o,       // SPI clock
    input  wire        sdata_i       // Serial data FROM ADC (MISO)
);

    // ========================================================================
    // STATE MACHINE DEFINITIONS
    // ========================================================================
    //
    // States for reading from the AD7476A:
    //   IDLE  → Wait for start trigger
    //   START → Assert CS low, prepare for clocking
    //   SHIFT → Clock in 16 bits (4 zeros + 12 data)
    //   DONE  → CS high, output result

    localparam STATE_IDLE  = 2'd0;
    localparam STATE_START = 2'd1;
    localparam STATE_SHIFT = 2'd2;
    localparam STATE_DONE  = 2'd3;

    reg [1:0] state = STATE_IDLE;

    // ========================================================================
    // REGISTERS
    // ========================================================================

    reg [15:0] shift_reg = 16'd0;    // Shift register for incoming data
    reg [4:0]  bit_count = 5'd0;     // Count of bits received (0-15)
    reg        sclk_phase = 1'b0;    // Track SCLK phase

    // ========================================================================
    // ADC SPI STATE MACHINE
    // ========================================================================
    //
    // Reads 16 bits from the AD7476A:
    //   - Assert CS low to start conversion
    //   - Toggle SCLK 16 times
    //   - Sample SDATA on rising edge (data valid after falling edge)
    //   - Release CS high when done

    always @(posedge clk) begin
        // Default: done_o is only high for one clock
        done_o <= 1'b0;

        case (state)
            // ----------------------------------------------------------------
            // IDLE: Wait for start trigger
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                cs_n_o <= 1'b1;          // CS high (inactive)
                sclk_o <= 1'b1;          // SCLK idles high
                sclk_phase <= 1'b0;
                busy_o <= 1'b0;

                if (start_i) begin
                    busy_o <= 1'b1;
                    state <= STATE_START;
                end
            end

            // ----------------------------------------------------------------
            // START: Assert CS low to begin conversion
            // ----------------------------------------------------------------
            STATE_START: begin
                cs_n_o <= 1'b0;          // Assert CS low - starts conversion
                sclk_o <= 1'b1;          // SCLK starts high
                shift_reg <= 16'd0;
                bit_count <= 5'd0;
                sclk_phase <= 1'b0;
                state <= STATE_SHIFT;
            end

            // ----------------------------------------------------------------
            // SHIFT: Clock in 16 bits from ADC
            // ----------------------------------------------------------------
            // The AD7476A outputs data on the FALLING edge of SCLK.
            // We sample the data on the RISING edge (after it's stable).
            STATE_SHIFT: begin
                if (sclk_phase == 1'b0) begin
                    // Falling edge - ADC clocks out data
                    sclk_o <= 1'b0;
                    sclk_phase <= 1'b1;
                end else begin
                    // Rising edge - we sample the data
                    sclk_o <= 1'b1;
                    shift_reg <= {shift_reg[14:0], sdata_i};
                    sclk_phase <= 1'b0;

                    if (bit_count == 5'd15) begin
                        // All 16 bits received
                        state <= STATE_DONE;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end
            end

            // ----------------------------------------------------------------
            // DONE: Store result and signal completion
            // ----------------------------------------------------------------
            // Note: Due to SPI timing, we capture bits 1-16 instead of 0-15.
            // The first bit (output when CS falls) is missed because we
            // create a falling edge before sampling. To compensate, we
            // extract bits [12:1] instead of [11:0].
            STATE_DONE: begin
                cs_n_o <= 1'b1;          // Release CS high

                // Extract 12-bit result (shifted by 1 to compensate for timing)
                data_o <= shift_reg[12:1];
                done_o <= 1'b1;
                busy_o <= 1'b0;

                state <= STATE_IDLE;
            end

            default: begin
                state <= STATE_IDLE;
            end
        endcase
    end

endmodule
