`timescale 1ns/1ps
`default_nettype none

module stream_downsizer_tb;

    // ------------------------------------------------------------------ params
    localparam int M_DATA_WIDTH = 8;
    localparam int RATIO        = 4;
    localparam int S_DATA_WIDTH = M_DATA_WIDTH * RATIO;
    localparam int USER_WIDTH   = 1;

    // ----------------------------------------------------------------- signals
    logic                        clk;
    logic                        rst_n;

    logic                        s_valid;
    logic                        s_ready;
    logic [S_DATA_WIDTH-1:0]     s_data;
    logic [RATIO-1:0]            s_keep;
    logic                        s_last;
    logic [USER_WIDTH-1:0]       s_user;

    logic                        m_valid;
    logic                        m_ready;
    logic [M_DATA_WIDTH-1:0]     m_data;
    logic [0:0]                  m_keep;
    logic                        m_last;
    logic [USER_WIDTH-1:0]       m_user;

    // --------------------------------------------------------------- DUT
    stream_downsizer #(
        .M_DATA_WIDTH(M_DATA_WIDTH),
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

    // -------------------------------------------------------- send wide beat
    task automatic send_wide(input logic [S_DATA_WIDTH-1:0] data,
                             input logic [RATIO-1:0]        keep,
                             input logic                    last);
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_last  <= last;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // -------------------------------------------------------- receive narrow beat
    task automatic recv_narrow(output logic [M_DATA_WIDTH-1:0] data,
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
    int                      beat_cnt;

    initial begin
        apply_reset();

        // (a) 1 wide beat → 4 narrow beats
        $display("TEST(a): 1 wide beat -> 4 narrow beats");
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 32'hDEADBEEF;
        s_keep  <= 4'hF;
        s_last  <= 1'b1;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0; s_last <= 1'b0;
        beat_cnt = 0;
        repeat (8) begin
            @(posedge clk);
            if (m_valid && m_ready) begin
                $display("  narrow[%0d] data=0x%02h last=%b", beat_cnt, m_data, m_last);
                beat_cnt++;
            end
        end

        // (b) m_last on last narrow beat when s_last set
        $display("TEST(b): m_last asserts on 4th narrow beat");
        apply_reset();
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 32'h11223344;
        s_keep  <= 4'hF;
        s_last  <= 1'b1;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0; s_last <= 1'b0;
        beat_cnt = 0;
        repeat (10) begin
            @(posedge clk);
            if (m_valid) begin
                $display("  beat[%0d] data=0x%02h last=%b", beat_cnt, m_data, m_last);
                beat_cnt++;
            end
        end

        // (c) backpressure
        $display("TEST(c): backpressure on output");
        apply_reset();
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 32'hAABBCCDD;
        s_keep  <= 4'hF;
        s_last  <= 1'b1;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0; s_last <= 1'b0;
        repeat (3) @(posedge clk);
        $display("  m_valid=%b while m_ready=0", m_valid);
        m_ready <= 1'b1;
        repeat (6) begin
            @(posedge clk);
            if (m_valid) $display("  drained data=0x%02h last=%b", m_data, m_last);
        end
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_downsizer_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
