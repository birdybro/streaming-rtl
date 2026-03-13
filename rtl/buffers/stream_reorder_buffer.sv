// =============================================================================
// stream_reorder_buffer.sv
// -----------------------------------------------------------------------------
// Reorder buffer: accepts out-of-order transactions tagged with sequence IDs
// and outputs them in-order. Maintains expected_id counter and only presents
// the entry whose ID matches expected_id on the output port.
// =============================================================================

module stream_reorder_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                       clk,
    input  logic                       rst_n,

    // Slave (input) stream
    input  logic                       s_valid,
    output logic                       s_ready,
    input  logic [DATA_WIDTH-1:0]      s_data,
    input  logic [KEEP_WIDTH-1:0]      s_keep,
    input  logic                       s_last,
    input  logic [USER_WIDTH-1:0]      s_user,
    input  logic [ID_WIDTH-1:0]        s_id,

    // Master (output) stream
    output logic                       m_valid,
    input  logic                       m_ready,
    output logic [DATA_WIDTH-1:0]      m_data,
    output logic [KEEP_WIDTH-1:0]      m_keep,
    output logic                       m_last,
    output logic [USER_WIDTH-1:0]      m_user,

    // Status
    output logic [ID_WIDTH-1:0]        expected_id
);

    localparam int ADDR_W = $clog2(DEPTH);

    // Storage arrays indexed 0..DEPTH-1
    logic [DATA_WIDTH-1:0] buf_data [0:DEPTH-1];
    logic [KEEP_WIDTH-1:0] buf_keep [0:DEPTH-1];
    logic                  buf_last [0:DEPTH-1];
    logic [USER_WIDTH-1:0] buf_user [0:DEPTH-1];
    logic [ID_WIDTH-1:0]   buf_id   [0:DEPTH-1];
    logic                  buf_valid[0:DEPTH-1];

    logic [ID_WIDTH-1:0]   exp_id;
    logic [ADDR_W-1:0]     free_slot;
    logic                  have_free;
    logic [ADDR_W-1:0]     match_slot;
    logic                  have_match;

    assign expected_id = exp_id;

    // Find a free slot for incoming data
    always_comb begin
        free_slot  = '0;
        have_free  = 1'b0;
        for (int i = DEPTH-1; i >= 0; i--) begin
            if (!buf_valid[i]) begin
                free_slot = ADDR_W'(i);
                have_free = 1'b1;
            end
        end
    end

    // Find slot matching expected_id
    always_comb begin
        match_slot  = '0;
        have_match  = 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            if (buf_valid[i] && (buf_id[i] == exp_id)) begin
                match_slot = ADDR_W'(i);
                have_match = 1'b1;
            end
        end
    end

    assign s_ready = have_free;
    assign m_valid = have_match;

    assign m_data = buf_data[match_slot];
    assign m_keep = buf_keep[match_slot];
    assign m_last = buf_last[match_slot];
    assign m_user = buf_user[match_slot];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exp_id <= '0;
            for (int i = 0; i < DEPTH; i++) buf_valid[i] <= 1'b0;
        end else begin
            // Write incoming beat into free slot
            if (s_valid && s_ready) begin
                buf_data [free_slot] <= s_data;
                buf_keep [free_slot] <= s_keep;
                buf_last [free_slot] <= s_last;
                buf_user [free_slot] <= s_user;
                buf_id   [free_slot] <= s_id;
                buf_valid[free_slot] <= 1'b1;
            end
            // Output matching beat
            if (m_valid && m_ready) begin
                buf_valid[match_slot] <= 1'b0;
                exp_id                <= exp_id + 1'b1;
            end
        end
    end

endmodule
