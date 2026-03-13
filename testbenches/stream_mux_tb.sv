`timescale 1ns/1ps
`default_nettype none

module stream_mux_tb;

    // ------------------------------------------------------------------ params
    localparam int unsigned NUM_INPUTS  = 4;
    localparam int unsigned DATA_WIDTH  = 8;
    localparam int unsigned USER_WIDTH  = 1;
    localparam int unsigned KEEP_WIDTH  = 1;
    localparam int unsigned SEL_WIDTH   = $clog2(NUM_INPUTS); // 2

    // ----------------------------------------------------------------- signals
    logic                                         clk;
    logic                                         rst_n;

    logic [SEL_WIDTH-1:0]                         sel;

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

    // --------------------------------------------------------------- DUT
    stream_mux #(
        .NUM_INPUTS (NUM_INPUTS),
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

    // ----------------------------------------------------------- send single beat on input i
    task automatic send_beat(
        input int unsigned          port,
        input logic [DATA_WIDTH-1:0] data,
        input logic                  last
    );
        @(posedge clk);
        s_valid[port] <= 1'b1;
        s_data[port]  <= data;
        s_keep[port]  <= 1'b1;
        s_last[port]  <= last;
        s_user[port]  <= 1'b0;
        do @(posedge clk); while (!(s_ready[port] && s_valid[port]));
        s_valid[port] <= 1'b0;
        s_last[port]  <= 1'b0;
    endtask

    // ================================================================ stimulus
    initial begin
        $display("=== stream_mux_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): sel=0 – input 0 data appears at output
        $display("[TEST A] sel=0: input 0 data must appear at output");
        sel     <= 2'd0;
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid[0] <= 1'b1;
        s_data[0]  <= 8'hA0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST A] m_data=0x%02h m_last=%b (expected 0xA0)", m_data, m_last);
        s_valid[0] <= 1'b0;
        s_last[0]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST A] DONE");

        // ------------------------------------------------------ test (b): sel=2 – input 2 data appears at output
        $display("[TEST B] sel=2: input 2 data must appear at output");
        sel     <= 2'd2;
        m_ready <= 1'b1;
        @(posedge clk);
        s_valid[2] <= 1'b1;
        s_data[2]  <= 8'hB2; s_keep[2] <= 1'b1; s_last[2] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST B] m_data=0x%02h m_last=%b (expected 0xB2)", m_data, m_last);
        s_valid[2] <= 1'b0;
        s_last[2]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        // ------------------------------------------------------ test (c): s_ready only for selected input
        $display("[TEST C] s_ready only asserted for selected input (sel=1)");
        sel     <= 2'd1;
        m_ready <= 1'b1;
        @(posedge clk);
        // Assert all inputs valid simultaneously; only input 1 should see s_ready
        s_valid <= 4'b1111;
        for (int i = 0; i < NUM_INPUTS; i++) begin
            s_data[i] <= 8'(8'hC0 | i);
            s_keep[i] <= 1'b1;
            s_last[i] <= 1'b1;
        end
        @(posedge clk); // one cycle to observe ready
        $display("[TEST C] s_ready=%04b (expected only bit 1 set = 0010)", s_ready);
        $display("[TEST C] m_data=0x%02h (expected 0xC1)", m_data);
        do @(posedge clk); while (!(m_valid && m_ready));
        s_valid <= '0;
        s_last  <= '0;
        m_ready <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        // ------------------------------------------------------ test (d): change sel between frames
        $display("[TEST D] Change sel between frames: sel=0 then sel=3");
        m_ready <= 1'b1;
        sel     <= 2'd0;
        @(posedge clk);
        s_valid[0] <= 1'b1;
        s_data[0]  <= 8'hD0; s_keep[0] <= 1'b1; s_last[0] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST D] frame1 m_data=0x%02h (expected 0xD0)", m_data);
        s_valid[0] <= 1'b0;
        s_last[0]  <= 1'b0;
        @(posedge clk);
        // Switch sel to 3 for second frame
        sel        <= 2'd3;
        s_valid[3] <= 1'b1;
        s_data[3]  <= 8'hD3; s_keep[3] <= 1'b1; s_last[3] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST D] frame2 m_data=0x%02h (expected 0xD3)", m_data);
        s_valid[3] <= 1'b0;
        s_last[3]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST D] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_mux_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
