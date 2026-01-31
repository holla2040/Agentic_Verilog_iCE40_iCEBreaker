// ============================================================================
// SPI Master Controller - Shared Library Module
// ============================================================================
//
// Canonical SPI master for the iCEBreaker shared module library.
// Supports all 4 SPI modes via CPOL and CPHA parameters.
//
// INTERFACE CONVENTIONS (library standard):
//   - All inputs use _i suffix, outputs use _o suffix
//   - clk_i: System clock input
//   - rst_i: Synchronous reset (active HIGH)
//   - ready_o: HIGH when idle/ready to accept commands
//   - start_i: Single-clock pulse to begin operation
//
// SPI MODES:
//   Mode | CPOL | CPHA | SCLK Idle | Sample Edge | Shift Edge
//   -----|------|------|-----------|-------------|------------
//     0  |  0   |  0   |    LOW    |   Rising    |  Falling
//     1  |  0   |  1   |    LOW    |   Falling   |  Rising
//     2  |  1   |  0   |    HIGH   |   Falling   |  Rising
//     3  |  1   |  1   |    HIGH   |   Rising    |  Falling
//
// CRITICAL TIMING FOR CPHA=0:
//   In CPHA=0 mode, the slave outputs data when CS falls, BEFORE any clock
//   edge. This master correctly samples that first bit on the FIRST clock
//   edge, not after creating a spurious falling edge first.
//
//   Correct sequence for CPHA=0:
//     1. CS falls -> slave outputs first bit immediately
//     2. First clock edge (rising for CPOL=0) -> master samples first bit
//     3. Second clock edge (falling) -> slave shifts to next bit
//     4. Repeat...
//
// USAGE:
//   1. Wait for ready_o == 1
//   2. Load data_i with data to send (or don't care for read-only)
//   3. Assert start_i for one clock cycle
//   4. ready_o goes LOW during transfer
//   5. When ready_o goes HIGH, read data_o for received data
//
// PARAMETERS:
//   CPOL: Clock polarity (0 = idle LOW, 1 = idle HIGH)
//   CPHA: Clock phase (0 = sample on 1st edge, 1 = sample on 2nd edge)
//   WIDTH: Number of bits per transfer (default 8)
//   HALF_PERIOD: SCLK half-period in clk_i cycles (default 6 = 1 MHz @ 12 MHz)
//
// ============================================================================

