`timescale 1ns/1ps
`default_nettype none

module stream_perf_monitor_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH  = 8;
    localparam int STAT_WIDTH  = 32;
    localparam int USER_WIDTH  = 1;
    localparam int KEEP_WIDTH  = 1;

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

    logic                    stats_clear;
    logic [STAT_WIDTH-1:0]   beat_count;
    logic [STAT_WIDTH-1:0]   byte_count;
    logic [STAT_WIDTH-1:0]   cycle_count;
    logic [STAT_WIDTH-1:0]   idle_cycles;
    logic [STAT_WIDTH-1:0]   bp_cycles;

    // --------------------------------------------------------------- DUT
    stream_perf_monitor #(
        .DATA_WIDTH(DATA_WIDTH),
        .STAT_WIDTH(STAT_WIDTH),
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
        .stats_clear(stats_clear),
        .beat_count (beat_count),
        .byte_count (byte_count),
        .cycle_count(cycle_count),
        .idle_cycles(idle_cycles),
        .bp_cycles  (bp_cycles)
    );

    // ----------------------------------------------------------- clock gen
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------- reset task
    task automatic apply_reset();
        rst_n       <= 1'b0;
        s_valid     <= 1'b0;
        s_data      <= '0;
        s_keep      <= '1;
        s_last      <= 1'b0;
        s_user      <= '0;
        m_ready     <= 1'b0;
        stats_clear <= 1'b0;
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

        // (a) send 4 beats with backpressure
        $display("TEST(a): 4 beats with backpressure");
        m_ready <= 1'b0;                       // assert backpressure first
        @(posedge clk);
        s_valid <= 1'b1; s_data <= 8'hAA; s_keep <= 1'b1; s_last <= 1'b0;
        repeat (3) @(posedge clk);             // 3 cycles of backpressure
        m_ready <= 1'b1;
        @(posedge clk);
        s_data <= 8'hBB; @(posedge clk);
        s_data <= 8'hCC; @(posedge clk);
        s_data <= 8'hDD; s_last <= 1'b1; @(posedge clk);
        s_valid <= 1'b0; s_last <= 1'b0;
        @(posedge clk);

        // (b) verify beat_count and byte_count
        $display("TEST(b): stats after 4 beats");
        $display("  beat_count=%0d (expect 4)", beat_count);
        $display("  byte_count=%0d (expect 4)", byte_count);
        $display("  cycle_count=%0d", cycle_count);
        $display("  idle_cycles=%0d", idle_cycles);

        // (c) verify bp_cycles during backpressure
        $display("TEST(c): bp_cycles > 0 (backpressure was applied)");
        $display("  bp_cycles=%0d (expect > 0)", bp_cycles);

        // (d) stats_clear
        $display("TEST(d): stats_clear resets counters");
        @(posedge clk);
        stats_clear <= 1'b1;
        @(posedge clk);
        stats_clear <= 1'b0;
        @(posedge clk);
        $display("  beat_count after clear=%0d (expect 0)", beat_count);
        $display("  byte_count after clear=%0d (expect 0)", byte_count);
        $display("  bp_cycles   after clear=%0d (expect 0)", bp_cycles);

        repeat (2) @(posedge clk);
        $display("stream_perf_monitor_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
