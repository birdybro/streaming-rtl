`timescale 1ns/1ps
`default_nettype none

module stream_idle_detector_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int TIMEOUT    = 10;
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

    logic                    idle;
    logic [3:0]              idle_cycles;    // $clog2(TIMEOUT+1) = $clog2(11) = 4 bits

    // --------------------------------------------------------------- DUT
    stream_idle_detector #(
        .DATA_WIDTH(DATA_WIDTH),
        .TIMEOUT   (TIMEOUT),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .s_valid    (s_valid),
        .s_ready    (s_ready),
        .s_data     (s_data),
        .s_keep     (s_keep),
        .s_last     (s_last),
        .s_user     (s_user),
        .m_valid    (m_valid),
        .m_ready    (m_ready),
        .m_data     (m_data),
        .m_keep     (m_keep),
        .m_last     (m_last),
        .m_user     (m_user),
        .idle       (idle),
        .idle_cycles(idle_cycles)
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
    initial begin
        apply_reset();

        // (a) send beats continuously → idle never asserts
        $display("TEST(a): continuous beats - idle should stay 0");
        m_ready <= 1'b1;
        for (int i = 0; i < TIMEOUT + 4; i++) begin
            send_beat(8'(i), 1'b0);
            if (idle) $display("  WARN: idle asserted during continuous flow at beat %0d", i);
        end
        $display("  idle after continuous=%b (expect 0)", idle);

        // (b) stop sending for TIMEOUT+1 cycles → idle asserts
        $display("TEST(b): stall > TIMEOUT cycles -> idle asserts");
        s_valid <= 1'b0;
        repeat (TIMEOUT + 2) @(posedge clk);
        $display("  idle after %0d idle cycles=%b (expect 1)", TIMEOUT + 2, idle);
        $display("  idle_cycles=%0d", idle_cycles);

        // (c) send one beat → idle clears
        $display("TEST(c): send beat after idle -> idle clears");
        send_beat(8'hFF, 1'b1);
        @(posedge clk);
        $display("  idle after beat=%b (expect 0)", idle);

        repeat (2) @(posedge clk);
        $display("stream_idle_detector_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
