// ============================================================================
// UART TX Testbench
// ============================================================================

`timescale 1ns/1ps

module uart_tx_tb;

    parameter CLK_PERIOD = 83.33;        // 12 MHz
    parameter CLOCKS_PER_BIT = 104;      // 115200 baud
    parameter BIT_PERIOD = CLK_PERIOD * CLOCKS_PER_BIT;

    reg        clk = 0;
    reg        rst = 0;
    reg  [7:0] data = 0;
    reg        start = 0;
    wire       ready;
    wire       tx;

    integer errors = 0;
    reg [7:0] received_byte;
    integer i;

    always #(CLK_PERIOD/2) clk = ~clk;

    uart_tx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) dut (
        .clk_i(clk),
        .rst_i(rst),
        .data_i(data),
        .start_i(start),
        .ready_o(ready),
        .tx_o(tx)
    );

    // Task to receive and verify a byte
    task receive_and_check;
        input [7:0] expected;
        begin
            // Wait for start bit (tx goes low)
            wait(tx == 0);

            // Wait to middle of start bit
            #(BIT_PERIOD / 2);

            if (tx !== 0) begin
                $display("FAIL: Start bit not LOW");
                errors = errors + 1;
            end

            // Sample 8 data bits (LSB first)
            received_byte = 0;
            for (i = 0; i < 8; i = i + 1) begin
                #BIT_PERIOD;
                received_byte[i] = tx;
            end

            // Check stop bit
            #BIT_PERIOD;
            if (tx !== 1) begin
                $display("FAIL: Stop bit not HIGH");
                errors = errors + 1;
            end

            // Verify data
            if (received_byte !== expected) begin
                $display("FAIL: Expected 0x%02X, received 0x%02X", expected, received_byte);
                errors = errors + 1;
            end else begin
                $display("PASS: Sent and received 0x%02X correctly", received_byte);
            end
        end
    endtask

    initial begin
        $dumpfile("uart_tx_tb.vcd");
        $dumpvars(0, uart_tx_tb);

        $display("");
        $display("===========================================");
        $display("UART TX Testbench - 115200 baud");
        $display("===========================================");
        $display("");

        // Reset
        rst = 1;
        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 5);

        // Test 1: Verify idle state
        if (ready !== 1) begin
            $display("FAIL: ready_o should be HIGH after reset");
            errors = errors + 1;
        end else begin
            $display("PASS: ready_o is HIGH after reset");
        end

        if (tx !== 1) begin
            $display("FAIL: tx_o should be HIGH (idle) after reset");
            errors = errors + 1;
        end else begin
            $display("PASS: tx_o is HIGH (idle) after reset");
        end

        // Test 2: Send 0x55 (alternating bits)
        $display("Test: Sending 0x55...");
        data = 8'h55;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        fork
            receive_and_check(8'h55);
        join

        // Wait for ready
        wait(ready);
        #(CLK_PERIOD * 10);

        // Test 3: Send 0xAA
        $display("Test: Sending 0xAA...");
        data = 8'hAA;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        fork
            receive_and_check(8'hAA);
        join

        wait(ready);
        #(CLK_PERIOD * 10);

        // Test 4: Send 'A' (0x41)
        $display("Test: Sending 'A' (0x41)...");
        data = 8'h41;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        fork
            receive_and_check(8'h41);
        join

        wait(ready);

        // Summary
        $display("");
        $display("===========================================");
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("FAILED: %0d errors", errors);
        end
        $display("===========================================");
        $display("");

        #(CLK_PERIOD * 100);
        $finish;
    end

    // Timeout
    initial begin
        #(BIT_PERIOD * 100);
        $display("TIMEOUT!");
        $finish;
    end

endmodule
