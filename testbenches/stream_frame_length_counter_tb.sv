`timescale 1ns/1ps
`default_nettype none

module stream_frame_length_counter_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int MAX_LEN    = 256;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 1;
    // $clog2(MAX_LEN+1) = $clog2(257) = 9
    localparam int CNT_W      = 9;

    // ----------------------------------------------------------------- signals
    logic                  clk;
    logic                  rst_n;

    logic                  s_valid;
    logic                  s_ready;
    logic [DATA_WIDTH-1:0] s_data;
    logic [KEEP_WIDTH-1:0] s_keep;
    logic                  s_last;
    logic [USER_WIDTH-1:0] s_user;

    logic                  m_valid;
    logic                  m_ready;
    logic [DATA_WIDTH-1:0] m_data;
    logic [KEEP_WIDTH-1:0] m_keep;
    logic                  m_last;
    logic [USER_WIDTH-1:0] m_user;

    logic [CNT_W-1:0]      count;   // count[8:0]

    // --------------------------------------------------------------- DUT
    stream_frame_length_counter #(
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_LEN   (MAX_LEN),
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
        .count  (count)
    );

    // ------------------------------------------------------------ clock gen
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------- apply_reset
    task automatic apply_reset();
        rst_n   <= 1'b0;
        s_valid <= 1'b0;
        s_data  <= '0;
        s_keep  <= '1;
        s_last  <= 1'b0;
        s_user  <= '0;
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ----------------------------------------------------------- send_beat
    task automatic send_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last,
        input logic [USER_WIDTH-1:0] user
    );
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_last  <= last;
        s_user  <= user;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ----------------------------------------------------------- recv_beat
    // count is also captured at the handshake cycle
    logic [DATA_WIDTH-1:0] r_data;
    logic [KEEP_WIDTH-1:0] r_keep;
    logic                  r_last;
    logic [USER_WIDTH-1:0] r_user;
    logic [CNT_W-1:0]      r_count;

    task automatic recv_beat();
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        r_data  = m_data;
        r_keep  = m_keep;
        r_last  = m_last;
        r_user  = m_user;
        r_count = count;
    endtask

    // ================================================================ stimulus
    int err_count;
    int frame_len;

    initial begin
        $display("=== stream_frame_length_counter_tb START ===");
        err_count = 0;
        apply_reset();

        // ------------------------------------------------------ test (a)
        $display("[TEST A] 4-beat frame – expect count=4 on last beat");
        fork
            begin
                for (int i = 0; i < 4; i++)
                    send_beat(8'(8'hA0 + i), 1'b1, (i == 3) ? 1'b1 : 1'b0, 1'b0);
            end
            begin
                for (int i = 0; i < 4; i++) begin
                    recv_beat();
                    $display("  beat %0d  data=0x%02h  last=%0b  count=%0d",
                             i, r_data, r_last, r_count);
                    if (r_last && r_count != CNT_W'(4)) begin
                        $display("  ERROR: expected count=4 on last, got %0d", r_count);
                        err_count++;
                    end
                end
            end
        join
        $display("[TEST A] DONE");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (b)
        $display("[TEST B] 1-beat frame – expect count=1");
        fork
            send_beat(8'hBB, 1'b1, 1'b1, 1'b0);
            recv_beat();
        join
        $display("  data=0x%02h  last=%0b  count=%0d", r_data, r_last, r_count);
        if (r_count != CNT_W'(1)) begin
            $display("  ERROR: expected count=1, got %0d", r_count);
            err_count++;
        end
        $display("[TEST B] DONE");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (c)
        $display("[TEST C] 2 frames in sequence (lengths 3 and 5)");
        for (int f = 0; f < 2; f++) begin
            frame_len = (f == 0) ? 3 : 5;
            fork
                begin
                    for (int i = 0; i < frame_len; i++)
                        send_beat(8'(8'hC0 + i), 1'b1,
                                  (i == frame_len - 1) ? 1'b1 : 1'b0, 1'b0);
                end
                begin
                    for (int i = 0; i < frame_len; i++) begin
                        recv_beat();
                        $display("  f%0d beat %0d  last=%0b  count=%0d",
                                 f, i, r_last, r_count);
                        if (r_last && r_count != CNT_W'(frame_len)) begin
                            $display("  ERROR: f%0d expected count=%0d, got %0d",
                                     f, frame_len, r_count);
                            err_count++;
                        end
                    end
                end
            join
            @(posedge clk);
        end
        $display("[TEST C] DONE");

        if (err_count == 0)
            $display("=== stream_frame_length_counter_tb PASSED ===");
        else
            $display("=== stream_frame_length_counter_tb FAILED (%0d errors) ===",
                     err_count);
        $finish;
    end

endmodule
`default_nettype wire
