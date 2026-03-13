`timescale 1ns/1ps
`default_nettype none

module stream_depacketizer_tb;

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

    logic [31:0]           frame_count;

    // --------------------------------------------------------------- DUT
    stream_depacketizer #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .s_valid    (s_valid),
        .s_ready    (s_ready),
        .s_data     (s_data),
        .s_keep     (s_keep),
        .s_last     (s_last),
        .s_user     (s_user),
        .m_valid    (m_valid),
        .m_ready    (m_ready),
        .m_data     (m_data),
        .m_keep     (m_keep),
        .m_last     (m_last),
        .m_user     (m_user),
        .frame_count(frame_count)
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
    int         err_count;
    logic [31:0] fc_before;

    initial begin
        $display("=== stream_depacketizer_tb START ===");
        err_count = 0;
        apply_reset();

        // ------------------------------------------------------ test (a)
        $display("[TEST A] 2 frames of 4 beats each");
        for (int f = 0; f < 2; f++) begin
            fork
                begin
                    for (int i = 0; i < 4; i++)
                        send_beat(8'(8'h10 * (f + 1) + i), 1'b1,
                                  (i == 3) ? 1'b1 : 1'b0, 1'b0);
                end
                begin
                    for (int i = 0; i < 4; i++) begin
                        recv_beat();
                        $display("  frame %0d beat %0d  data=0x%02h  last=%0b",
                                 f, i, r_data, r_last);
                    end
                end
            join
            @(posedge clk);
        end
        $display("[TEST A] DONE");

        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (b)
        $display("[TEST B] Verify frame_count increments per frame");
        fc_before = frame_count;
        $display("  frame_count before = %0d", fc_before);
        fork
            begin
                for (int i = 0; i < 4; i++)
                    send_beat(8'(8'hC0 + i), 1'b1, (i == 3) ? 1'b1 : 1'b0, 1'b0);
            end
            begin
                for (int i = 0; i < 4; i++)
                    recv_beat();
            end
        join
        repeat (2) @(posedge clk);
        $display("  frame_count after  = %0d", frame_count);
        if (frame_count != fc_before + 1) begin
            $display("  ERROR: expected frame_count=%0d, got %0d",
                     fc_before + 1, frame_count);
            err_count++;
        end
        $display("[TEST B] DONE");

        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (c)
        $display("[TEST C] Backpressure on output");
        m_ready <= 1'b0;
        fork
            begin
                for (int i = 0; i < 4; i++)
                    send_beat(8'(8'hD0 + i), 1'b1, (i == 3) ? 1'b1 : 1'b0, 1'b0);
                $display("  input frame accepted under backpressure");
            end
            begin
                repeat (8) @(posedge clk);
                m_ready <= 1'b1;
                $display("  m_ready released");
            end
        join
        for (int i = 0; i < 4; i++)
            recv_beat();
        $display("  output frame received after backpressure");
        repeat (4) @(posedge clk);
        $display("[TEST C] DONE");

        if (err_count == 0)
            $display("=== stream_depacketizer_tb PASSED ===");
        else
            $display("=== stream_depacketizer_tb FAILED (%0d errors) ===", err_count);
        $finish;
    end

endmodule
`default_nettype wire
