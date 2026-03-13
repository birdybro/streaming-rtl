`timescale 1ns/1ps
`default_nettype none

module stream_header_inserter_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH   = 8;
    localparam int HEADER_BEATS = 2;
    localparam int USER_WIDTH   = 1;
    localparam int KEEP_WIDTH   = 1;
    // Header bus width = HEADER_BEATS * DATA_WIDTH
    localparam int HDR_W        = HEADER_BEATS * DATA_WIDTH;  // 16

    // ----------------------------------------------------------------- signals
    logic                  clk;
    logic                  rst_n;

    logic                  s_valid;
    logic                  s_ready;
    logic [DATA_WIDTH-1:0] s_data;
    logic [KEEP_WIDTH-1:0] s_keep;
    logic                  s_last;
    logic [USER_WIDTH-1:0] s_user;

    // header sideband
    logic                  hdr_valid;
    logic                  hdr_ready;
    logic [HDR_W-1:0]      hdr_data;   // [15:0]

    logic                  m_valid;
    logic                  m_ready;
    logic [DATA_WIDTH-1:0] m_data;
    logic [KEEP_WIDTH-1:0] m_keep;
    logic                  m_last;
    logic [USER_WIDTH-1:0] m_user;

    // --------------------------------------------------------------- DUT
    stream_header_inserter #(
        .DATA_WIDTH  (DATA_WIDTH),
        .HEADER_BEATS(HEADER_BEATS),
        .USER_WIDTH  (USER_WIDTH),
        .KEEP_WIDTH  (KEEP_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .s_valid  (s_valid),
        .s_ready  (s_ready),
        .s_data   (s_data),
        .s_keep   (s_keep),
        .s_last   (s_last),
        .s_user   (s_user),
        .hdr_valid(hdr_valid),
        .hdr_ready(hdr_ready),
        .hdr_data (hdr_data),
        .m_valid  (m_valid),
        .m_ready  (m_ready),
        .m_data   (m_data),
        .m_keep   (m_keep),
        .m_last   (m_last),
        .m_user   (m_user)
    );

    // ------------------------------------------------------------ clock gen
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------- apply_reset
    task automatic apply_reset();
        rst_n     <= 1'b0;
        s_valid   <= 1'b0;
        s_data    <= '0;
        s_keep    <= '1;
        s_last    <= 1'b0;
        s_user    <= '0;
        hdr_valid <= 1'b0;
        hdr_data  <= '0;
        m_ready   <= 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ----------------------------------------------------------- send_header
    task automatic send_header(input logic [HDR_W-1:0] data);
        @(posedge clk);
        hdr_valid <= 1'b1;
        hdr_data  <= data;
        do @(posedge clk); while (!hdr_ready);
        hdr_valid <= 1'b0;
    endtask

    // ----------------------------------------------------------- send_beat
    task automatic send_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last,
        input logic [USER_WIDTH-1:0] user
    );
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= keep;
        s_last  <= last;
        s_user  <= user;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ----------------------------------------------------------- recv_beat
    logic [DATA_WIDTH-1:0] r_data;
    logic [KEEP_WIDTH-1:0] r_keep;
    logic                  r_last;
    logic [USER_WIDTH-1:0] r_user;

    task automatic recv_beat();
        m_ready <= 1'b1;
        do @(posedge clk); while (!m_valid);
        r_data = m_data;
        r_keep = m_keep;
        r_last = m_last;
        r_user = m_user;
    endtask

    // ================================================================ stimulus
    // Total output beats per frame = HEADER_BEATS + payload beats
    localparam int PAYLOAD_BEATS = 4;
    localparam int TOTAL_BEATS   = HEADER_BEATS + PAYLOAD_BEATS;

    int err_count;

    initial begin
        $display("=== stream_header_inserter_tb START ===");
        err_count = 0;
        apply_reset();

        // ------------------------------------------------------ test (a)
        $display("[TEST A] Provide header then payload frame");
        $display("  expected output: %0d header beat(s) then %0d payload beat(s)",
                 HEADER_BEATS, PAYLOAD_BEATS);
        fork
            begin
                // Supply header first, then payload
                send_header(16'hAABB);
                for (int i = 0; i < PAYLOAD_BEATS; i++)
                    send_beat(8'(8'hA0 + i), 1'b1, (i == PAYLOAD_BEATS-1) ? 1'b1 : 1'b0,
                              1'b0);
            end
            begin
                for (int i = 0; i < TOTAL_BEATS; i++) begin
                    recv_beat();
                    $display("  out beat %0d  data=0x%02h  last=%0b", i, r_data, r_last);
                    if (i == TOTAL_BEATS-1 && !r_last) begin
                        $display("  ERROR: m_last missing on final beat"); err_count++;
                    end
                    if (i < TOTAL_BEATS-1 && r_last) begin
                        $display("  ERROR: spurious m_last at beat %0d", i); err_count++;
                    end
                end
            end
        join
        $display("[TEST A] DONE");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (b)
        $display("[TEST B] Wait for hdr_ready before sending header");
        // Hold off hdr_valid for a few cycles to let DUT settle, then send
        repeat (3) @(posedge clk);
        fork
            begin
                send_header(16'hCCDD);
                for (int i = 0; i < PAYLOAD_BEATS; i++)
                    send_beat(8'(8'hB0 + i), 1'b1, (i == PAYLOAD_BEATS-1) ? 1'b1 : 1'b0,
                              1'b0);
            end
            begin
                for (int i = 0; i < TOTAL_BEATS; i++) begin
                    recv_beat();
                    $display("  out beat %0d  data=0x%02h  last=%0b", i, r_data, r_last);
                end
            end
        join
        $display("[TEST B] DONE  (hdr_ready handshake exercised)");
        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (c)
        $display("[TEST C] 2 frames with different headers");
        for (int f = 0; f < 2; f++) begin
            fork
                begin
                    send_header(f == 0 ? 16'h1234 : 16'h5678);
                    for (int i = 0; i < PAYLOAD_BEATS; i++)
                        send_beat(8'(8'hC0 + 8'h10 * f + i), 1'b1,
                                  (i == PAYLOAD_BEATS-1) ? 1'b1 : 1'b0, 1'b0);
                end
                begin
                    for (int i = 0; i < TOTAL_BEATS; i++) begin
                        recv_beat();
                        $display("  f%0d out beat %0d  data=0x%02h  last=%0b",
                                 f, i, r_data, r_last);
                    end
                end
            join
            @(posedge clk);
        end
        $display("[TEST C] DONE");

        if (err_count == 0)
            $display("=== stream_header_inserter_tb PASSED ===");
        else
            $display("=== stream_header_inserter_tb FAILED (%0d errors) ===", err_count);
        $finish;
    end

endmodule
`default_nettype wire
