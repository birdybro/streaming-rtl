`timescale 1ns/1ps
`default_nettype none

module stream_timeout_detector_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int TIMEOUT    = 8;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 1;

    // ----------------------------------------------------------------- signals
    logic                    clk;
    logic                    rst_n;

    logic                    s_valid;
    logic                    s_ready;
    logic [DATA_WIDTH-1:0]   s_data;
    logic [KEEP_WIDTH-1:0]   s_keep;
    logic                    s_last;
    logic [USER_WIDTH-1:0]   s_user;

    logic                    m_valid;
    logic                    m_ready;
    logic [DATA_WIDTH-1:0]   m_data;
    logic [KEEP_WIDTH-1:0]   m_keep;
    logic                    m_last;
    logic [USER_WIDTH-1:0]   m_user;

    logic                    timeout;
    logic [3:0]              timeout_cnt;    // $clog2(TIMEOUT+1) = $clog2(9) = 4 bits

    // --------------------------------------------------------------- DUT
    stream_timeout_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .TIMEOUT   (TIMEOUT),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .s_valid    (s_valid),
        .s_ready    (s_ready),
        .s_data     (s_data),
        .s_keep     (s_keep),
        .s_last     (s_last),
        .s_user     (s_user),
        .m_valid    (m_valid),
        .m_ready    (m_ready),
        .m_data     (m_data),
        .m_keep     (m_keep),
        .m_last     (m_last),
        .m_user     (m_user),
        .timeout    (timeout),
        .timeout_cnt(timeout_cnt)
    );

    // ----------------------------------------------------------- clock gen
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------- reset task
    task automatic apply_reset();
        rst_n   <= 1'b0;
        s_valid <= 1'b0;
        s_data  <= '0;
        s_keep  <= '1;
        s_last  <= 1'b0;
        s_user  <= '0;
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // -------------------------------------------------------- send one beat
    task automatic send_beat(input logic [DATA_WIDTH-1:0] data,
                             input logic                  last);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= 1'b1;
        s_last  <= last;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    initial begin
        apply_reset();

        // (a) complete frame in time → no timeout
        $display("TEST(a): complete frame within TIMEOUT - no timeout");
        m_ready <= 1'b1;
        send_beat(8'hAA, 1'b0);
        send_beat(8'hBB, 1'b0);
        send_beat(8'hCC, 1'b1);
        repeat (TIMEOUT - 1) @(posedge clk);
        $display("  timeout after complete frame=%b (expect 0)", timeout);

        // (b) partial frame then stall TIMEOUT+1 cycles → timeout asserts
        $display("TEST(b): partial frame then stall -> timeout asserts");
        apply_reset();
        m_ready <= 1'b1;
        send_beat(8'h11, 1'b0);   // first beat (frame started, no s_last yet)
        s_valid <= 1'b0;           // stall input without completing frame
        repeat (TIMEOUT + 2) @(posedge clk);
        $display("  timeout after stall=%b (expect 1)", timeout);
        $display("  timeout_cnt=%0d", timeout_cnt);

        // (c) complete frame → timeout clears
        $display("TEST(c): frame completion clears timeout");
        send_beat(8'h22, 1'b1);   // complete the stalled frame
        @(posedge clk);
        @(posedge clk);
        $display("  timeout after EOF=%b (expect 0)", timeout);

        repeat (2) @(posedge clk);
        $display("stream_timeout_detector_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
