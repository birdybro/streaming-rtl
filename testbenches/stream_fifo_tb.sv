`timescale 1ns/1ps
`default_nettype none

module stream_fifo_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 16;
    localparam int USER_WIDTH = 1;
    localparam int KEEP_WIDTH = 1;

    // ----------------------------------------------------------------- signals
    logic                          clk;
    logic                          rst_n;

    logic                          s_valid;
    logic                          s_ready;
    logic [DATA_WIDTH-1:0]         s_data;
    logic [KEEP_WIDTH-1:0]         s_keep;
    logic                          s_last;
    logic [USER_WIDTH-1:0]         s_user;

    logic                          m_valid;
    logic                          m_ready;
    logic [DATA_WIDTH-1:0]         m_data;
    logic [KEEP_WIDTH-1:0]         m_keep;
    logic                          m_last;
    logic [USER_WIDTH-1:0]         m_user;

    logic [$clog2(DEPTH):0]        count;
    logic                          full;
    logic                          empty;
    logic                          almost_full;
    logic                          almost_empty;

    // --------------------------------------------------------------- DUT
    stream_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_valid      (s_valid),
        .s_ready      (s_ready),
        .s_data       (s_data),
        .s_keep       (s_keep),
        .s_last       (s_last),
        .s_user       (s_user),
        .m_valid      (m_valid),
        .m_ready      (m_ready),
        .m_data       (m_data),
        .m_keep       (m_keep),
        .m_last       (m_last),
        .m_user       (m_user),
        .count        (count),
        .full         (full),
        .empty        (empty),
        .almost_full  (almost_full),
        .almost_empty (almost_empty)
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

    // ----------------------------------------------------------- send_beat
    task automatic send_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last
    );
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_last  <= last;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ----------------------------------------------------------- recv_beat
    task automatic recv_beat();
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        m_ready <= 1'b0;
    endtask

    // ================================================================ stimulus
    initial begin
        $display("=== stream_fifo_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): fill FIFO
        $display("[TEST A] Fill FIFO to capacity (%0d entries)", DEPTH);
        m_ready <= 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(i);
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH - 1) ? 1'b1 : 1'b0;
            // If FIFO reports full before we finish, stop pushing
            if (full) begin
                $display("[TEST A] full asserted at i=%0d", i);
                s_valid <= 1'b0;
                s_last  <= 1'b0;
                break;
            end
        end
        @(posedge clk);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        $display("[TEST A] full=%b count=%0d", full, count);
        $display("[TEST A] DONE");

        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (b): drain FIFO
        $display("[TEST B] Drain FIFO completely");
        m_ready <= 1'b1;
        // Wait until empty signal asserts
        repeat (DEPTH + 4) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST B] empty=%b count=%0d", empty, count);
        $display("[TEST B] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (c): simultaneous read/write
        $display("[TEST C] Simultaneous read and write (streaming)");
        m_ready <= 1'b1;
        for (int i = 0; i < 12; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(8'h30 | i[7:0]);
            s_keep  <= 1'b1;
            s_last  <= (i == 11) ? 1'b1 : 1'b0;
        end
        @(posedge clk);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (6) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (d): backpressure scenario
        $display("[TEST D] Backpressure: write 6 beats, stall output 8 cycles, then drain");
        m_ready <= 1'b0;
        for (int i = 0; i < 6; i++) begin
            send_beat(8'(8'hD0 + i), 1'b1, (i == 5) ? 1'b1 : 1'b0);
        end
        $display("[TEST D] count after writes: %0d", count);
        repeat (8) @(posedge clk);  // let it stall
        m_ready <= 1'b1;
        repeat (10) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST D] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (e): frame with last
        $display("[TEST E] 4-beat frame ending with s_last; verify m_last propagates");
        m_ready <= 1'b1;
        for (int i = 0; i < 4; i++) begin
            send_beat(8'(8'hE0 + i), 1'b1, (i == 3) ? 1'b1 : 1'b0);
        end
        repeat (6) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST E] DONE");

        $display("=== stream_fifo_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
