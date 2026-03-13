`timescale 1ns/1ps
`default_nettype none

module stream_mailbox_tb;

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

    // --------------------------------------------------------------- DUT
    stream_mailbox #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (s_valid),
        .s_ready (s_ready),
        .s_data  (s_data),
        .s_keep  (s_keep),
        .s_last  (s_last),
        .s_user  (s_user),
        .m_valid (m_valid),
        .m_ready (m_ready),
        .m_data  (m_data),
        .m_keep  (m_keep),
        .m_last  (m_last),
        .m_user  (m_user)
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
        $display("=== stream_mailbox_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): write then read
        $display("[TEST A] Write then read (mailbox basic flow)");
        // Write one entry; keep m_ready low so it stays stored
        m_ready <= 1'b0;
        send_beat(8'hAA, 1'b1, 1'b0);
        repeat (2) @(posedge clk);
        $display("[TEST A] m_valid after write (should be 1): %b", m_valid);
        // Now read
        recv_beat();
        repeat (2) @(posedge clk);
        $display("[TEST A] m_valid after read (should be 0): %b", m_valid);
        $display("[TEST A] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (b): try write when full
        $display("[TEST B] Write when mailbox is full (s_ready should deassert)");
        m_ready <= 1'b0;
        // Fill the single storage slot
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hBB;
        s_keep  <= 1'b1;
        s_last  <= 1'b0;
        // Wait for acceptance into slot
        do @(posedge clk); while (!s_ready);
        // Now attempt a second write while downstream is not consuming
        s_data  <= 8'hBC;
        // Observe that s_ready has deasserted (mailbox full)
        repeat (4) @(posedge clk);
        $display("[TEST B] s_ready when full (should be 0): %b", s_ready);
        s_valid <= 1'b0;
        // Drain to restore state
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST B] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (c): write with last
        $display("[TEST C] Write beat with s_last=1 and verify m_last propagates");
        m_ready <= 1'b1;
        send_beat(8'hCC, 1'b1, 1'b1);
        repeat (4) @(posedge clk);
        $display("[TEST C] m_last seen (expect 1 before drain): %b", m_last);
        m_ready <= 1'b0;
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (d): reset
        $display("[TEST D] Reset clears mailbox state");
        m_ready <= 1'b0;
        // Write something
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hDD;
        s_keep  <= 1'b1;
        s_last  <= 1'b0;
        @(posedge clk);
        // Mid-transfer reset
        rst_n   <= 1'b0;
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        $display("[TEST D] m_valid after reset (should be 0): %b", m_valid);
        $display("[TEST D] DONE");

        $display("=== stream_mailbox_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
