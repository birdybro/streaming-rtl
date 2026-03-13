`timescale 1ns/1ps
`default_nettype none

module stream_join_tb;

    // ------------------------------------------------------------------ params
    localparam int unsigned NUM_INPUTS  = 2;
    localparam int unsigned DATA_WIDTH  = 8;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned KEEP_WIDTH  = 1;
    localparam int unsigned OUT_WIDTH   = NUM_INPUTS * DATA_WIDTH; // 16

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
    logic [OUT_WIDTH-1:0]                         m_data;  // 16-bit concatenated output
    logic [KEEP_WIDTH-1:0]                        m_keep;
    logic                                         m_last;
    logic [USER_WIDTH-1:0]                        m_user;

    // --------------------------------------------------------------- DUT
    stream_join #(
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
        .m_user  (m_user)
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
        $display("=== stream_join_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): both inputs valid simultaneously → output fires
        $display("[TEST A] Both inputs valid simultaneously – output must fire in same cycle");
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid[0] <= 1'b1; s_data[0] <= 8'hA0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1; s_user[0] <= 1'b0;
        s_valid[1] <= 1'b1; s_data[1] <= 8'hA1; s_keep[1] <= 1'b1; s_last[1] <= 1'b1; s_user[1] <= 1'b0;
        do @(posedge clk); while (!(m_valid && m_ready));
        // m_data should be {s_data[1], s_data[0]} = {0xA1, 0xA0} = 0xA1A0
        $display("[TEST A] m_data=0x%04h m_last=%b s_ready=%02b (expected m_data=0xA1A0, m_last=1)",
                 m_data, m_last, s_ready);
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST A] DONE");

        apply_reset();

        // ------------------------------------------------------ test (b): one input delayed – output waits
        $display("[TEST B] Input 1 delayed by 3 cycles – output must wait");
        m_ready <= 1'b1;
        @(posedge clk);
        // Assert input 0 immediately
        s_valid[0] <= 1'b1; s_data[0] <= 8'hB0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1;
        // Input 1 starts 3 cycles later
        repeat (3) @(posedge clk);
        // During the wait, output must not fire
        if (m_valid)
            $display("[TEST B] WARNING: m_valid asserted before both inputs ready!");
        else
            $display("[TEST B] m_valid correctly deasserted while input 1 absent");
        // Now assert input 1
        s_valid[1] <= 1'b1; s_data[1] <= 8'hB1; s_keep[1] <= 1'b1; s_last[1] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST B] m_data=0x%04h m_last=%b (expected m_data=0xB1B0, m_last=1)",
                 m_data, m_last);
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        apply_reset();

        // ------------------------------------------------------ test (c): last synchronization across a 3-beat frame
        // Both inputs present a 3-beat frame simultaneously.
        // m_last must only assert when ALL inputs assert s_last together (beat 3).
        $display("[TEST C] 3-beat frame: m_last must align with both s_last[0] and s_last[1]");
        m_ready <= 1'b1;
        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            s_valid[0] <= 1'b1; s_data[0] <= 8'(8'hC0 + i); s_keep[0] <= 1'b1; s_last[0] <= (i == 2) ? 1'b1 : 1'b0;
            s_valid[1] <= 1'b1; s_data[1] <= 8'(8'hD0 + i); s_keep[1] <= 1'b1; s_last[1] <= (i == 2) ? 1'b1 : 1'b0;
            do @(posedge clk); while (!(m_valid && m_ready));
            $display("[TEST C] beat%0d: m_data=0x%04h m_last=%b (last only on beat 2)", i, m_data, m_last);
        end
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_join_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
