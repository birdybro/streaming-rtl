`timescale 1ns/1ps
`default_nettype none

module stream_header_stripper_tb;

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

    logic                  m_valid;
    logic                  m_ready;
    logic [DATA_WIDTH-1:0] m_data;
    logic [KEEP_WIDTH-1:0] m_keep;
    logic                  m_last;
    logic [USER_WIDTH-1:0] m_user;

    // header capture outputs
    logic [HDR_W-1:0]      hdr_data;   // [15:0]
    logic                  hdr_valid;

    // --------------------------------------------------------------- DUT
    stream_header_stripper #(
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
        .m_valid  (m_valid),
        .m_ready  (m_ready),
        .m_data   (m_data),
        .m_keep   (m_keep),
        .m_last   (m_last),
        .m_user   (m_user),
        .hdr_data (hdr_data),
        .hdr_valid(hdr_valid)
    );

    // ------------------------------------------------------------ clock gen
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------- apply_reset
    task automatic apply_reset();
        rst_n   <= 1'b0;
        s_valid <= 1'b0;
        s_data  <= '0;
        s_keep  <= '1;
        s_last  <= 1'b0;
        s_user  <= '0;
        m_ready <= 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
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
    localparam int PAYLOAD_BEATS = 4;
    localparam int FRAME_BEATS   = HEADER_BEATS + PAYLOAD_BEATS;

    // Reference header values used in each test
    localparam logic [HDR_W-1:0] HDR_A = 16'hAABB;
    localparam logic [HDR_W-1:0] HDR_B = 16'h1234;
    localparam logic [HDR_W-1:0] HDR_C = 16'h5678;

    int          err_count;
    logic [HDR_W-1:0] captured_hdr;
    logic             saw_hdr_valid;

    // Send a complete frame: HEADER_BEATS header bytes then PAYLOAD_BEATS payload
    task automatic send_frame(
        input logic [HDR_W-1:0] hdr,
        input logic [DATA_WIDTH-1:0] payload_base
    );
        // Transmit header beats (MSB-first byte order)
        for (int b = HEADER_BEATS - 1; b >= 0; b--)
            send_beat(hdr[b*DATA_WIDTH +: DATA_WIDTH], 1'b1, 1'b0, 1'b0);
        // Transmit payload beats
        for (int i = 0; i < PAYLOAD_BEATS; i++)
            send_beat(8'(payload_base + i), 1'b1,
                      (i == PAYLOAD_BEATS-1) ? 1'b1 : 1'b0, 1'b0);
    endtask

    initial begin
        $display("=== stream_header_stripper_tb START ===");
        err_count = 0;
        apply_reset();

        // ------------------------------------------------------ test (a) & (b) & (c)
        $display("[TEST A/B/C] 2-beat header + 4-beat payload; verify hdr_valid and hdr_data");
        saw_hdr_valid = 1'b0;
        fork
            send_frame(HDR_A, 8'hA0);
            begin
                // Only PAYLOAD_BEATS beats appear on the master port
                for (int i = 0; i < PAYLOAD_BEATS; i++) begin
                    recv_beat();
                    $display("  payload beat %0d  data=0x%02h  last=%0b",
                             i, r_data, r_last);
                    if (i == PAYLOAD_BEATS-1 && !r_last) begin
                        $display("  ERROR: m_last missing on final payload beat");
                        err_count++;
                    end
                end
            end
        join

        // hdr_valid may be a pulse; sample it shortly after the header is accepted
        repeat (2) @(posedge clk);
        captured_hdr  = hdr_data;
        saw_hdr_valid = hdr_valid;
        $display("  hdr_valid=%0b  hdr_data=0x%04h (expected 0x%04h)",
                 saw_hdr_valid, captured_hdr, HDR_A);
        $display("[TEST A] payload output with correct m_last – DONE");
        $display("[TEST B] hdr_valid observed=%0b – DONE", saw_hdr_valid);
        if (captured_hdr !== HDR_A) begin
            $display("  ERROR: hdr_data mismatch – got 0x%04h, want 0x%04h",
                     captured_hdr, HDR_A);
            err_count++;
        end
        $display("[TEST C] hdr_data capture check – DONE");

        repeat (2) @(posedge clk);

        // ------------------------------------------------------ test (d)
        $display("[TEST D] 2 back-to-back frames with different headers");
        for (int f = 0; f < 2; f++) begin
            logic [HDR_W-1:0] exp_hdr;
            exp_hdr = (f == 0) ? HDR_B : HDR_C;
            fork
                send_frame(exp_hdr, 8'(8'hD0 + 8'h10 * f));
                begin
                    for (int i = 0; i < PAYLOAD_BEATS; i++) begin
                        recv_beat();
                        $display("  f%0d payload beat %0d  data=0x%02h  last=%0b",
                                 f, i, r_data, r_last);
                    end
                end
            join
            repeat (2) @(posedge clk);
            $display("  f%0d hdr_data=0x%04h (expected 0x%04h)",
                     f, hdr_data, exp_hdr);
            if (hdr_data !== exp_hdr) begin
                $display("  ERROR: f%0d hdr_data mismatch", f);
                err_count++;
            end
            @(posedge clk);
        end
        $display("[TEST D] DONE");

        if (err_count == 0)
            $display("=== stream_header_stripper_tb PASSED ===");
        else
            $display("=== stream_header_stripper_tb FAILED (%0d errors) ===", err_count);
        $finish;
    end

endmodule
`default_nettype wire
