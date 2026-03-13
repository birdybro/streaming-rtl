`timescale 1ns/1ps
`default_nettype none

module stream_rate_matcher_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 1;

    // ----------------------------------------------------------------- signals
    logic                    s_clk;
    logic                    s_rst_n;
    logic                    s_valid;
    logic                    s_ready;
    logic [DATA_WIDTH-1:0]   s_data;
    logic [KEEP_WIDTH-1:0]   s_keep;
    logic                    s_last;
    logic [USER_WIDTH-1:0]   s_user;

    logic                    m_clk;
    logic                    m_rst_n;
    logic                    m_valid;
    logic                    m_ready;
    logic [DATA_WIDTH-1:0]   m_data;
    logic [KEEP_WIDTH-1:0]   m_keep;
    logic                    m_last;
    logic [USER_WIDTH-1:0]   m_user;

    // --------------------------------------------------------------- DUT
    stream_rate_matcher #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .s_clk  (s_clk),
        .s_rst_n(s_rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data (s_data),
        .s_keep (s_keep),
        .s_last (s_last),
        .s_user (s_user),
        .m_clk  (m_clk),
        .m_rst_n(m_rst_n),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data (m_data),
        .m_keep (m_keep),
        .m_last (m_last),
        .m_user (m_user)
    );

    // ------------------------------------------------------- clock gen (dual)
    // s_clk: 10ns period (100 MHz), m_clk: 15ns period (~67 MHz)
    initial s_clk = 1'b0;
    always #5 s_clk = ~s_clk;

    initial m_clk = 1'b0;
    always #7 m_clk = ~m_clk;         // ~71 MHz; slightly different from spec to avoid glitching

    // ----------------------------------------------------------- reset task
    task automatic apply_reset();
        s_rst_n <= 1'b0;
        m_rst_n <= 1'b0;
        s_valid <= 1'b0;
        s_data  <= '0;
        s_keep  <= '1;
        s_last  <= 1'b0;
        s_user  <= '0;
        m_ready <= 1'b0;
        repeat (8) @(posedge s_clk);
        repeat (8) @(posedge m_clk);
        s_rst_n <= 1'b1;
        m_rst_n <= 1'b1;
        @(posedge s_clk);
        @(posedge m_clk);
    endtask

    // -------------------------------------------------------- send on s_clk
    task automatic send_s_beat(input logic [DATA_WIDTH-1:0] data,
                               input logic                  last);
        @(posedge s_clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= 1'b1;
        s_last  <= last;
        do @(posedge s_clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    logic [DATA_WIDTH-1:0] rx_data [0:3];
    int                    rx_cnt;

    initial begin
        apply_reset();

        // (a) write 4 beats on s_clk, read on m_clk
        $display("TEST(a): write 4 beats on s_clk, read on m_clk");
        m_ready <= 1'b1;
        send_s_beat(8'hAA, 1'b0);
        send_s_beat(8'hBB, 1'b0);
        send_s_beat(8'hCC, 1'b0);
        send_s_beat(8'hDD, 1'b1);

        rx_cnt = 0;
        repeat (40) begin
            @(posedge m_clk);
            if (m_valid && m_ready) begin
                $display("  rx[%0d] data=0x%02h last=%b", rx_cnt, m_data, m_last);
                rx_data[rx_cnt] = m_data;
                rx_cnt++;
            end
        end

        // (b) verify data order preserved
        $display("TEST(b): verify data order preserved");
        if (rx_cnt == 4) begin
            if (rx_data[0] == 8'hAA && rx_data[1] == 8'hBB &&
                rx_data[2] == 8'hCC && rx_data[3] == 8'hDD)
                $display("  ORDER OK: AA BB CC DD");
            else
                $display("  ORDER MISMATCH: %02h %02h %02h %02h",
                         rx_data[0], rx_data[1], rx_data[2], rx_data[3]);
        end else begin
            $display("  Only received %0d beats (expected 4)", rx_cnt);
        end

        repeat (4) @(posedge m_clk);
        $display("stream_rate_matcher_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
