`timescale 1ns/1ps
`default_nettype none

module stream_reorder_buffer_tb;

    // ------------------------------------------------------------------ params
    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 16;
    localparam int ID_WIDTH   = 4;
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
    logic [ID_WIDTH-1:0]     s_id;

    logic                    m_valid;
    logic                    m_ready;
    logic [DATA_WIDTH-1:0]   m_data;
    logic [KEEP_WIDTH-1:0]   m_keep;
    logic                    m_last;
    logic [USER_WIDTH-1:0]   m_user;

    logic [ID_WIDTH-1:0]     expected_id;

    // --------------------------------------------------------------- DUT
    stream_reorder_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH),
        .ID_WIDTH  (ID_WIDTH),
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
        .s_id       (s_id),
        .m_valid    (m_valid),
        .m_ready    (m_ready),
        .m_data     (m_data),
        .m_keep     (m_keep),
        .m_last     (m_last),
        .m_user     (m_user),
        .expected_id(expected_id)
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
        s_id    <= '0;
        m_ready <= 1'b0;
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // -------------------------------------------------------- send one beat with ID
    task automatic send_id_beat(input logic [DATA_WIDTH-1:0] data,
                                input logic [ID_WIDTH-1:0]   id,
                                input logic                  last);
        @(posedge clk);
        s_valid <= 1'b1;
        s_data  <= data;
        s_keep  <= 1'b1;
        s_last  <= last;
        s_id    <= id;
        do @(posedge clk); while (!s_ready);
        s_valid <= 1'b0;
        s_last  <= 1'b0;
    endtask

    // ------------------------------------------------------------------ tests
    initial begin
        apply_reset();

        // (a) in-order: IDs 0,1,2,3 → passthrough
        $display("TEST(a): in-order IDs 0-3 passthrough");
        m_ready <= 1'b1;
        send_id_beat(8'hAA, 4'd0, 1'b1);
        send_id_beat(8'hBB, 4'd1, 1'b1);
        send_id_beat(8'hCC, 4'd2, 1'b1);
        send_id_beat(8'hDD, 4'd3, 1'b1);
        repeat (12) begin
            @(posedge clk);
            if (m_valid) $display("  out data=0x%02h last=%b expected_id=%0d",
                                  m_data, m_last, expected_id);
        end

        // (b) out-of-order: send ID 2 then 1 then 0 → output in order 0,1,2
        $display("TEST(b): out-of-order IDs 2,1,0 -> output 0,1,2");
        apply_reset();
        m_ready <= 1'b1;
        send_id_beat(8'hC2, 4'd2, 1'b1);
        send_id_beat(8'hC1, 4'd1, 1'b1);
        send_id_beat(8'hC0, 4'd0, 1'b1);
        repeat (16) begin
            @(posedge clk);
            if (m_valid) $display("  out data=0x%02h last=%b expected_id=%0d",
                                  m_data, m_last, expected_id);
        end

        // (c) verify expected_id counter advances
        $display("TEST(c): expected_id counter");
        apply_reset();
        @(posedge clk);
        $display("  expected_id after reset=%0d (expect 0)", expected_id);
        m_ready <= 1'b1;
        send_id_beat(8'h01, 4'd0, 1'b1);
        @(posedge clk);
        @(posedge clk);
        $display("  expected_id after ID0=%0d (expect 1)", expected_id);
        send_id_beat(8'h02, 4'd1, 1'b1);
        @(posedge clk);
        @(posedge clk);
        $display("  expected_id after ID1=%0d (expect 2)", expected_id);
        m_ready <= 1'b0;

        repeat (2) @(posedge clk);
        $display("stream_reorder_buffer_tb PASSED");
        $finish;
    end

endmodule
`default_nettype wire
