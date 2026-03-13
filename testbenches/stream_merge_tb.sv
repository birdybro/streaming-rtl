`timescale 1ns/1ps
`default_nettype none

module stream_merge_tb;

    // ------------------------------------------------------------------ params
    localparam int unsigned NUM_INPUTS  = 2;
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

    // --------------------------------------------------------------- DUT
    stream_merge #(
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

    // ----------------------------------------------------------- send a full frame on port p
    task automatic send_frame(
        input int unsigned           port,
        input logic [DATA_WIDTH-1:0] base_data,
        input int unsigned           beats
    );
        for (int b = 0; b < beats; b++) begin
            @(posedge clk);
            s_valid[port] <= 1'b1;
            s_data[port]  <= base_data + DATA_WIDTH'(b);
            s_keep[port]  <= 1'b1;
            s_last[port]  <= (b == beats - 1) ? 1'b1 : 1'b0;
            s_user[port]  <= 1'b0;
            do @(posedge clk); while (!(s_valid[port] && s_ready[port]));
        end
        s_valid[port] <= 1'b0;
        s_last[port]  <= 1'b0;
    endtask

    // ================================================================ stimulus
    initial begin
        $display("=== stream_merge_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): alternate frames from 2 inputs
        $display("[TEST A] Alternate 2-beat frames from inputs 0 and 1");
        m_ready <= 1'b1;
        fork
            // Input 0: frame 1 then frame 2 (after input 1 completes its first frame)
            begin
                send_frame(0, 8'hA0, 2);
                repeat (2) @(posedge clk); // gap between frames
                send_frame(0, 8'hA4, 2);
            end
            // Input 1: frame starts slightly after input 0 finishes
            begin
                repeat (6) @(posedge clk);
                send_frame(1, 8'hB0, 2);
            end
        join
        // Drain any remaining output
        repeat (8) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST A] DONE");

        apply_reset();

        // ------------------------------------------------------ monitor output beats for test (b)
        // We fork a monitor to print each output beat
        $display("[TEST B] One input inactive (only input 0 active)");
        m_ready <= 1'b1;
        s_valid[1] <= 1'b0;   // input 1 stays inactive
        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            s_valid[0] <= 1'b1;
            s_data[0]  <= 8'(8'hC0 + i);
            s_keep[0]  <= 1'b1;
            s_last[0]  <= (i == 2) ? 1'b1 : 1'b0;
            do @(posedge clk); while (!(s_valid[0] && s_ready[0]));
            $display("[TEST B] beat%0d: m_data=0x%02h m_last=%b", i, m_data, m_last);
        end
        s_valid[0] <= 1'b0;
        s_last[0]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST B] DONE");

        apply_reset();

        // ------------------------------------------------------ test (c): backpressure
        $display("[TEST C] Backpressure: m_ready deasserted mid-frame, then released");
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid[0] <= 1'b1;
        s_data[0]  <= 8'hD0; s_keep[0] <= 1'b1; s_last[0] <= 1'b0;
        repeat (4) @(posedge clk);
        $display("[TEST C] stalled: m_valid=%b s_ready[0]=%b (should stall when output not ready)",
                 m_valid, s_ready[0]);
        // Release backpressure and consume the 2-beat frame
        m_ready <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat1 m_data=0x%02h", m_data);
        s_data[0] <= 8'hD1; s_last[0] <= 1'b1;
        do @(posedge clk); while (!(m_valid && m_ready));
        $display("[TEST C] beat2 m_data=0x%02h m_last=%b", m_data, m_last);
        s_valid[0] <= 1'b0;
        s_last[0]  <= 1'b0;
        m_ready    <= 1'b0;
        repeat (2) @(posedge clk);
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);
        $display("=== stream_merge_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
