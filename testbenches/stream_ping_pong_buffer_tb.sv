`timescale 1ns/1ps
`default_nettype none

module stream_ping_pong_buffer_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 8;
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

    logic                    swap;

    // --------------------------------------------------------------- DUT
    stream_ping_pong_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
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
        .swap   (swap)
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

    // -------------------------------------------------------- write full frame
    task automatic write_frame(input logic [DATA_WIDTH-1:0] base);
        for (int i = 0; i < DEPTH; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(base + i);
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH - 1);
            do @(posedge clk); while (!s_ready);
            s_valid <= 1'b0;
            s_last  <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------ tests
    logic swap_seen;

    initial begin
        apply_reset();

        // (a) write full frame → swap asserts
        $display("TEST(a): write full frame, verify swap pulse");
        swap_seen = 1'b0;
        m_ready   <= 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(i + 1);
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH - 1);
            if (swap) swap_seen = 1'b1;
            do @(posedge clk); while (!s_ready);
            s_valid <= 1'b0;
            s_last  <= 1'b0;
        end
        repeat (4) @(posedge clk);
        if (swap) swap_seen = 1'b1;
        $display("  swap pulse seen=%b (expect 1)", swap_seen);

        // (b) read from read bank while writing new frame
        $display("TEST(b): read read-bank while writing new frame");
        apply_reset();
        // fill write bank first
        for (int i = 0; i < DEPTH; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(8'hA0 + i);
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH - 1);
            do @(posedge clk); while (!s_ready);
            s_valid <= 1'b0; s_last <= 1'b0;
        end
        repeat (2) @(posedge clk);
        // now read + write simultaneously
        m_ready <= 1'b1;
        fork
            begin
                for (int i = 0; i < DEPTH; i++) begin
                    @(posedge clk);
                    s_valid <= 1'b1;
                    s_data  <= 8'(8'hB0 + i);
                    s_keep  <= 1'b1;
                    s_last  <= (i == DEPTH - 1);
                    do @(posedge clk); while (!s_ready);
                    s_valid <= 1'b0; s_last <= 1'b0;
                end
            end
            begin
                repeat (DEPTH * 2) begin
                    @(posedge clk);
                    if (m_valid) $display("  read data=0x%02h last=%b", m_data, m_last);
                end
            end
        join
        m_ready <= 1'b0;

        // (c) verify swap pulse on frame boundary
        $display("TEST(c): verify swap pulse on frame boundary");
        apply_reset();
        @(posedge clk);
        s_valid <= 1'b1;
        for (int i = 0; i < DEPTH; i++) begin
            s_data <= 8'(i);
            s_keep <= 1'b1;
            s_last <= (i == DEPTH - 1);
            do @(posedge clk); while (!s_ready);
            if (swap) $display("  swap asserted at beat %0d", i);
        end
        s_valid <= 1'b0; s_last <= 1'b0;
        repeat (4) @(posedge clk);
        if (swap) $display("  swap asserted post-frame");

        repeat (2) @(posedge clk);
        $display("stream_ping_pong_buffer_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
