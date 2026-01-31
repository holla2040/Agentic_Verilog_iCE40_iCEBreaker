// ============================================================================
// UART RX Testbench
// ============================================================================

`timescale 1ns/1ps

module uart_rx_tb;

    parameter CLK_PERIOD = 83.33;        // 12 MHz
    parameter CLOCKS_PER_BIT = 104;      // 115200 baud
    parameter BIT_PERIOD = CLK_PERIOD * CLOCKS_PER_BIT;

    reg        clk = 0;
    reg        rst = 0;
    reg        rx = 1;                   // Idle HIGH
    wire [7:0] data;
    wire       valid;

    integer errors = 0;
    integer i;

    always #(CLK_PERIOD/2) clk = ~clk;

    uart_rx #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) dut (
        .clk_i(clk),
        .rst_i(rst),
        .rx_i(rx),
        .data_o(data),
        .valid_o(valid)
    );

    // Task to send a byte
    task send_byte;
        input [7:0] byte_to_send;
        begin
            // Start bit
            rx = 0;
            #BIT_PERIOD;

            // 8 data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                rx = byte_to_send[i];
                #BIT_PERIOD;
            end

            // Stop bit
            rx = 1;
            #BIT_PERIOD;
        end
    endtask

    // Task to send and verify
    task send_and_check;
        input [7:0] byte_to_send;
        begin
            fork
                // Send the byte
                send_byte(byte_to_send);

                // Wait for valid pulse and check
                begin
                    wait(valid);
                    @(posedge clk);
                    if (data !== byte_to_send) begin
                        $display("FAIL: Sent 0x%02X, received 0x%02X", byte_to_send, data);
                        errors = errors + 1;
                    end else begin
                        $display("PASS: Sent and received 0x%02X correctly", byte_to_send);
                    end
                end
            join
        end
    endtask

    initial begin
        $dumpfile("uart_rx_tb.vcd");
        $dumpvars(0, uart_rx_tb);

        $display("");
        $display("===========================================");
        $display("UART RX Testbench - 115200 baud");
        $display("===========================================");
        $display("");

        // Reset
        rst = 1;
        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 5);

        // Test 1: Verify idle state
        if (valid !== 0) begin
            $display("FAIL: valid_o should be LOW after reset");
            errors = errors + 1;
        end else begin
            $display("PASS: valid_o is LOW after reset");
        end

        #(BIT_PERIOD * 2);

        // Test 2: Receive 0x55
        $display("Test: Receiving 0x55...");
        send_and_check(8'h55);

        #(BIT_PERIOD * 2);

        // Test 3: Receive 0xAA
        $display("Test: Receiving 0xAA...");
        send_and_check(8'hAA);

        #(BIT_PERIOD * 2);

        // Test 4: Receive 'A' (0x41)
        $display("Test: Receiving 'A' (0x41)...");
        send_and_check(8'h41);

        #(BIT_PERIOD * 2);

        // Test 5: Receive 0x00
        $display("Test: Receiving 0x00...");
        send_and_check(8'h00);

        #(BIT_PERIOD * 2);

        // Test 6: Receive 0xFF
        $display("Test: Receiving 0xFF...");
        send_and_check(8'hFF);

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

        #(BIT_PERIOD * 5);
        $finish;
    end

    // Timeout
    initial begin
        #(BIT_PERIOD * 200);
        $display("TIMEOUT!");
        $finish;
    end

endmodule
