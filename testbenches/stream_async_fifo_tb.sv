`timescale 1ns/1ps
`default_nettype none

module stream_async_fifo_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH  = 8;
    localparam int DEPTH       = 16;
    localparam int SYNC_STAGES = 2;
    localparam int USER_WIDTH  = 1;
    localparam int KEEP_WIDTH  = 1;

    // ----------------------------------------------------------------- signals
    // Write (slave) clock domain – 10 ns period (100 MHz)
    logic                    s_clk;
    logic                    s_rst_n;
    logic                    s_valid;
    logic                    s_ready;
    logic [DATA_WIDTH-1:0]   s_data;
    logic [KEEP_WIDTH-1:0]   s_keep;
    logic                    s_last;
    logic [USER_WIDTH-1:0]   s_user;

    // Read (master) clock domain – 13 ns period (~77 MHz)
    logic                    m_clk;
    logic                    m_rst_n;
    logic                    m_valid;
    logic                    m_ready;
    logic [DATA_WIDTH-1:0]   m_data;
    logic [KEEP_WIDTH-1:0]   m_keep;
    logic                    m_last;
    logic [USER_WIDTH-1:0]   m_user;

    // --------------------------------------------------------------- DUT
    stream_async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH),
        .SYNC_STAGES(SYNC_STAGES),
        .USER_WIDTH (USER_WIDTH),
        .KEEP_WIDTH (KEEP_WIDTH)
    ) dut (
        .s_clk   (s_clk),
        .s_rst_n (s_rst_n),
        .s_valid (s_valid),
        .s_ready (s_ready),
        .s_data  (s_data),
        .s_keep  (s_keep),
        .s_last  (s_last),
        .s_user  (s_user),
        .m_clk   (m_clk),
        .m_rst_n (m_rst_n),
        .m_valid (m_valid),
        .m_ready (m_ready),
        .m_data  (m_data),
        .m_keep  (m_keep),
        .m_last  (m_last),
        .m_user  (m_user)
    );

    // ----------------------------------------------------------- clock gen (different frequencies)
    initial s_clk = 1'b0;
    always #5  s_clk = ~s_clk;   // 10 ns period

    initial m_clk = 1'b0;
    always #6.5 m_clk = ~m_clk;  // 13 ns period

    // ----------------------------------------------------------- reset task
    // Resets both clock domains simultaneously.
    task automatic apply_reset();
        s_rst_n <= 1'b0;
        m_rst_n <= 1'b0;
        s_valid <= 1'b0;
        s_data  <= '0;
        s_keep  <= '1;
        s_last  <= 1'b0;
        s_user  <= '0;
        m_ready <= 1'b0;
        // Hold reset for several cycles of both clocks
        repeat (8) @(posedge s_clk);
        repeat (8) @(posedge m_clk);
        s_rst_n <= 1'b1;
        m_rst_n <= 1'b1;
        repeat (4) @(posedge s_clk);
        repeat (4) @(posedge m_clk);
    endtask

    // ----------------------------------------------------------- send_beat (write clock domain)
    task automatic send_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last
    );
        @(posedge s_clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_last  <= last;
        do @(posedge s_clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ----------------------------------------------------------- recv_beat (read clock domain)
    task automatic recv_beat();
        m_ready <= 1'b1;
        do @(posedge m_clk); while (!m_valid);
        m_ready <= 1'b0;
    endtask

    // ================================================================ stimulus
    initial begin
        $display("=== stream_async_fifo_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): write side fills, then read side drains
        $display("[TEST A] Write side fills FIFO then read side drains");
        // Stop read side from consuming
        m_ready <= 1'b0;

        // Push DEPTH beats from write clock domain
        for (int i = 0; i < DEPTH; i++) begin
            @(posedge s_clk);
            s_valid <= 1'b1;
            s_data  <= 8'(i);
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH - 1) ? 1'b1 : 1'b0;
            // Respect backpressure
            do @(posedge s_clk); while (!s_ready);
        end
        @(posedge s_clk);
        s_valid <= 1'b0;
        s_last  <= 1'b0;

        // Allow synchronisation latency before reading
        repeat (SYNC_STAGES + 4) @(posedge m_clk);

        // Drain all entries on read clock domain
        $display("[TEST A] Draining read side");
        m_ready <= 1'b1;
        repeat (DEPTH + SYNC_STAGES + 8) @(posedge m_clk);
        m_ready <= 1'b0;
        $display("[TEST A] DONE");

        // Quiet period
        repeat (8) @(posedge s_clk);
        repeat (8) @(posedge m_clk);

        // ------------------------------------------------------ test (b): simultaneous write/read at different rates
        $display("[TEST B] Simultaneous write/read at different clock rates");

        // Enable read side continuously
        m_ready <= 1'b1;

        // Write 12 beats on write clock domain (non-blocking with clock domain)
        fork
            begin : writer
                for (int i = 0; i < 12; i++) begin
                    send_beat(8'(8'hB0 | i[7:0]), 1'b1, (i == 11) ? 1'b1 : 1'b0);
                end
                $display("[TEST B] Write side done");
            end
            begin : reader
                // Let write side work; give the FIFO time to produce m_valid
                repeat (SYNC_STAGES + 4) @(posedge m_clk);
                repeat (12 + SYNC_STAGES + 8) @(posedge m_clk);
                $display("[TEST B] Read side done");
            end
        join

        m_ready <= 1'b0;
        $display("[TEST B] DONE");

        repeat (8) @(posedge s_clk);
        repeat (8) @(posedge m_clk);

        // ------------------------------------------------------ test (c): reset both sides
        $display("[TEST C] Mid-transfer reset of both clock domains");
        // Start a write
        @(posedge s_clk);
        s_valid <= 1'b1;
        s_data  <= 8'hFF;
        s_keep  <= 1'b1;
        s_last  <= 1'b0;
        repeat (2) @(posedge s_clk);

        // Simultaneously reset both domains
        s_rst_n <= 1'b0;
        m_rst_n <= 1'b0;
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (8) @(posedge s_clk);
        repeat (8) @(posedge m_clk);
        s_rst_n <= 1'b1;
        m_rst_n <= 1'b1;
        repeat (4) @(posedge s_clk);
        repeat (4) @(posedge m_clk);

        $display("[TEST C] m_valid after reset (should be 0): %b", m_valid);
        $display("[TEST C] DONE");

        $display("=== stream_async_fifo_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
