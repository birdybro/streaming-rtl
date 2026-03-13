`timescale 1ns/1ps
`default_nettype none

module stream_frame_detector_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 1;

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

    logic                  sof;
    logic                  eof;

    // --------------------------------------------------------------- DUT
    stream_frame_detector #(
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
        .sof    (sof),
        .eof    (eof)
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
    // sof and eof are also captured at the handshake cycle
    logic [DATA_WIDTH-1:0] r_data;
    logic [KEEP_WIDTH-1:0] r_keep;
    logic                  r_last;
    logic [USER_WIDTH-1:0] r_user;
    logic                  r_sof;
    logic                  r_eof;

    task automatic recv_beat();
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        r_data = m_data;
        r_keep = m_keep;
        r_last = m_last;
        r_user = m_user;
        r_sof  = sof;
        r_eof  = eof;
    endtask

    // ================================================================ stimulus
    int err_count;
    int beat_num;

    initial begin
        $display("=== stream_frame_detector_tb START ===");
        err_count = 0;
        apply_reset();

        // ------------------------------------------------------ test (a)
        $display("[TEST A] 4-beat frame: sof on beat 1, eof on beat 4");
        beat_num = 0;
        fork
            begin
                for (int i = 0; i < 4; i++)
                    send_beat(8'(8'hA0 + i), 1'b1, (i == 3) ? 1'b1 : 1'b0, 1'b0);
            end
            begin
                for (int i = 0; i < 4; i++) begin
                    recv_beat();
                    beat_num++;
                    $display("  beat %0d  data=0x%02h  sof=%0b  eof=%0b",
                             beat_num, r_data, r_sof, r_eof);
                    if (beat_num == 1 && !r_sof) begin
                        $display("  ERROR: sof missing on first beat"); err_count++;
                    end
                    if (beat_num == 4 && !r_eof) begin
                        $display("  ERROR: eof missing on last beat");  err_count++;
                    end
                    if (beat_num > 1 && beat_num < 4 && r_sof) begin
                        $display("  ERROR: spurious sof at beat %0d", beat_num); err_count++;
                    end
                    if (beat_num < 4 && r_eof) begin
                        $display("  ERROR: spurious eof at beat %0d", beat_num); err_count++;
                    end
                end
            end
        join
        $display("[TEST A] DONE");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (b)
        $display("[TEST B] Single-beat frame: sof and eof both asserted");
        fork
            send_beat(8'hBB, 1'b1, 1'b1, 1'b0);
            recv_beat();
        join
        $display("  data=0x%02h  sof=%0b  eof=%0b", r_data, r_sof, r_eof);
        if (!r_sof) begin
            $display("  ERROR: sof missing on single-beat frame"); err_count++;
        end
        if (!r_eof) begin
            $display("  ERROR: eof missing on single-beat frame"); err_count++;
        end
        $display("[TEST B] DONE");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (c)
        $display("[TEST C] 2 back-to-back frames");
        for (int f = 0; f < 2; f++) begin
            beat_num = 0;
            fork
                begin
                    for (int i = 0; i < 4; i++)
                        send_beat(8'(8'hC0 + 8'h10 * f + i), 1'b1,
                                  (i == 3) ? 1'b1 : 1'b0, 1'b0);
                end
                begin
                    for (int i = 0; i < 4; i++) begin
                        recv_beat();
                        beat_num++;
                        $display("  f%0d beat %0d  sof=%0b  eof=%0b",
                                 f, beat_num, r_sof, r_eof);
                        if (beat_num == 1 && !r_sof) begin
                            $display("  ERROR: f%0d sof missing", f); err_count++;
                        end
                        if (beat_num == 4 && !r_eof) begin
                            $display("  ERROR: f%0d eof missing", f); err_count++;
                        end
                    end
                end
            join
            @(posedge clk);
        end
        $display("[TEST C] DONE");

        if (err_count == 0)
            $display("=== stream_frame_detector_tb PASSED ===");
        else
            $display("=== stream_frame_detector_tb FAILED (%0d errors) ===", err_count);
        $finish;
    end

endmodule
`default_nettype wire
