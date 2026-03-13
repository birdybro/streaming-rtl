`timescale 1ns/1ps
`default_nettype none

module stream_upsizer_tb;

    // ------------------------------------------------------------------ params
    localparam int S_DATA_WIDTH = 8;
    localparam int RATIO        = 4;
    localparam int M_DATA_WIDTH = S_DATA_WIDTH * RATIO;
    localparam int USER_WIDTH   = 1;

    // ----------------------------------------------------------------- signals
    logic                        clk;
    logic                        rst_n;

    logic                        s_valid;
    logic                        s_ready;
    logic [S_DATA_WIDTH-1:0]     s_data;
    logic [0:0]                  s_keep;
    logic                        s_last;
    logic [USER_WIDTH-1:0]       s_user;

    logic                        m_valid;
    logic                        m_ready;
    logic [M_DATA_WIDTH-1:0]     m_data;
    logic [RATIO-1:0]            m_keep;
    logic                        m_last;
    logic [USER_WIDTH-1:0]       m_user;

    // --------------------------------------------------------------- DUT
    stream_upsizer #(
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .RATIO       (RATIO),
        .USER_WIDTH  (USER_WIDTH)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data (s_data),
        .s_keep (s_keep),
        .s_last (s_last),
        .s_user (s_user),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data (m_data),
        .m_keep (m_keep),
        .m_last (m_last),
        .m_user (m_user)
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
        m_ready <= 1'b0;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // -------------------------------------------------------- send narrow beat
    task automatic send_beat(input logic [S_DATA_WIDTH-1:0] data,
                             input logic                    last);
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= 1'b1;
        s_last  <= last;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------- receive wide beat
    task automatic recv_beat(output logic [M_DATA_WIDTH-1:0] data,
                             output logic                    last);
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        data    = m_data;
        last    = m_last;
        m_ready <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    logic [M_DATA_WIDTH-1:0] rx_data;
    logic                    rx_last;

    initial begin
        apply_reset();

        // (a) send 4 narrow beats → 1 wide beat
        $display("TEST(a): 4 narrow beats -> 1 wide beat");
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid <= 1'b1; s_data <= 8'hAA; s_keep <= 1'b1; s_last <= 1'b0; @(posedge clk);
        s_data  <= 8'hBB; @(posedge clk);
        s_data  <= 8'hCC; @(posedge clk);
        s_data  <= 8'hDD; s_last <= 1'b1; @(posedge clk);
        s_valid <= 1'b0; s_last <= 1'b0;
        repeat (4) @(posedge clk);
        $display("  m_data=0x%08h m_last=%b", m_data, m_last);

        // (b) s_last mid-way forces flush
        $display("TEST(b): s_last on beat 2 flushes partial word");
        m_ready <= 1'b0;
        apply_reset();
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid <= 1'b1; s_data <= 8'h11; s_keep <= 1'b1; s_last <= 1'b0; @(posedge clk);
        s_data  <= 8'h22; s_last <= 1'b1; @(posedge clk);
        s_valid <= 1'b0; s_last <= 1'b0;
        repeat (4) @(posedge clk);
        $display("  m_data=0x%08h m_last=%b m_keep=%04b", m_data, m_last, m_keep);

        // (c) backpressure on output
        $display("TEST(c): backpressure on output");
        apply_reset();
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid <= 1'b1; s_data <= 8'h01; s_last <= 1'b0; @(posedge clk);
        s_data  <= 8'h02; @(posedge clk);
        s_data  <= 8'h03; @(posedge clk);
        s_data  <= 8'h04; s_last <= 1'b1; @(posedge clk);
        s_valid <= 1'b0; s_last <= 1'b0;
        repeat (3) @(posedge clk);
        $display("  m_valid=%b (output held)", m_valid);
        m_ready <= 1'b1;
        @(posedge clk);
        $display("  m_valid=%b m_data=0x%08h after release", m_valid, m_data);
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_upsizer_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
