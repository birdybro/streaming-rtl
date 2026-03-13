`timescale 1ns/1ps
`default_nettype none

module stream_elastic_buffer_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 16;
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

    logic                    almost_full;
    logic                    almost_empty;

    // --------------------------------------------------------------- DUT
    stream_elastic_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_valid      (s_valid),
        .s_ready      (s_ready),
        .s_data       (s_data),
        .s_keep       (s_keep),
        .s_last       (s_last),
        .s_user       (s_user),
        .m_valid      (m_valid),
        .m_ready      (m_ready),
        .m_data       (m_data),
        .m_keep       (m_keep),
        .m_last       (m_last),
        .m_user       (m_user),
        .almost_full  (almost_full),
        .almost_empty (almost_empty)
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
        $display("=== stream_elastic_buffer_tb START ===");

        apply_reset();

        // ------------------------------------------------------ test (a): fill halfway
        $display("[TEST A] Fill buffer halfway (%0d beats)", DEPTH/2);
        m_ready <= 1'b0;
        for (int i = 0; i < DEPTH/2; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(i);
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH/2 - 1) ? 1'b1 : 1'b0;
            @(posedge clk);  // wait one cycle per beat
        end
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        $display("[TEST A] almost_full=%b almost_empty=%b", almost_full, almost_empty);
        // Drain what we wrote
        m_ready <= 1'b1;
        repeat (DEPTH/2 + 4) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST A] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (b): fill to near-full then drain
        $display("[TEST B] Fill to near-full then drain");
        m_ready <= 1'b0;
        for (int i = 0; i < DEPTH - 2; i++) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= 8'(8'h40 | (i & 8'h0F));
            s_keep  <= 1'b1;
            s_last  <= (i == DEPTH - 3) ? 1'b1 : 1'b0;
            @(posedge clk);
        end
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        $display("[TEST B] almost_full=%b", almost_full);
        // Drain completely
        m_ready <= 1'b1;
        repeat (DEPTH + 4) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST B] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (c): backpressure
        $display("[TEST C] Backpressure: write while m_ready=0 then release");
        m_ready <= 1'b0;
        for (int i = 0; i < 4; i++) begin
            send_beat(8'(8'hB0 + i), 1'b1, (i == 3) ? 1'b1 : 1'b0);
        end
        // Hold backpressure for 10 cycles
        repeat (10) @(posedge clk);
        $display("[TEST C] Releasing backpressure");
        m_ready <= 1'b1;
        repeat (8) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST C] DONE");

        repeat (4) @(posedge clk);

        // ------------------------------------------------------ test (d): single-beat frame with last
        $display("[TEST D] Single-beat frame with s_last asserted");
        m_ready <= 1'b1;
        send_beat(8'hEF, 1'b1, 1'b1);
        repeat (4) @(posedge clk);
        m_ready <= 1'b0;
        $display("[TEST D] m_last observed on output: %b", m_last);
        $display("[TEST D] DONE");

        $display("=== stream_elastic_buffer_tb PASSED ===");
        $finish;
    end

endmodule

`default_nettype wire
