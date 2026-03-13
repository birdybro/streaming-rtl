`timescale 1ns/1ps
`default_nettype none

module stream_skid_buffer_tb;

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
    stream_skid_buffer #(
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
        $display("=== stream_skid_buffer_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): single beat
        $display("[TEST A] Single beat");
        m_ready <= 1'b1;
        send_beat(8'h55, 1'b1, 1'b1);
        repeat (3) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST A] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (b): burst of 8 beats
        $display("[TEST B] Burst of 8 beats");
        m_ready <= 1'b1;
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(8'h80 | i[7:0]);
            s_keep  <= 1'b1;
            s_last  <= (i == 7) ? 1'b1 : 1'b0;
        end
        @(posedge clk);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        repeat (4) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST B] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (c): backpressure for 3 cycles
        $display("[TEST C] Backpressure for 3 cycles");
        // Send beat while m_ready is deasserted
        m_ready <= 1'b0;
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= 8'hC1;
        s_keep  <= 1'b1;
        s_last  <= 1'b0;
        repeat (3) @(posedge clk);   // hold back-pressure
        // Push a second beat into the skid slot
        s_data  <= 8'hC2;
        s_last  <= 1'b1;
        @(posedge clk);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        // Release downstream
        m_ready <= 1'b1;
        repeat (6) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (d): alternating valid/ready
        $display("[TEST D] Alternating valid / ready (handshake stress)");
        for (int i = 0; i < 8; i++) begin
            // Set up source beat
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(8'hD0 + i[7:0]);
            s_keep  <= 1'b1;
            s_last  <= (i == 7) ? 1'b1 : 1'b0;
            m_ready <= i[0]; // alternate readiness
            @(posedge clk);
            m_ready <= ~m_ready;
        end
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        m_ready <= 1'b1;
        repeat (6) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST D] DONE");

        $display("=== stream_skid_buffer_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
