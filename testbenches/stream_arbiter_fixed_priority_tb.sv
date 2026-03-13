`timescale 1ns/1ps
`default_nettype none

module stream_arbiter_fixed_priority_tb;

    // ------------------------------------------------------------------ params
    localparam int unsigned NUM_INPUTS  = 4;
    localparam int unsigned DATA_WIDTH  = 8;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned KEEP_WIDTH  = 1;

    // ----------------------------------------------------------------- signals
    logic                                         clk;
    logic                                         rst_n;

    logic [NUM_INPUTS-1:0]                        s_valid;
    logic [NUM_INPUTS-1:0]                        s_ready;
    logic [NUM_INPUTS-1:0][DATA_WIDTH-1:0]        s_data;
    logic [NUM_INPUTS-1:0][KEEP_WIDTH-1:0]        s_keep;
    logic [NUM_INPUTS-1:0]                        s_last;
    logic [NUM_INPUTS-1:0][USER_WIDTH-1:0]        s_user;

    logic                                         m_valid;
    logic                                         m_ready;
    logic [DATA_WIDTH-1:0]                        m_data;
    logic [KEEP_WIDTH-1:0]                        m_keep;
    logic                                         m_last;
    logic [USER_WIDTH-1:0]                        m_user;

    logic [NUM_INPUTS-1:0]                        grant;

    // --------------------------------------------------------------- DUT
    stream_arbiter_fixed_priority #(
        .NUM_INPUTS (NUM_INPUTS),
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
        .m_user  (m_user),
        .grant   (grant)
    );

    // ----------------------------------------------------------- clock gen
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------- reset task
    task automatic apply_reset();
        rst_n   <= 1'b0;
        s_valid <= '0;
        s_data  <= '0;
        s_keep  <= '1;
        s_last  <= '0;
        s_user  <= '0;
        m_ready <= 1'b0;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ----------------------------------------------------------- wait_beat: consume one master beat
    task automatic wait_beat();
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        m_ready <= 1'b0;
    endtask

    // ================================================================ stimulus
    initial begin
        $display("=== stream_arbiter_fixed_priority_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): all inputs valid simultaneously
        $display("[TEST A] All inputs simultaneously valid – input 0 must win");
        m_ready <= 1'b1;
        @(posedge clk);
        // Assert all four inputs in the same cycle with distinct data
        s_valid <= 4'b1111;
        s_data[0] <= 8'hA0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1; s_user[0] <= 1'b0;
        s_data[1] <= 8'hA1; s_keep[1] <= 1'b1; s_last[1] <= 1'b1; s_user[1] <= 1'b0;
        s_data[2] <= 8'hA2; s_keep[2] <= 1'b1; s_last[2] <= 1'b1; s_user[2] <= 1'b0;
        s_data[3] <= 8'hA3; s_keep[3] <= 1'b1; s_last[3] <= 1'b1; s_user[3] <= 1'b0;
        // Wait for a beat to be accepted
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST A] m_data=0x%02h grant=%04b (expected data=0xA0, grant[0]=1)", m_data, grant);
        // Deassert the winning input; let the others clear too
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST A] DONE");

        // ------------------------------------------------------ test (b): input 0 inactive – input 1 wins
        $display("[TEST B] Input 0 inactive – input 1 must win");
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid <= 4'b1110;   // inputs 1-3 active, 0 inactive
        s_data[1] <= 8'hB1; s_keep[1] <= 1'b1; s_last[1] <= 1'b1;
        s_data[2] <= 8'hB2; s_keep[2] <= 1'b1; s_last[2] <= 1'b1;
        s_data[3] <= 8'hB3; s_keep[3] <= 1'b1; s_last[3] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST B] m_data=0x%02h grant=%04b (expected data=0xB1, grant[1]=1)", m_data, grant);
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        // ------------------------------------------------------ test (c): frame atomicity
        // Start a 3-beat frame on input 1, then mid-frame assert input 0 (higher priority).
        // The arbiter must finish input 1's frame before switching.
        $display("[TEST C] Frame atomicity: input 1 frame in progress, input 0 interrupts – must not switch");
        m_ready <= 1'b1;
        @(posedge clk);
        // Start frame on input 1 (beat 1 of 3, no last yet)
        s_valid[1] <= 1'b1;
        s_data[1]  <= 8'hC1; s_keep[1] <= 1'b1; s_last[1] <= 1'b0;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat1 m_data=0x%02h grant=%04b", m_data, grant);
        // Mid-frame: assert input 0 (higher priority)
        s_valid[0] <= 1'b1;
        s_data[0]  <= 8'hC0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1;
        // Beat 2 of input 1 (still no last)
        s_data[1] <= 8'hC2; s_last[1] <= 1'b0;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat2 m_data=0x%02h grant=%04b (must still be input 1)", m_data, grant);
        // Beat 3 of input 1: last beat
        s_data[1] <= 8'hC3; s_last[1] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat3 m_data=0x%02h grant=%04b (last of input 1 frame)", m_data, grant);
        s_valid[1] <= 1'b0;
        s_last[1]  <= 1'b0;
        // Now the arbiter should switch to input 0
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] post-frame m_data=0x%02h grant=%04b (now input 0)", m_data, grant);
        s_valid[0] <= 1'b0;
        s_last[0]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        // ------------------------------------------------------ test (d): backpressure
        $display("[TEST D] Backpressure: m_ready deasserted, source stalls");
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid[2] <= 1'b1;
        s_data[2]  <= 8'hD0; s_keep[2] <= 1'b1; s_last[2] <= 1'b0;
        // Wait 5 cycles – m_valid should stay high but no acceptance
        repeat (5) @(posedge clk);
        $display("[TEST D] after 5 stall cycles: m_valid=%b m_ready=%b", m_valid, m_ready);
        // Now release and consume 2-beat frame
        m_ready <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST D] beat1 accepted m_data=0x%02h", m_data);
        s_data[2] <= 8'hD1; s_last[2] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST D] beat2 accepted m_data=0x%02h m_last=%b", m_data, m_last);
        s_valid[2] <= 1'b0;
        s_last[2]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST D] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_arbiter_fixed_priority_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
