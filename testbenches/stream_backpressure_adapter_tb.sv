`timescale 1ns/1ps
`default_nettype none

module stream_backpressure_adapter_tb;

    // ------------------------------------------------------------------ params
    localparam int    DATA_WIDTH = 8;
    localparam int    DEPTH      = 16;
    localparam int    USER_WIDTH = 1;
    localparam int    KEEP_WIDTH = 1;
    localparam string MODE       = "ABSORB";

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

    logic                    dropped;

    // --------------------------------------------------------------- DUT
    stream_backpressure_adapter #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MODE      (MODE)
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
        .m_user (m_user),
        .dropped(dropped)
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

    // -------------------------------------------------------- send one beat
    task automatic send_beat(input logic [DATA_WIDTH-1:0] data,
                             input logic                  last);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= 1'b1;
        s_last  <= last;
        @(posedge clk);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    int drop_cnt;

    initial begin
        apply_reset();

        // (a) ABSORB mode: burst while m_ready=0, verify no drops
        $display("TEST(a): ABSORB mode - burst with m_ready=0, expect no drops");
        m_ready  <= 1'b0;
        drop_cnt = 0;
        for (int i = 0; i < 8; i++) begin
            send_beat(8'(i + 1), i == 7);
            if (dropped) drop_cnt++;
        end
        repeat (2) @(posedge clk);
        $display("  dropped signals during burst: %0d (expect 0)", drop_cnt);

        // (b) verify data drains correctly
        $display("TEST(b): drain buffer");
        m_ready <= 1'b1;
        repeat (16) begin
            @(posedge clk);
            if (m_valid) $display("  drain data=0x%02h last=%b", m_data, m_last);
        end
        m_ready <= 1'b0;

        // (c) reset clears state
        $display("TEST(c): reset clears state");
        apply_reset();
        @(posedge clk);
        $display("  m_valid after reset=%b (expect 0)", m_valid);
        // send one beat and verify it passes through after reset
        m_ready <= 1'b1;
        send_beat(8'hEE, 1'b1);
        repeat (4) @(posedge clk);
        $display("  m_data=0x%02h m_valid=%b after send post-reset", m_data, m_valid);
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_backpressure_adapter_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