module spi_master #(
    parameter CPOL = 0,              // Clock polarity
    parameter CPHA = 0,              // Clock phase
    parameter WIDTH = 8,             // Bits per transfer
    parameter HALF_PERIOD = 6        // SCLK half-period in clk_i cycles
) (
    input  wire             clk_i,
    input  wire             rst_i,

    // Data interface
    input  wire [WIDTH-1:0] data_i,  // MOSI data to send
    input  wire             start_i, // Pulse to begin transfer
    output reg  [WIDTH-1:0] data_o,  // MISO data received
    output wire             ready_o, // HIGH when idle/ready

    // SPI bus
    output reg              sclk_o,  // SPI clock
    output reg              mosi_o,  // Master Out, Slave In
    input  wire             miso_i,  // Master In, Slave Out
    output reg              cs_n_o   // Chip select (active LOW)
);

    // ========================================================================
    // INTERNAL SIGNALS
    // ========================================================================

    reg busy = 1'b0;
    assign ready_o = ~busy;

    // Shift registers
    reg [WIDTH-1:0] tx_shift = {WIDTH{1'b0}};
    reg [WIDTH-1:0] rx_shift = {WIDTH{1'b0}};

    // Bit counter
    reg [$clog2(WIDTH)-1:0] bit_count = 0;

    // Timer for half-period delays
    reg [$clog2(HALF_PERIOD)-1:0] timer = 0;

    // ========================================================================
    // STATE MACHINE
    // ========================================================================
    //
    // The state machine handles all 4 SPI modes correctly.
    //
    // Key insight: In CPHA=0, sample happens on FIRST edge after CS.
    //              In CPHA=1, sample happens on SECOND edge after CS.
    //
    // For CPHA=0: IDLE -> SETUP -> SAMPLE_EDGE -> SHIFT_EDGE -> (repeat) -> DONE
    // For CPHA=1: IDLE -> SETUP -> SHIFT_EDGE -> SAMPLE_EDGE -> (repeat) -> DONE

    localparam S_IDLE        = 3'd0;
    localparam S_SETUP       = 3'd1;  // CS asserted, setup first bit
    localparam S_FIRST_EDGE  = 3'd2;  // First clock edge of current bit
    localparam S_SECOND_EDGE = 3'd3;  // Second clock edge of current bit
    localparam S_DONE        = 3'd4;  // Transfer complete, deassert CS

    reg [2:0] state = S_IDLE;

    // Derived clock values based on CPOL
    wire sclk_idle = CPOL ? 1'b1 : 1'b0;
    wire sclk_active = CPOL ? 1'b0 : 1'b1;

    // ========================================================================
    // MAIN STATE MACHINE
    // ========================================================================

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= S_IDLE;
            busy <= 1'b0;
            cs_n_o <= 1'b1;          // CS inactive (HIGH)
            sclk_o <= sclk_idle;     // Clock at idle level
            mosi_o <= 1'b0;
            tx_shift <= {WIDTH{1'b0}};
            rx_shift <= {WIDTH{1'b0}};
            data_o <= {WIDTH{1'b0}};
            bit_count <= 0;
            timer <= 0;
        end else begin
            case (state)
                // ----------------------------------------------------------------
                // IDLE: Wait for start signal
                // ----------------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    cs_n_o <= 1'b1;
                    sclk_o <= sclk_idle;
                    timer <= 0;

                    if (start_i) begin
                        busy <= 1'b1;
                        tx_shift <= data_i;
                        rx_shift <= {WIDTH{1'b0}};
                        bit_count <= 0;
                        state <= S_SETUP;
                    end
                end

                // ----------------------------------------------------------------
                // SETUP: Assert CS, output first MOSI bit, wait setup time
                // ----------------------------------------------------------------
                // For CPHA=0: Slave outputs first MISO bit when CS falls.
                //             We need to sample it on the first clock edge.
                // For CPHA=1: First clock edge is for shifting, not sampling.
                S_SETUP: begin
                    cs_n_o <= 1'b0;              // Assert CS
                    sclk_o <= sclk_idle;         // Clock stays at idle
                    mosi_o <= tx_shift[WIDTH-1]; // Output MSB first

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 0;
                        state <= S_FIRST_EDGE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // FIRST_EDGE: Create first clock transition
                // ----------------------------------------------------------------
                // CPHA=0: This is the SAMPLE edge (data captured here)
                // CPHA=1: This is the SHIFT edge (data changes here)
                S_FIRST_EDGE: begin
                    sclk_o <= sclk_active;       // Toggle clock to active level

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 0;

                        if (CPHA == 0) begin
                            // CPHA=0: Sample MISO on this (first) edge
                            rx_shift <= {rx_shift[WIDTH-2:0], miso_i};
                        end else begin
                            // CPHA=1: Shift to next bit on this edge
                            tx_shift <= {tx_shift[WIDTH-2:0], 1'b0};
                            mosi_o <= tx_shift[WIDTH-2];
                        end

                        state <= S_SECOND_EDGE;
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // SECOND_EDGE: Create second clock transition
                // ----------------------------------------------------------------
                // CPHA=0: This is the SHIFT edge (slave shifts to next bit)
                // CPHA=1: This is the SAMPLE edge (data captured here)
                S_SECOND_EDGE: begin
                    sclk_o <= sclk_idle;         // Toggle clock back to idle

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 0;

                        if (CPHA == 0) begin
                            // CPHA=0: Shift to next bit on this edge
                            tx_shift <= {tx_shift[WIDTH-2:0], 1'b0};
                            mosi_o <= tx_shift[WIDTH-2];
                        end else begin
                            // CPHA=1: Sample MISO on this (second) edge
                            rx_shift <= {rx_shift[WIDTH-2:0], miso_i};
                        end

                        // Check if all bits done
                        if (bit_count == WIDTH - 1) begin
                            state <= S_DONE;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                            state <= S_FIRST_EDGE;
                        end
                    end else begin
                        timer <= timer + 1'b1;
                    end
                end

                // ----------------------------------------------------------------
                // DONE: Deassert CS, return to idle
                // ----------------------------------------------------------------
                S_DONE: begin
                    sclk_o <= sclk_idle;

                    if (timer == HALF_PERIOD - 1) begin
                        timer <= 0;
                        cs_n_o <= 1'b1;          // Deassert CS
                        data_o <= rx_shift;      // Output received data
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
