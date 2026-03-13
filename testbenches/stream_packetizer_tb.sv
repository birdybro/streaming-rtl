`timescale 1ns/1ps
`default_nettype none

module stream_packetizer_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int PACKET_LEN = 4;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 1;

    // ----------------------------------------------------------------- signals
    logic                  clk;
    logic                  rst_n;

    // slave side – no s_last port on packetizer
    logic                  s_valid;
    logic                  s_ready;
    logic [DATA_WIDTH-1:0] s_data;
    logic [KEEP_WIDTH-1:0] s_keep;
    logic [USER_WIDTH-1:0] s_user;

    logic                  m_valid;
    logic                  m_ready;
    logic [DATA_WIDTH-1:0] m_data;
    logic [KEEP_WIDTH-1:0] m_keep;
    logic                  m_last;
    logic [USER_WIDTH-1:0] m_user;

    // --------------------------------------------------------------- DUT
    stream_packetizer #(
        .DATA_WIDTH(DATA_WIDTH),
        .PACKET_LEN(PACKET_LEN),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data (s_data),
        .s_keep (s_keep),
        .s_user (s_user),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data (m_data),
        .m_keep (m_keep),
        .m_last (m_last),
        .m_user (m_user)
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
        s_user  <= '0;
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ----------------------------------------------------------- send_beat
    // Packetizer has no s_last input – omitted from signature
    task automatic send_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic [USER_WIDTH-1:0] user
    );
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_user  <= user;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
    endtask

    // ----------------------------------------------------------- recv_beat
    logic [DATA_WIDTH-1:0] r_data;
    logic [KEEP_WIDTH-1:0] r_keep;
    logic                  r_last;
    logic [USER_WIDTH-1:0] r_user;

    task automatic recv_beat();
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        r_data = m_data;
        r_keep = m_keep;
        r_last = m_last;
        r_user = m_user;
    endtask

    // ================================================================ stimulus
    int beat_num;
    int err_count;

    initial begin
        $display("=== stream_packetizer_tb START ===");
        err_count = 0;
        apply_reset();

        // ------------------------------------------------------ test (a)
        $display("[TEST A] 8 continuous beats – expect m_last every %0d", PACKET_LEN);
        beat_num = 0;
        fork
            begin
                for (int i = 0; i < 8; i++)
                    send_beat(8'(8'hA0 + i), 1'b1, 1'b0);
            end
            begin
                for (int i = 0; i < 8; i++) begin
                    recv_beat();
                    beat_num++;
                    $display("  beat %0d  data=0x%02h  last=%0b", beat_num, r_data, r_last);
                    if ((beat_num % PACKET_LEN == 0) && !r_last) begin
                        $display("  ERROR: m_last missing at beat %0d", beat_num);
                        err_count++;
                    end
                    if ((beat_num % PACKET_LEN != 0) && r_last) begin
                        $display("  ERROR: spurious m_last at beat %0d", beat_num);
                        err_count++;
                    end
                end
            end
        join
        $display("[TEST A] DONE");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (b)
        $display("[TEST B] One packet with output backpressure");
        m_ready <= 1'b0;
        fork
            begin
                for (int i = 0; i < PACKET_LEN; i++)
                    send_beat(8'(8'hB0 + i), 1'b1, 1'b0);
                $display("  all %0d input beats accepted", PACKET_LEN);
            end
            begin
                repeat (6) @(posedge clk);
                m_ready <= 1'b1;
                $display("  m_ready released after 6 stall cycles");
            end
        join
        do @(posedge clk); while (!m_valid);
        $display("  first output beat  last=%0b", m_last);
        repeat (4) @(posedge clk);
        $display("[TEST B] DONE");

        // ------------------------------------------------------ test (c)
        $display("[TEST C] Reset mid-stream");
        fork
            begin
                for (int i = 0; i < PACKET_LEN; i++)
                    send_beat(8'(8'hC0 + i), 1'b1, 1'b0);
            end
            begin
                repeat (3) @(posedge clk);
                rst_n <= 1'b0;
                @(posedge clk);
                rst_n <= 1'b1;
                $display("  reset asserted and released mid-stream");
            end
        join_any
        disable fork;
        s_valid <= 1'b0;
        @(negedge clk);
        rst_n <= 1'b1;
        repeat (4) @(posedge clk);
        $display("[TEST C] DONE");

        if (err_count == 0)
            $display("=== stream_packetizer_tb PASSED ===");
        else
            $display("=== stream_packetizer_tb FAILED (%0d errors) ===", err_count);
        $finish;
    end

endmodule
`default_nettype wire
