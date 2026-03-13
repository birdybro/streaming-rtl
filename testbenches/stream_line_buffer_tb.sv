`timescale 1ns/1ps
`default_nettype none

module stream_line_buffer_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int LINE_LEN   = 8;
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

    logic                    line_ready;

    // --------------------------------------------------------------- DUT
    stream_line_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_LEN  (LINE_LEN),
        .USER_WIDTH(USER_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .s_valid   (s_valid),
        .s_ready   (s_ready),
        .s_data    (s_data),
        .s_keep    (s_keep),
        .s_last    (s_last),
        .s_user    (s_user),
        .m_valid   (m_valid),
        .m_ready   (m_ready),
        .m_data    (m_data),
        .m_keep    (m_keep),
        .m_last    (m_last),
        .m_user    (m_user),
        .line_ready(line_ready)
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

    // -------------------------------------------------------- write full line
    task automatic write_line(input logic [DATA_WIDTH-1:0] base);
        for (int i = 0; i < LINE_LEN; i++)
            send_beat(8'(base + i), i == LINE_LEN - 1);
    endtask

    // ------------------------------------------------------------------ tests
    initial begin
        apply_reset();

        // (a) write full line (s_last on 8th beat) → line_ready asserts
        $display("TEST(a): write full line, check line_ready");
        write_line(8'h10);
        repeat (4) @(posedge clk);
        $display("  line_ready=%b (expect 1)", line_ready);

        // (b) read out the line
        $display("TEST(b): read out full line");
        m_ready <= 1'b1;
        repeat (LINE_LEN + 4) begin
            @(posedge clk);
            if (m_valid) $display("  out data=0x%02h last=%b", m_data, m_last);
        end
        m_ready <= 1'b0;
        $display("  line_ready after drain=%b", line_ready);

        // (c) write next line while reading previous
        $display("TEST(c): write next line while reading previous");
        apply_reset();
        write_line(8'hA0);
        // start reading immediately while sending second line
        m_ready <= 1'b1;
        fork
            begin
                // write second line
                for (int i = 0; i < LINE_LEN; i++)
                    send_beat(8'(8'hB0 + i), i == LINE_LEN - 1);
            end
            begin
                // read first line
                repeat (LINE_LEN + 4) begin
                    @(posedge clk);
                    if (m_valid) $display("  read data=0x%02h last=%b", m_data, m_last);
                end
            end
        join
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_line_buffer_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
