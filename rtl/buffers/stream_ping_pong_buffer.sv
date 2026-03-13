// =============================================================================
// stream_ping_pong_buffer.sv
// =============================================================================
// Description:
//   Ping-pong (double) buffer for streaming data. Writes incoming frames into
//   one RAM bank while the reader drains the other, then swaps roles when the
//   write frame completes. Allows simultaneous, independent read and write at
//   full throughput once both banks are in use.
//
// Parameters:
//   DATA_WIDTH  - Width of each data word in bits (default: 8)
//   DEPTH       - Entries per bank, must be a power of 2 (default: 256)
//   USER_WIDTH  - Width of user sideband signal (default: 1)
//   KEEP_WIDTH  - Number of byte-enable bits (default: DATA_WIDTH/8)
//
// Ports:
//   clk         - Clock
//   rst_n       - Active-low synchronous reset
//   s_valid     - Input stream valid
//   s_ready     - Input stream ready
//   s_data      - Input stream data
//   s_keep      - Input byte enables
//   s_last      - Input end-of-frame
//   s_user      - Input user sideband
//   m_valid     - Output stream valid
//   m_ready     - Output stream ready
//   m_data      - Output stream data
//   m_keep      - Output byte enables
//   m_last      - Output end-of-frame
//   m_user      - Output user sideband
//   swap        - Pulses for one cycle when banks are swapped
//
// Latency:
//   Output begins after the first complete frame has been written (one full
//   frame of latency). Subsequent frames have zero additional latency overlap
//   (write to bank A while reading bank B).
//
// Throughput:
//   Up to 1 beat/cycle on both write and read paths simultaneously.
//
// Backpressure:
//   s_ready de-asserts when the write bank is full.
//   m_valid de-asserts when the read bank is empty.
//
// Limitations:
//   Frame length must not exceed DEPTH beats. Behaviour is undefined if a
//   single frame exceeds DEPTH.
// =============================================================================

module stream_ping_pong_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 256,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Slave (input) port
    input  logic                   s_valid,
    output logic                   s_ready,
    input  logic [DATA_WIDTH-1:0]  s_data,
    input  logic [KEEP_WIDTH-1:0]  s_keep,
    input  logic                   s_last,
    input  logic [USER_WIDTH-1:0]  s_user,

    // Master (output) port
    output logic                   m_valid,
    input  logic                   m_ready,
    output logic [DATA_WIDTH-1:0]  m_data,
    output logic [KEEP_WIDTH-1:0]  m_keep,
    output logic                   m_last,
    output logic [USER_WIDTH-1:0]  m_user,

    // Status
    output logic                   swap
);

    localparam int ADDR_W = $clog2(DEPTH);

    // -------------------------------------------------------------------------
    // Storage: two banks, each DEPTH entries wide
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;
        logic [KEEP_WIDTH-1:0] keep;
        logic                  last;
        logic [USER_WIDTH-1:0] user;
    } entry_t;

    entry_t bank[0:1][0:DEPTH-1];

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    logic                  wr_bank;       // which bank is being written
    logic [ADDR_W-1:0]     wr_ptr;
    logic [ADDR_W:0]       wr_count;      // number of entries in write bank
    logic                  wr_frame_done; // a complete frame has been written

    logic                  rd_bank;       // which bank is being read
    logic [ADDR_W-1:0]     rd_ptr;
    logic [ADDR_W:0]       rd_count;      // remaining entries in read bank
    logic                  rd_bank_valid; // read bank holds valid data

    // -------------------------------------------------------------------------
    // Write path
    // -------------------------------------------------------------------------
    logic wr_en;
    assign wr_en   = s_valid & s_ready;
    assign s_ready = (wr_count < DEPTH[ADDR_W:0]);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr        <= '0;
            wr_count      <= '0;
            wr_frame_done <= 1'b0;
        end else begin
            wr_frame_done <= 1'b0;
            if (wr_en) begin
                bank[wr_bank][wr_ptr] <= '{s_data, s_keep, s_last, s_user};
                wr_ptr                <= wr_ptr + 1'b1;
                wr_count              <= wr_count + 1'b1;
                if (s_last) begin
                    wr_frame_done <= 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read path
    // -------------------------------------------------------------------------
    logic rd_en;
    assign rd_en    = m_valid & m_ready;
    assign m_valid  = rd_bank_valid & (rd_count > '0);
    assign m_data   = bank[rd_bank][rd_ptr].data;
    assign m_keep   = bank[rd_bank][rd_ptr].keep;
    assign m_last   = bank[rd_bank][rd_ptr].last;
    assign m_user   = bank[rd_bank][rd_ptr].user;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr       <= '0;
            rd_count     <= '0;
            rd_bank_valid <= 1'b0;
        end else begin
            if (rd_en) begin
                rd_ptr   <= rd_ptr + 1'b1;
                rd_count <= rd_count - 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Bank swap logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_bank  <= 1'b0;
            rd_bank  <= 1'b1;
            swap     <= 1'b0;
        end else begin
            swap <= 1'b0;
            // Swap when: write frame complete AND read bank is empty (or unused)
            if (wr_frame_done && (!rd_bank_valid || rd_count == '0)) begin
                // Move filled write bank to read side
                wr_bank       <= ~wr_bank;
                rd_bank       <= wr_bank;
                rd_ptr        <= '0;
                rd_count      <= wr_count + (wr_en ? 1'b1 : 1'b0); // wr_count already updated
                rd_bank_valid <= 1'b1;
                wr_ptr        <= '0;
                wr_count      <= '0;
                swap          <= 1'b1;
            end else if (!rd_bank_valid && wr_frame_done) begin
                wr_bank       <= ~wr_bank;
                rd_bank       <= wr_bank;
                rd_ptr        <= '0;
                rd_count      <= wr_count;
                rd_bank_valid <= 1'b1;
                wr_ptr        <= '0;
                wr_count      <= '0;
                swap          <= 1'b1;
            end else if (rd_bank_valid && rd_count == '0) begin
                rd_bank_valid <= 1'b0;
            end
        end
    end

endmodule
