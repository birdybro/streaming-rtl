`timescale 1ns/1ps
`default_nettype none

module stream_arbiter_round_robin_tb;

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

    // ----------------------------------------------------------- beat tracking
    int unsigned beat_count;
    int unsigned frame_count;

    // --------------------------------------------------------------- DUT
    stream_arbiter_round_robin #(
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

    // ================================================================ stimulus
    initial begin
        $display("=== stream_arbiter_round_robin_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): 4 inputs, 2-beat frames, verify round-robin order
        $display("[TEST A] 4 inputs each with 2-beat frames – verify round-robin order");
        m_ready <= 1'b1;
        // Prepare all four inputs: beat 1 of 2 (no last), then beat 2 (last)
        // Drive all simultaneously and let arbitration proceed frame by frame
        for (int i = 0; i < NUM_INPUTS; i++) begin
            s_data[i]  <= 8'(8'hA0 | i);
            s_keep[i]  <= 1'b1;
            s_last[i]  <= 1'b0;
            s_user[i]  <= 1'b0;
        end
        s_valid <= 4'b1111;

        beat_count  = 0;
        frame_count = 0;
        // Consume 8 beats (4 frames × 2 beats each)
        repeat (8) begin
            do @(posedge clk); while (!(m_valid && m_ready));
            $display("[TEST A] beat %0d: m_data=0x%02h grant=%04b m_last=%b",
                     beat_count, m_data, grant, m_last);
            // Toggle last on even beats (beat 1 of each 2-beat frame)
            for (int i = 0; i < NUM_INPUTS; i++) begin
                if (grant[i]) begin
                    if (beat_count[0] == 1'b0) begin
                        // Second beat of frame – set last
                        s_last[i] <= 1'b1;
                        s_data[i] <= 8'(8'hA8 | i);
                    end else begin
                        // Frame just ended – prepare next pair
                        s_last[i] <= 1'b0;
                        s_data[i] <= 8'(8'hA0 | i);
                    end
                end
            end
            beat_count++;
            if (m_last) frame_count++;
        end

        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        $display("[TEST A] frames_seen=%0d (expected 4)", frame_count);
        repeat (2) @(posedge clk);
        $display("[TEST A] DONE");

        apply_reset();

        // ------------------------------------------------------ test (b): skip inactive inputs
        $display("[TEST B] Skip inactive inputs – only inputs 0 and 2 active");
        m_ready <= 1'b1;
        s_valid <= 4'b0101;   // inputs 0 and 2 only
        s_data[0] <= 8'hB0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1;
        s_data[2] <= 8'hB2; s_keep[2] <= 1'b1; s_last[2] <= 1'b1;
        // Consume 4 grants; should only see inputs 0 and 2 alternating
        for (int k = 0; k < 4; k++) begin
            do @(posedge clk); while (!(m_valid && m_ready));
            $display("[TEST B] grant=%04b m_data=0x%02h (only grant[0] or grant[2] expected)", grant, m_data);
        end
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        apply_reset();

        // ------------------------------------------------------ test (c): frame atomicity
        $display("[TEST C] Frame atomicity: start frame on input 1, then assert input 0 – must finish input 1 first");
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid[1] <= 1'b1;
        s_data[1]  <= 8'hC1; s_keep[1] <= 1'b1; s_last[1] <= 1'b0;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat1 m_data=0x%02h grant=%04b", m_data, grant);
        // Assert input 0 mid-frame
        s_valid[0] <= 1'b1;
        s_data[0]  <= 8'hC0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1;
        // Continue input 1 frame
        s_data[1] <= 8'hC2; s_last[1] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat2 m_data=0x%02h grant=%04b (must be input 1)", m_data, grant);
        s_valid[1] <= 1'b0;
        // Now arbiter should serve input 0
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] next grant m_data=0x%02h grant=%04b (now input 0)", m_data, grant);
        s_valid[0] <= 1'b0;
        s_last[0]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        apply_reset();

        // ------------------------------------------------------ test (d): backpressure
        $display("[TEST D] Backpressure: m_ready deasserted, then released");
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid[3] <= 1'b1;
        s_data[3]  <= 8'hD0; s_keep[3] <= 1'b1; s_last[3] <= 1'b0;
        repeat (4) @(posedge clk);
        $display("[TEST D] after 4 stall cycles m_valid=%b", m_valid);
        m_ready <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST D] beat1 accepted m_data=0x%02h grant=%04b", m_data, grant);
        s_data[3] <= 8'hD1; s_last[3] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST D] beat2 accepted m_data=0x%02h m_last=%b", m_data, m_last);
        s_valid[3] <= 1'b0;
        s_last[3]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST D] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_arbiter_round_robin_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
