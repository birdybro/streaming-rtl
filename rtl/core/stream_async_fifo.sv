// =============================================================================
// Module:      stream_async_fifo
// Description: An asynchronous (dual-clock domain) FIFO with AXI-Stream
//              compatible interfaces. Uses Gray-coded pointers for safe
//              clock-domain crossing. Write pointer is synchronized into the
//              read clock domain; read pointer is synchronized into the write
//              clock domain using configurable multi-stage synchronizers.
//
//              DEPTH must be a power of 2. Pointer registers are one bit wider
//              than the address (ADDR_W+1 bits) to disambiguate full from empty
//              when all address bits are equal. Gray coding ensures only one bit
//              changes per pointer increment, making synchronization safe.
//
//              The output (master) side has a registered read port; m_valid
//              asserts one cycle after a FIFO entry is consumed into the output
//              register.
//
// Parameters:
//   DATA_WIDTH   - Width of data payload in bits         (default: 8)
//   DEPTH        - Number of FIFO entries; power of 2    (default: 16)
//   SYNC_STAGES  - Number of synchronizer flop stages    (default: 2)
//   USER_WIDTH   - Width of sideband user signal         (default: 1)
//   KEEP_WIDTH   - Number of byte-enable keep bits       (default: DATA_WIDTH/8)
//
// Ports:
//   s_clk        - Write-side (slave) clock
//   s_rst_n      - Write-side active-low synchronous reset
//   s_valid      - Upstream valid
//   s_ready      - Upstream ready (deasserts when write-side sees FIFO full)
//   s_data       - Upstream data
//   s_keep       - Upstream byte enables
//   s_last       - Upstream packet end indicator
//   s_user       - Upstream sideband data
//   m_clk        - Read-side (master) clock
//   m_rst_n      - Read-side active-low synchronous reset
//   m_valid      - Downstream valid (asserted when output register valid)
//   m_ready      - Downstream ready
//   m_data       - Downstream data (registered, m_clk domain)
//   m_keep       - Downstream byte enables (registered)
//   m_last       - Downstream packet end (registered)
//   m_user       - Downstream sideband data (registered)
//
// Latency:       SYNC_STAGES + 1 cycles (pointer crossing) + 1 cycle (output reg)
// Throughput:    1 transfer/cycle on each side (full throughput)
// Backpressure:  s_ready deasserts conservatively (uses synchronized rd_ptr)
// Limitations:   DEPTH must be power of 2 >= 2; SYNC_STAGES >= 2 recommended
// =============================================================================

