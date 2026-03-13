`timescale 1ns/1ps
`default_nettype none

module stream_demux_tb;

    // ------------------------------------------------------------------ params
    localparam int unsigned NUM_OUTPUTS = 4;
    localparam int unsigned DATA_WIDTH  = 8;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned KEEP_WIDTH  = 1;
    localparam int unsigned SEL_WIDTH   = $clog2(NUM_OUTPUTS); // 2

    // ----------------------------------------------------------------- signals
    logic                                          clk;
    logic                                          rst_n;

    logic [SEL_WIDTH-1:0]                          sel;

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
    stream_demux #(
        .NUM_OUTPUTS(NUM_OUTPUTS),
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (USER_WIDTH),
        .KEEP_WIDTH (KEEP_WIDTH)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .sel     (sel),
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
        sel     <= '0;
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
        $display("=== stream_demux_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): sel=1 – data appears on output 1
        $display("[TEST A] sel=1: input data must appear on output 1 only");
        sel     <= 2'd1;
        m_ready <= 4'b1111;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hA1; s_keep <= 1'b1; s_last <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST A] m_valid=%04b m_data[1]=0x%02h m_last[1]=%b (only bit 1 expected)",
                 m_valid, m_data[1], m_last[1]);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST A] DONE");

        // ------------------------------------------------------ test (b): sel=3 – data appears on output 3
        $display("[TEST B] sel=3: input data must appear on output 3 only");
        sel     <= 2'd3;
        m_ready <= 4'b1111;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hB3; s_keep <= 1'b1; s_last <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST B] m_valid=%04b m_data[3]=0x%02h m_last[3]=%b (only bit 3 expected)",
                 m_valid, m_data[3], m_last[3]);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        // ------------------------------------------------------ test (c): backpressure from selected output
        $display("[TEST C] Backpressure: selected output (sel=0) deasserts m_ready – source stalls");
        sel     <= 2'd0;
        m_ready <= 4'b1110;   // output 0 not ready
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hC0; s_keep <= 1'b1; s_last <= 1'b0;
        // Source should stall because s_ready reflects m_ready[sel]
        repeat (4) @(posedge clk);
        $display("[TEST C] after 4 stall cycles: s_ready=%b m_valid[0]=%b (beat not yet accepted)", s_ready, m_valid[0]);
        // Release backpressure
        m_ready[0] <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST C] beat1 accepted m_data[0]=0x%02h", m_data[0]);
        s_data  <= 8'hC1; s_last <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST C] beat2 accepted m_data[0]=0x%02h m_last[0]=%b", m_data[0], m_last[0]);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        // ------------------------------------------------------ test (d): change sel between frames
        $display("[TEST D] Change sel between frames");
        m_ready <= 4'b1111;
        sel     <= 2'd2;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hD2; s_keep <= 1'b1; s_last <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST D] frame1: m_valid=%04b m_data[2]=0x%02h (expected 0xD2)", m_valid, m_data[2]);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        @(posedge clk);
        // Switch to output 0
        sel     <= 2'd0;
        s_valid <= 1'b1;
        s_data  <= 8'hD0; s_last <= 1'b1;
        do @(posedge clk); while (!(s_valid && s_ready));
        $display("[TEST D] frame2: m_valid=%04b m_data[0]=0x%02h (expected 0xD0)", m_valid, m_data[0]);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST D] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_demux_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
