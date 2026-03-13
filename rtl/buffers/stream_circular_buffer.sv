// =============================================================================
// stream_circular_buffer.sv
// -----------------------------------------------------------------------------
// Circular (ring) buffer with head/tail pointers. Supports variable-length
// frames. Uses RAM with wr_ptr/rd_ptr. Exposes fill count, full, and empty.
// =============================================================================

module stream_circular_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 256,  // must be power of 2
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

    // Master (output) stream
    output logic                       m_valid,
    input  logic                       m_ready,
    output logic [DATA_WIDTH-1:0]      m_data,
    output logic [KEEP_WIDTH-1:0]      m_keep,
    output logic                       m_last,
    output logic [USER_WIDTH-1:0]      m_user,

    // Status
    output logic [$clog2(DEPTH):0]     count,
    output logic                       full,
    output logic                       empty
);

    localparam int ADDR_W = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] ram_data [0:DEPTH-1];
    logic [KEEP_WIDTH-1:0] ram_keep [0:DEPTH-1];
    logic                  ram_last [0:DEPTH-1];
    logic [USER_WIDTH-1:0] ram_user [0:DEPTH-1];

    logic [ADDR_W-1:0] wr_ptr;
    logic [ADDR_W-1:0] rd_ptr;
    logic [ADDR_W:0]   fill_cnt; // one extra bit for full/empty distinction

    assign full  = (fill_cnt == DEPTH[ADDR_W:0]);
    assign empty = (fill_cnt == '0);
    assign count = fill_cnt;

    assign s_ready = !full;
    assign m_valid = !empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            fill_cnt <= '0;
        end else begin
            logic wr_en, rd_en;
            wr_en = s_valid && s_ready;
            rd_en = m_valid && m_ready;

            if (wr_en) begin
                ram_data[wr_ptr] <= s_data;
                ram_keep[wr_ptr] <= s_keep;
                ram_last[wr_ptr] <= s_last;
                ram_user[wr_ptr] <= s_user;
                wr_ptr           <= wr_ptr + 1'b1;
            end
            if (rd_en) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({wr_en, rd_en})
                2'b10:   fill_cnt <= fill_cnt + 1'b1;
                2'b01:   fill_cnt <= fill_cnt - 1'b1;
                default: fill_cnt <= fill_cnt;
            endcase
        end
    end

    assign m_data = ram_data[rd_ptr];
    assign m_keep = ram_keep[rd_ptr];
    assign m_last = ram_last[rd_ptr];
    assign m_user = ram_user[rd_ptr];

endmodule
