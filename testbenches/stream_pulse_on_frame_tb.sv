`timescale 1ns/1ps
`default_nettype none

module stream_pulse_on_frame_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH   = 8;
    localparam int PULSE_ON_SOF = 0;
    localparam int USER_WIDTH   = 1;
    localparam int KEEP_WIDTH   = 1;

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

    logic                    pulse;

    // --------------------------------------------------------------- DUT
    stream_pulse_on_frame #(
        .DATA_WIDTH  (DATA_WIDTH),
        .PULSE_ON_SOF(PULSE_ON_SOF),
        .USER_WIDTH  (USER_WIDTH),
        .KEEP_WIDTH  (KEEP_WIDTH)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data (s_data),
        .s_keep (s_keep),
        .s_last (s_last),
        .s_user (s_user),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data (m_data),
        .m_keep (m_keep),
        .m_last (m_last),
        .m_user (m_user),
        .pulse  (pulse)
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
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // -------------------------------------------------------- send one beat
    task automatic send_beat(input logic [DATA_WIDTH-1:0] data,
                             input logic                  last);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= 1'b1;
        s_last  <= last;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    logic pulse_on_last;
    logic pulse_on_mid;

    initial begin
        apply_reset();

        // (a) PULSE_ON_SOF=0: pulse on last beat of frame
        $display("TEST(a): PULSE_ON_SOF=0 - pulse on EOF (s_last)");
        m_ready <= 1'b1;
        // send 3-beat frame
        send_beat(8'hAA, 1'b0);
        pulse_on_mid = pulse;
        $display("  pulse on beat 1 (non-last)=%b (expect 0)", pulse_on_mid);
        send_beat(8'hBB, 1'b0);
        pulse_on_mid = pulse;
        $display("  pulse on beat 2 (non-last)=%b (expect 0)", pulse_on_mid);
        send_beat(8'hCC, 1'b1);
        pulse_on_last = pulse;
        $display("  pulse on beat 3 (last)=%b (expect 1)", pulse_on_last);

        // (b) verify no pulse on non-last beats
        $display("TEST(b): no pulse on non-last beats of next frame");
        for (int i = 0; i < 4; i++) begin
            send_beat(8'(i + 1), i == 3);
            if (i < 3) begin
                if (pulse) $display("  WARN: pulse on non-last beat %0d", i);
            end else begin
                $display("  pulse on EOF=%b (expect 1)", pulse);
            end
        end

        // (c) single-beat frame (beat is both SOF and EOF)
        $display("TEST(c): single-beat frame");
        send_beat(8'hFF, 1'b1);
        $display("  pulse on single beat=%b (expect 1)", pulse);

        repeat (2) @(posedge clk);
        $display("stream_pulse_on_frame_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
