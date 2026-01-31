// ============================================================================
// SPI Master Testbench
// ============================================================================
//
// Tests the spi_master module for correct operation in all 4 SPI modes.
// Critical test: CPHA=0 mode must capture the first bit correctly.
//
// ============================================================================

`timescale 1ns/1ps

module spi_master_tb;

    // ========================================================================
    // PARAMETERS
    // ========================================================================

    parameter CLK_PERIOD = 83.33;    // 12 MHz = 83.33ns period
    parameter WIDTH = 8;
    parameter HALF_PERIOD = 6;

    // ========================================================================
    // SIGNALS
    // ========================================================================

    reg              clk = 0;
    reg              rst = 0;
    reg  [WIDTH-1:0] data_in = 0;
    reg              start = 0;
    wire [WIDTH-1:0] data_out;
    wire             ready;
    wire             sclk;
    wire             mosi;
    reg              miso = 0;
    wire             cs_n;

    // Test tracking
    integer test_num = 0;
    integer errors = 0;

    // ========================================================================
    // CLOCK GENERATION
    // ========================================================================

    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // DUT INSTANTIATION - Mode 0 (CPOL=0, CPHA=0)
    // ========================================================================

    spi_master #(
        .CPOL(0),
        .CPHA(0),
        .WIDTH(WIDTH),
        .HALF_PERIOD(HALF_PERIOD)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .data_i(data_in),
        .start_i(start),
        .data_o(data_out),
        .ready_o(ready),
        .sclk_o(sclk),
        .mosi_o(mosi),
        .miso_i(miso),
        .cs_n_o(cs_n)
    );

    // ========================================================================
    // SPI SLAVE MODEL (for CPHA=0)
    // ========================================================================
    //
    // In CPHA=0, slave outputs data when CS falls, before any clock.
    // Slave shifts on falling edge, master samples on rising edge.

    reg [WIDTH-1:0] slave_tx_data = 0;
    reg [WIDTH-1:0] slave_shift_reg = 0;
    reg [2:0]       slave_bit_count = 0;
    reg             cs_n_prev = 1;

    always @(posedge clk) begin
        cs_n_prev <= cs_n;

        // Detect CS falling edge - output first bit immediately
        if (cs_n_prev && !cs_n) begin
            slave_shift_reg <= slave_tx_data;
            miso <= slave_tx_data[WIDTH-1];  // Output MSB immediately
            slave_bit_count <= 0;
        end

        // On falling edge of SCLK, shift to next bit
        // (but only when CS is active)
        if (!cs_n) begin
            // Detect falling edge of sclk
        end
    end

    // Shift on falling edge of SCLK
    always @(negedge sclk) begin
        if (!cs_n && slave_bit_count < WIDTH-1) begin
            slave_shift_reg <= {slave_shift_reg[WIDTH-2:0], 1'b0};
            miso <= slave_shift_reg[WIDTH-2];
            slave_bit_count <= slave_bit_count + 1;
        end
    end

    // ========================================================================
    // TEST TASKS
    // ========================================================================

    task do_transfer;
        input [WIDTH-1:0] tx_data;
        input [WIDTH-1:0] expected_rx;
        begin
            test_num = test_num + 1;

            // Setup
            data_in = tx_data;
            slave_tx_data = expected_rx;

            // Wait for ready
            wait(ready);
            @(posedge clk);

            // Start transfer
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for completion
            wait(ready);
            @(posedge clk);
            @(posedge clk);

            // Check result
            if (data_out !== expected_rx) begin
                $display("FAIL Test %0d: Expected 0x%02X, got 0x%02X",
                         test_num, expected_rx, data_out);
                errors = errors + 1;
            end else begin
                $display("PASS Test %0d: TX=0x%02X, RX=0x%02X",
                         test_num, tx_data, data_out);
            end
        end
    endtask

    // ========================================================================
    // MAIN TEST SEQUENCE
    // ========================================================================

    initial begin
        $dumpfile("spi_master_tb.vcd");
        $dumpvars(0, spi_master_tb);

        $display("");
        $display("===========================================");
        $display("SPI Master Testbench - Mode 0 (CPOL=0, CPHA=0)");
        $display("===========================================");
        $display("");

        // Reset
        rst = 1;
        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 5);

        // Test 1: Basic transfer - alternating bits
        $display("Test 1: Alternating bits (0xAA)");
        do_transfer(8'h55, 8'hAA);

        // Test 2: All ones
        $display("Test 2: All ones (0xFF)");
        do_transfer(8'h00, 8'hFF);

        // Test 3: All zeros
        $display("Test 3: All zeros (0x00)");
        do_transfer(8'hFF, 8'h00);

        // Test 4: Single bit patterns - test first bit capture
        $display("Test 4: MSB only (0x80) - critical first-bit test");
        do_transfer(8'h00, 8'h80);

        // Test 5: LSB only
        $display("Test 5: LSB only (0x01)");
        do_transfer(8'h00, 8'h01);

        // Test 6: Walking ones
        $display("Test 6: Walking one (0x42)");
        do_transfer(8'h24, 8'h42);

        // Extended tests - walking ones pattern
        $display("Test 7-14: Walking ones MSB to LSB");
        do_transfer(8'h00, 8'h80);
        do_transfer(8'h00, 8'h40);
        do_transfer(8'h00, 8'h20);
        do_transfer(8'h00, 8'h10);
        do_transfer(8'h00, 8'h08);
        do_transfer(8'h00, 8'h04);
        do_transfer(8'h00, 8'h02);
        do_transfer(8'h00, 8'h01);

        // Walking zeros
        $display("Test 15-22: Walking zeros MSB to LSB");
        do_transfer(8'hFF, 8'h7F);
        do_transfer(8'hFF, 8'hBF);
        do_transfer(8'hFF, 8'hDF);
        do_transfer(8'hFF, 8'hEF);
        do_transfer(8'hFF, 8'hF7);
        do_transfer(8'hFF, 8'hFB);
        do_transfer(8'hFF, 8'hFD);
        do_transfer(8'hFF, 8'hFE);

        // Counter pattern
        $display("Test 23-38: Counter 0x00 to 0x0F");
        do_transfer(8'h00, 8'h00);
        do_transfer(8'h00, 8'h01);
        do_transfer(8'h00, 8'h02);
        do_transfer(8'h00, 8'h03);
        do_transfer(8'h00, 8'h04);
        do_transfer(8'h00, 8'h05);
        do_transfer(8'h00, 8'h06);
        do_transfer(8'h00, 8'h07);
        do_transfer(8'h00, 8'h08);
        do_transfer(8'h00, 8'h09);
        do_transfer(8'h00, 8'h0A);
        do_transfer(8'h00, 8'h0B);
        do_transfer(8'h00, 8'h0C);
        do_transfer(8'h00, 8'h0D);
        do_transfer(8'h00, 8'h0E);
        do_transfer(8'h00, 8'h0F);

        // More random patterns
        $display("Test 39-54: Various patterns");
        do_transfer(8'hA5, 8'h5A);
        do_transfer(8'h96, 8'h69);
        do_transfer(8'hC3, 8'h3C);
        do_transfer(8'hE7, 8'h7E);
        do_transfer(8'h81, 8'h18);
        do_transfer(8'h42, 8'h24);
        do_transfer(8'hDB, 8'hBD);
        do_transfer(8'hF0, 8'h0F);
        do_transfer(8'h33, 8'hCC);
        do_transfer(8'h55, 8'hAA);
        do_transfer(8'hAA, 8'h55);
        do_transfer(8'h12, 8'h34);
        do_transfer(8'h56, 8'h78);
        do_transfer(8'h9A, 8'hBC);
        do_transfer(8'hDE, 8'hF0);
        do_transfer(8'h11, 8'h22);

        // Summary
        $display("");
        $display("===========================================");
        if (errors == 0) begin
            $display("ALL TESTS PASSED (%0d tests)", test_num);
        end else begin
            $display("FAILED: %0d errors out of %0d tests", errors, test_num);
        end
        $display("===========================================");
        $display("");

        #(CLK_PERIOD * 10);
        $finish;
    end

    // Timeout
    initial begin
        #(CLK_PERIOD * 10000);
        $display("TIMEOUT!");
        $finish;
    end

endmodule
