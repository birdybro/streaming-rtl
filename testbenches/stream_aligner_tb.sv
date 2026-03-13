`timescale 1ns/1ps
`default_nettype none

module stream_aligner_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 32;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 4;

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

    // --------------------------------------------------------------- DUT
    stream_aligner #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
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
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // -------------------------------------------------------- send one beat
    task automatic send_beat(input logic [DATA_WIDTH-1:0] data,
                             input logic [KEEP_WIDTH-1:0] keep,
                             input logic                  last);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_last  <= last;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    initial begin
        apply_reset();

        // (a) all keep bits set → pass-through
        $display("TEST(a): all keep bits set - pass-through");
        m_ready <= 1'b1;
        send_beat(32'hDEADBEEF, 4'hF, 1'b1);
        @(posedge clk);
        $display("  m_data=0x%08h m_keep=%04b m_last=%b", m_data, m_keep, m_last);

        // (b) gaps in keep (partial valid bytes)
        $display("TEST(b): gaps in keep bits");
        send_beat(32'hAABBCCDD, 4'b1010, 1'b1);
        @(posedge clk);
        $display("  m_data=0x%08h m_keep=%04b m_last=%b", m_data, m_keep, m_last);

        send_beat(32'h12345678, 4'b0011, 1'b0);
        @(posedge clk);
        $display("  m_data=0x%08h m_keep=%04b m_last=%b", m_data, m_keep, m_last);

        // (c) backpressure
        $display("TEST(c): backpressure");
        apply_reset();
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 32'h11223344;
        s_keep  <= 4'hF;
        s_last  <= 1'b1;
        repeat (3) @(posedge clk);
        $display("  m_valid=%b while m_ready=0", m_valid);
        m_ready <= 1'b1;
        @(posedge clk);
        $display("  m_valid=%b m_data=0x%08h after release", m_valid, m_data);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_aligner_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
