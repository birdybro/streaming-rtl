// =============================================================================
// Module:      stream_fifo
// Description: A synchronous FIFO with AXI-Stream compatible interfaces.
//              Uses a circular buffer with binary write and read pointers.
//              The read data path is registered (one cycle read latency).
//              Provides occupancy count, full/empty, almost_full/almost_empty
//              flags for external flow control and monitoring.
//
//              DEPTH must be a power of 2 to allow natural pointer wrap-around
//              using truncated addition. The count output is ($clog2(DEPTH)+1)
//              bits wide to represent values 0 through DEPTH inclusive.
//
// Parameters:
//   DATA_WIDTH   - Width of data payload in bits         (default: 8)
//   DEPTH        - Number of FIFO entries; power of 2    (default: 16)
//   USER_WIDTH   - Width of sideband user signal         (default: 1)
//   KEEP_WIDTH   - Number of byte-enable keep bits       (default: DATA_WIDTH/8)
//
// Ports:
//   clk          - Clock
//   rst_n        - Active-low synchronous reset
//   s_valid      - Upstream valid
//   s_ready      - Upstream ready (deasserts when FIFO full)
//   s_data       - Upstream data
//   s_keep       - Upstream byte enables
//   s_last       - Upstream packet end indicator
//   s_user       - Upstream sideband data
//   m_valid      - Downstream valid (asserted when output register valid)
//   m_ready      - Downstream ready
//   m_data       - Downstream data (registered)
//   m_keep       - Downstream byte enables (registered)
//   m_last       - Downstream packet end (registered)
//   m_user       - Downstream sideband data (registered)
//   count        - Current FIFO occupancy (does not include output register)
//   full         - Asserted when FIFO is full (s_ready deasserts)
//   empty        - Asserted when FIFO and output register are both empty
//   almost_full  - Asserted when occupancy >= DEPTH-1
//   almost_empty - Asserted when occupancy <= 1
//
// Latency:       1 cycle (registered read port)
// Throughput:    1 transfer/cycle (full throughput)
// Backpressure:  s_ready deasserts when FIFO is full
// Limitations:   Single-clock domain; DEPTH must be power of 2 >= 2
// =============================================================================

module stream_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // Upstream (slave) interface
    input  logic                        s_valid,
    output logic                        s_ready,
    input  logic [DATA_WIDTH-1:0]       s_data,
    input  logic [KEEP_WIDTH-1:0]       s_keep,
    input  logic                        s_last,
    input  logic [USER_WIDTH-1:0]       s_user,

    // Downstream (master) interface
    output logic                        m_valid,
    input  logic                        m_ready,
    output logic [DATA_WIDTH-1:0]       m_data,
    output logic [KEEP_WIDTH-1:0]       m_keep,
    output logic                        m_last,
    output logic [USER_WIDTH-1:0]       m_user,

    // Status
    output logic [$clog2(DEPTH):0]      count,
    output logic                        full,
    output logic                        empty,
    output logic                        almost_full,
    output logic                        almost_empty
);

    // -------------------------------------------------------------------------
    // Parameter validation (simulation only)
    // -------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "stream_fifo: DEPTH must be a power of 2 >= 2, got %0d", DEPTH);
        end
    end
    // synthesis translate_on

    localparam int ADDR_W  = $clog2(DEPTH);
    localparam int ENTRY_W = DATA_WIDTH + KEEP_WIDTH + 1 + USER_WIDTH;
    localparam logic [ADDR_W:0] DEPTH_W  = DEPTH[ADDR_W:0];
    localparam logic [ADDR_W:0] DEPTH_M1 = DEPTH[ADDR_W:0] - 1'b1;

    // -------------------------------------------------------------------------
    // Memory array
    // -------------------------------------------------------------------------
    logic [ENTRY_W-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Write / read pointers and occupancy
    // -------------------------------------------------------------------------
    logic [ADDR_W-1:0]  wr_ptr;
    logic [ADDR_W-1:0]  rd_ptr;
    logic [ADDR_W:0]    fifo_count;

    logic fifo_full;
    logic fifo_empty;

    assign fifo_full  = (fifo_count == DEPTH_W);
    assign fifo_empty = (fifo_count == '0);

    // -------------------------------------------------------------------------
    // Registered output stage
    // -------------------------------------------------------------------------
    logic                  out_valid;
    logic [DATA_WIDTH-1:0] out_data;
    logic [KEEP_WIDTH-1:0] out_keep;
    logic                  out_last;
    logic [USER_WIDTH-1:0] out_user;

    // Read from FIFO when output stage is free to accept
    logic fifo_rd;
    assign fifo_rd = ~fifo_empty & (~out_valid | m_ready);

    // Write to FIFO when not full
    logic fifo_wr;
    assign fifo_wr = s_valid & ~fifo_full;

    // -------------------------------------------------------------------------
    // Write pointer and memory write
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (fifo_wr) begin
            mem[wr_ptr] <= {s_data, s_keep, s_last, s_user};
            wr_ptr      <= wr_ptr + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Read pointer and output register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr    <= '0;
            out_valid <= 1'b0;
            out_data  <= '0;
            out_keep  <= '0;
            out_last  <= 1'b0;
            out_user  <= '0;
        end else begin
            if (fifo_rd) begin
                rd_ptr    <= rd_ptr + 1'b1;
                out_valid <= 1'b1;
                {out_data, out_keep, out_last, out_user} <= mem[rd_ptr];
            end else if (m_ready && out_valid) begin
                out_valid <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Occupancy counter
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fifo_count <= '0;
        end else begin
            unique case ({fifo_wr, fifo_rd})
                2'b10:   fifo_count <= fifo_count + 1'b1;
                2'b01:   fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Output and status assignments
    // -------------------------------------------------------------------------
    assign s_ready      = ~fifo_full;
    assign full         = fifo_full;
    assign empty        = fifo_empty & ~out_valid;
    assign almost_full  = (fifo_count >= DEPTH_M1);
    assign almost_empty = (fifo_count <= 1'b1);
    assign count        = fifo_count;

    assign m_valid = out_valid;
    assign m_data  = out_data;
    assign m_keep  = out_keep;
    assign m_last  = out_last;
    assign m_user  = out_user;

endmodule