module stream_async_fifo #(
    parameter int DATA_WIDTH  = 8,
    parameter int DEPTH       = 16,
    parameter int SYNC_STAGES = 2,
    parameter int USER_WIDTH  = 1,
    parameter int KEEP_WIDTH  = DATA_WIDTH / 8
) (
    // Write side
    input  logic                    s_clk,
    input  logic                    s_rst_n,
    input  logic                    s_valid,
    output logic                    s_ready,
    input  logic [DATA_WIDTH-1:0]   s_data,
    input  logic [KEEP_WIDTH-1:0]   s_keep,
    input  logic                    s_last,
    input  logic [USER_WIDTH-1:0]   s_user,

    // Read side
    input  logic                    m_clk,
    input  logic                    m_rst_n,
    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [DATA_WIDTH-1:0]   m_data,
    output logic [KEEP_WIDTH-1:0]   m_keep,
    output logic                    m_last,
    output logic [USER_WIDTH-1:0]   m_user
);

    // -------------------------------------------------------------------------
    // Parameter validation (simulation only)
    // -------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin
            $fatal(1, "stream_async_fifo: DEPTH must be a power of 2 >= 2, got %0d", DEPTH);
        end
        if (SYNC_STAGES < 2) begin
            $fatal(1, "stream_async_fifo: SYNC_STAGES must be >= 2, got %0d", SYNC_STAGES);
        end
    end
    // synthesis translate_on

    localparam int ADDR_W  = $clog2(DEPTH);
    localparam int PTR_W   = ADDR_W + 1;   // extra bit for full/empty detect
    localparam int ENTRY_W = DATA_WIDTH + KEEP_WIDTH + 1 + USER_WIDTH;

    // =========================================================================
    // Shared memory (written in s_clk domain, read in m_clk domain)
    // Inference of a simple dual-port RAM; no reset needed on data content.
    // =========================================================================
    (* ram_style = "block" *)
    logic [ENTRY_W-1:0] mem [0:DEPTH-1];

    // =========================================================================
    // WRITE SIDE (s_clk domain)
    // =========================================================================

    logic [PTR_W-1:0] wr_bin;          // binary write pointer
    logic [PTR_W-1:0] wr_gray;         // Gray-coded write pointer
    logic [PTR_W-1:0] rd_gray_sync_wr; // synchronized read Gray pointer (write domain)
    logic [PTR_W-1:0] rd_bin_wr;       // binary read pointer reconstructed in write domain
    logic             wr_full;

    // Gray encoding: binary to Gray
    function automatic logic [PTR_W-1:0] bin2gray(input logic [PTR_W-1:0] b);
        return b ^ (b >> 1);
    endfunction

    // Gray decoding: Gray to binary
    function automatic logic [PTR_W-1:0] gray2bin(input logic [PTR_W-1:0] g);
        logic [PTR_W-1:0] b;
        b[PTR_W-1] = g[PTR_W-1];
        for (int i = PTR_W-2; i >= 0; i--) begin
            b[i] = b[i+1] ^ g[i];
        end
        return b;
    endfunction

    // Full condition: MSBs differ, remaining bits equal (Gray domain comparison)
    assign wr_full = (wr_gray[PTR_W-1]   != rd_gray_sync_wr[PTR_W-1]) &&
                     (wr_gray[PTR_W-2]   != rd_gray_sync_wr[PTR_W-2]) &&
                     (wr_gray[PTR_W-3:0] == rd_gray_sync_wr[PTR_W-3:0]);

    assign s_ready = ~wr_full;

    // Write pointer advancement
    always_ff @(posedge s_clk) begin
        if (!s_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
        end else if (s_valid & ~wr_full) begin
            mem[wr_bin[ADDR_W-1:0]] <= {s_data, s_keep, s_last, s_user};
            wr_bin                  <= wr_bin + 1'b1;
            wr_gray                 <= bin2gray(wr_bin + 1'b1);
        end
    end

    // =========================================================================
    // READ SIDE (m_clk domain)
    // =========================================================================

    logic [PTR_W-1:0] rd_bin;          // binary read pointer
    logic [PTR_W-1:0] rd_gray;         // Gray-coded read pointer
    logic [PTR_W-1:0] wr_gray_sync_rd; // synchronized write Gray pointer (read domain)
    logic             fifo_empty_rd;

    // Empty condition: write and read pointers are equal in Gray domain
    assign fifo_empty_rd = (rd_gray == wr_gray_sync_rd);

    // =========================================================================
    // 2-flop synchronizers
    // =========================================================================

    // Write pointer → read clock domain
    logic [PTR_W-1:0] wr_gray_sync_pipe [0:SYNC_STAGES-1];

    always_ff @(posedge m_clk) begin
        if (!m_rst_n) begin
            for (int i = 0; i < SYNC_STAGES; i++) begin
                wr_gray_sync_pipe[i] <= '0;
            end
        end else begin
            wr_gray_sync_pipe[0] <= wr_gray;
            for (int i = 1; i < SYNC_STAGES; i++) begin
                wr_gray_sync_pipe[i] <= wr_gray_sync_pipe[i-1];
            end
        end
    end
    assign wr_gray_sync_rd = wr_gray_sync_pipe[SYNC_STAGES-1];

    // Read pointer → write clock domain
    logic [PTR_W-1:0] rd_gray_sync_pipe [0:SYNC_STAGES-1];

    always_ff @(posedge s_clk) begin
        if (!s_rst_n) begin
            for (int i = 0; i < SYNC_STAGES; i++) begin
                rd_gray_sync_pipe[i] <= '0;
            end
        end else begin
            rd_gray_sync_pipe[0] <= rd_gray;
            for (int i = 1; i < SYNC_STAGES; i++) begin
                rd_gray_sync_pipe[i] <= rd_gray_sync_pipe[i-1];
            end
        end
    end
    assign rd_gray_sync_wr = rd_gray_sync_pipe[SYNC_STAGES-1];

    // =========================================================================
    // Read pointer advancement (m_clk domain)
    // =========================================================================

    // Registered output stage
    logic                  out_valid;
    logic [DATA_WIDTH-1:0] out_data;
    logic [KEEP_WIDTH-1:0] out_keep;
    logic                  out_last;
    logic [USER_WIDTH-1:0] out_user;

    // Load output register from FIFO when output is empty or being consumed
    logic fifo_rd;
    assign fifo_rd = ~fifo_empty_rd & (~out_valid | m_ready);

    always_ff @(posedge m_clk) begin
        if (!m_rst_n) begin
            rd_bin    <= '0;
            rd_gray   <= '0;
            out_valid <= 1'b0;
            out_data  <= '0;
            out_keep  <= '0;
            out_last  <= 1'b0;
            out_user  <= '0;
        end else begin
            if (fifo_rd) begin
                {out_data, out_keep, out_last, out_user} <= mem[rd_bin[ADDR_W-1:0]];
                out_valid <= 1'b1;
                rd_bin    <= rd_bin + 1'b1;
                rd_gray   <= bin2gray(rd_bin + 1'b1);
            end else if (m_ready && out_valid) begin
                out_valid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign m_valid = out_valid;
    assign m_data  = out_data;
    assign m_keep  = out_keep;
    assign m_last  = out_last;
    assign m_user  = out_user;

endmodule
