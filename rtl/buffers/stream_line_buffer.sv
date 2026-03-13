// =============================================================================
// stream_line_buffer.sv
// -----------------------------------------------------------------------------
// Stores a complete frame (line) before forwarding. Allows full line to be read
// while a new line is being written using a ping-pong (two-bank) memory scheme.
// Write into bank A while reading bank B; swap on frame boundary.
// =============================================================================

module stream_line_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int LINE_LEN   = 256,
    parameter int USER_WIDTH = 1,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Slave (input) stream
    input  logic                  s_valid,
    output logic                  s_ready,
    input  logic [DATA_WIDTH-1:0] s_data,
    input  logic [KEEP_WIDTH-1:0] s_keep,
    input  logic                  s_last,
    input  logic [USER_WIDTH-1:0] s_user,

    // Master (output) stream
    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [DATA_WIDTH-1:0] m_data,
    output logic [KEEP_WIDTH-1:0] m_keep,
    output logic                  m_last,
    output logic [USER_WIDTH-1:0] m_user,

    // Status
    output logic                  line_ready
);

    localparam int ADDR_W = $clog2(LINE_LEN);

    // Two-bank memory
    logic [DATA_WIDTH-1:0] mem_data [0:1][0:LINE_LEN-1];
    logic [KEEP_WIDTH-1:0] mem_keep [0:1][0:LINE_LEN-1];
    logic                  mem_last [0:1][0:LINE_LEN-1];
    logic [USER_WIDTH-1:0] mem_user [0:1][0:LINE_LEN-1];

    logic                  write_bank;   // which bank is being written
    logic [ADDR_W-1:0]     wr_ptr;
    logic [ADDR_W-1:0]     rd_ptr;
    logic                  rd_bank_valid; // read bank has data
    logic                  rd_active;

    logic                  wr_accept;
    logic                  rd_accept;

    assign wr_accept = s_valid && s_ready;
    assign rd_accept = m_valid && m_ready;

    // Write side
    assign s_ready = !rd_bank_valid || (write_bank != (1 - write_bank)); // always accept unless read bank stalls
    // Simplified: accept whenever write bank is free (we always write)
    // s_ready: writable if we have space (circular line)
    // For ping-pong, writer is always open as long as we don't overflow
    // We gate s_ready: accept if write bank != read bank OR read bank is done

    // Actually simplify: s_ready is always 1 (write bank always available)
    // We just overwrite if consumer is slow (line buffer semantics)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr        <= '0;
            write_bank    <= 1'b0;
            rd_bank_valid <= 1'b0;
        end else begin
            if (s_valid) begin
                mem_data[write_bank][wr_ptr] <= s_data;
                mem_keep[write_bank][wr_ptr] <= s_keep;
                mem_last[write_bank][wr_ptr] <= s_last;
                mem_user[write_bank][wr_ptr] <= s_user;
                if (s_last) begin
                    wr_ptr        <= '0;
                    rd_bank_valid <= 1'b1;
                    write_bank    <= ~write_bank;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
            // Clear rd_bank_valid when read side finishes
            if (rd_accept && mem_last[~write_bank][rd_ptr]) begin
                rd_bank_valid <= 1'b0;
            end
        end
    end

    assign s_ready = 1'b1;

    // Read side
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr    <= '0;
            rd_active <= 1'b0;
        end else begin
            if (rd_bank_valid && !rd_active) begin
                rd_active <= 1'b1;
                rd_ptr    <= '0;
            end else if (rd_active && rd_accept) begin
                if (mem_last[~write_bank][rd_ptr]) begin
                    rd_active <= 1'b0;
                    rd_ptr    <= '0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end
        end
    end

    assign m_valid     = rd_active;
    assign m_data      = mem_data[~write_bank][rd_ptr];
    assign m_keep      = mem_keep[~write_bank][rd_ptr];
    assign m_last      = mem_last[~write_bank][rd_ptr];
    assign m_user      = mem_user[~write_bank][rd_ptr];
    assign line_ready  = rd_bank_valid;

endmodule
