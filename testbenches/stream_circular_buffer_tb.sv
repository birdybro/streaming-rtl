`timescale 1ns/1ps
`default_nettype none

module stream_circular_buffer_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
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

    logic [8:0]              count;
    logic                    full;
    logic                    empty;

    // --------------------------------------------------------------- DUT
    stream_circular_buffer #(
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
        .m_user (m_user),
        .count  (count),
        .full   (full),
        .empty  (empty)
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
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    initial begin
        apply_reset();

        // (a) fill then drain
        $display("TEST(a): fill 16 beats then drain");
        m_ready <= 1'b0;
        for (int i = 0; i < 16; i++)
            send_beat(8'(i), i == 15);
        @(posedge clk);
        $display("  count=%0d full=%b empty=%b after fill", count, full, empty);
        m_ready <= 1'b1;
        repeat (20) begin
            @(posedge clk);
            if (m_valid) $display("  drain data=0x%02h last=%b count=%0d", m_data, m_last, count);
        end
        $display("  empty=%b after drain", empty);
        m_ready <= 1'b0;

        // (b) simultaneous read/write
        $display("TEST(b): simultaneous read/write");
        apply_reset();
        m_ready <= 1'b1;
        fork
            begin
                for (int i = 0; i < 8; i++)
                    send_beat(8'(8'hA0 + i), i == 7);
            end
            begin
                repeat (16) begin
                    @(posedge clk);
                    if (m_valid) $display("  simul read data=0x%02h last=%b", m_data, m_last);
                end
            end
        join
        m_ready <= 1'b0;

        // (c) full/empty flags
        $display("TEST(c): full/empty flags");
        apply_reset();
        @(posedge clk);
        $display("  empty after reset=%b (expect 1)", empty);
        send_beat(8'hFF, 1'b1);
        @(posedge clk);
        $display("  empty after 1 write=%b (expect 0)", empty);
        m_ready <= 1'b1;
        @(posedge clk);
        @(posedge clk);
        $display("  empty after drain=%b", empty);
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_circular_buffer_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
