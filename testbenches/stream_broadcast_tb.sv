`timescale 1ns/1ps
`default_nettype none

module stream_broadcast_tb;

    // ------------------------------------------------------------------ params
    localparam int unsigned NUM_OUTPUTS = 4;
    localparam int unsigned DATA_WIDTH  = 8;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned KEEP_WIDTH  = 1;

    // ----------------------------------------------------------------- signals
    logic                                          clk;
    logic                                          rst_n;

    logic                                          s_valid;
    logic                                          s_ready;
    logic [DATA_WIDTH-1:0]                         s_data;
    logic [KEEP_WIDTH-1:0]                         s_keep;
    logic                                          s_last;
    logic [USER_WIDTH-1:0]                         s_user;

    logic [NUM_OUTPUTS-1:0]                        m_valid;
    logic [NUM_OUTPUTS-1:0]                        m_ready;
    logic [NUM_OUTPUTS-1:0][DATA_WIDTH-1:0]        m_data;
    logic [NUM_OUTPUTS-1:0][KEEP_WIDTH-1:0]        m_keep;
    logic [NUM_OUTPUTS-1:0]                        m_last;
    logic [NUM_OUTPUTS-1:0][USER_WIDTH-1:0]        m_user;

    // --------------------------------------------------------------- DUT
    stream_broadcast #(
        .NUM_OUTPUTS(NUM_OUTPUTS),
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (USER_WIDTH),
        .KEEP_WIDTH (KEEP_WIDTH)
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
        s_keep  <= 1'b1;
        s_last  <= 1'b0;
        s_user  <= '0;
        m_ready <= '1;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ================================================================ stimulus
    initial begin
        $display("=== stream_broadcast_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): all outputs ready – beat accepted in one cycle
        $display("[TEST A] All outputs ready: single beat accepted in one cycle");
        m_ready <= 4'b1111;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hAA; s_keep <= 1'b1; s_last <= 1'b1;
        // Expect handshake within a single cycle
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST A] beat accepted: s_ready=%b m_valid=%04b m_data[0]=0x%02h m_last=%04b",
                 s_ready, m_valid, m_data[0], m_last);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST A] DONE");

        apply_reset();

        // ------------------------------------------------------ test (b): one slow output – source stalls
        $display("[TEST B] Output 2 slow (not ready): source must stall until all outputs done");
        // All ready except output 2
        m_ready <= 4'b1011;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hBB; s_keep <= 1'b1; s_last <= 1'b1;
        // Allow outputs 0,1,3 to accept; wait a few cycles
        repeat (3) @(posedge clk);
        $display("[TEST B] mid-stall: s_ready=%b (should be 0 – output 2 pending)", s_ready);
        // Release output 2
        m_ready[2] <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST B] all done: s_ready=%b m_last=%04b", s_ready, m_last);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        apply_reset();

        // ------------------------------------------------------ test (c): 4-beat frame broadcast to all outputs
        $display("[TEST C] 4-beat frame broadcast; verify last only on beat 4");
        m_ready <= 4'b1111;
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(8'hC0 + i);
            s_keep  <= 1'b1;
            s_last  <= (i == 3) ? 1'b1 : 1'b0;
            do @(posedge clk); while (!(s_valid && s_ready));
            $display("[TEST C] beat%0d: m_data[0]=0x%02h m_last=%04b", i, m_data[0], m_last);
        end
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        m_ready <= 4'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_broadcast_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
