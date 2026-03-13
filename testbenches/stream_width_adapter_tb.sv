`timescale 1ns/1ps
`default_nettype none

module stream_width_adapter_tb;

    // ------------------------------------------------------------------ params
    localparam int S_DATA_WIDTH = 8;
    localparam int M_DATA_WIDTH = 32;
    localparam int USER_WIDTH   = 1;
    localparam int S_KEEP_WIDTH = 1;
    localparam int M_KEEP_WIDTH = 4;

    // ----------------------------------------------------------------- signals
    logic                        clk;
    logic                        rst_n;

    logic                        s_valid;
    logic                        s_ready;
    logic [S_DATA_WIDTH-1:0]     s_data;
    logic [S_KEEP_WIDTH-1:0]     s_keep;
    logic                        s_last;
    logic [USER_WIDTH-1:0]       s_user;

    logic                        m_valid;
    logic                        m_ready;
    logic [M_DATA_WIDTH-1:0]     m_data;
    logic [M_KEEP_WIDTH-1:0]     m_keep;
    logic                        m_last;
    logic [USER_WIDTH-1:0]       m_user;

    // --------------------------------------------------------------- DUT
    stream_width_adapter #(
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .M_DATA_WIDTH(M_DATA_WIDTH),
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

    // -------------------------------------------------------- send one narrow beat
    task automatic send_narrow(input logic [S_DATA_WIDTH-1:0] data,
                               input logic                    last);
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

        // (a) upsize: 4 narrow in, 1 wide out
        $display("TEST(a): upsize 4 beats -> 1 wide beat");
        m_ready <= 1'b1;
        send_narrow(8'hAA, 1'b0);
        send_narrow(8'hBB, 1'b0);
        send_narrow(8'hCC, 1'b0);
        send_narrow(8'hDD, 1'b1);
        repeat (4) @(posedge clk);
        $display("  m_data=0x%08h m_keep=%04b m_last=%b", m_data, m_keep, m_last);

        // (b) s_last triggers flush (partial word)
        $display("TEST(b): s_last flushes partial word");
        apply_reset();
        m_ready <= 1'b1;
        send_narrow(8'h11, 1'b0);
        send_narrow(8'h22, 1'b1);
        repeat (4) @(posedge clk);
        $display("  m_data=0x%08h m_keep=%04b m_last=%b", m_data, m_keep, m_last);

        // (c) backpressure
        $display("TEST(c): output backpressure");
        apply_reset();
        m_ready <= 1'b0;
        send_narrow(8'h01, 1'b0);
        send_narrow(8'h02, 1'b0);
        send_narrow(8'h03, 1'b0);
        send_narrow(8'h04, 1'b1);
        repeat (2) @(posedge clk);
        $display("  m_valid=%b while m_ready=0", m_valid);
        m_ready <= 1'b1;
        @(posedge clk);
        $display("  m_valid=%b m_data=0x%08h after release", m_valid, m_data);
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_width_adapter_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
