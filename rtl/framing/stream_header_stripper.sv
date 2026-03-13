// =============================================================================
// Module:      stream_header_stripper
// Description: Strips the first HEADER_BEATS beats from each incoming AXI-
//              Stream frame and exposes them on a sideband port.  For each
//              frame the module:
//                1. (S_HDR_CAP) Accepts the first HEADER_BEATS beats from
//                   the slave without forwarding them downstream.  Each beat
//                   is registered into the corresponding slice of hdr_data_reg.
//                   m_valid is deasserted during this phase.
//                2. When the HEADER_BEATS-th header beat is accepted,
//                   hdr_valid pulses for one cycle (registered) and
//                   hdr_data holds the complete captured header.
//                3. (S_PAYLOAD) Transparently passes the remaining payload
//                   beats to the master, including s_last.  On the accepted
//                   s_last beat the module returns to S_HDR_CAP for the next
//                   frame.
//              If s_last fires before HEADER_BEATS beats are received the
//              module returns to S_HDR_CAP; hdr_valid is not asserted for
//              short/truncated frames.
//
// Parameters:
//   DATA_WIDTH    - Width of data payload in bits          (default: 8)
//   HEADER_BEATS  - Number of header beats to strip        (default: 4)
//   USER_WIDTH    - Width of sideband user signal          (default: 1)
//   KEEP_WIDTH    - Number of byte-enable keep bits        (default: DATA_WIDTH/8)
//
// Ports:
//   clk           - Clock
//   rst_n         - Active-low synchronous reset
//   s_valid       - Upstream valid
//   s_ready       - Upstream ready
//   s_data        - Upstream data
//   s_keep        - Upstream byte enables
//   s_last        - Upstream packet end
//   s_user        - Upstream sideband data
//   m_valid       - Downstream valid
//   m_ready       - Downstream ready
//   m_data        - Downstream data (payload only, header stripped)
//   m_keep        - Downstream byte enables
//   m_last        - Downstream packet end
//   m_user        - Downstream sideband data
//   hdr_data      - Captured header (stable after hdr_valid and until EoF)
//   hdr_valid     - Pulses one cycle after full header is captured
//
// Latency:       HEADER_BEATS cycles of payload latency (header absorbed)
// Throughput:    1 transfer/cycle during payload phase; 0 during capture
// Backpressure:  m_ready causes backpressure in payload phase; s_ready is
//                always 1 during header capture
// Limitations:   HEADER_BEATS >= 1; frames shorter than HEADER_BEATS beats
//                will not produce a hdr_valid pulse
// =============================================================================

module stream_header_stripper #(
    parameter int DATA_WIDTH   = 8,
    parameter int HEADER_BEATS = 4,
    parameter int USER_WIDTH   = 1,
    parameter int KEEP_WIDTH   = DATA_WIDTH / 8
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    // Slave interface
    input  logic                                    s_valid,
    output logic                                    s_ready,
    input  logic [DATA_WIDTH-1:0]                   s_data,
    input  logic [KEEP_WIDTH-1:0]                   s_keep,
    input  logic                                    s_last,
    input  logic [USER_WIDTH-1:0]                   s_user,

    // Master interface (payload only; header beats removed)
    output logic                                    m_valid,
    input  logic                                    m_ready,
    output logic [DATA_WIDTH-1:0]                   m_data,
    output logic [KEEP_WIDTH-1:0]                   m_keep,
    output logic                                    m_last,
    output logic [USER_WIDTH-1:0]                   m_user,

    // Header sideband output
    output logic [HEADER_BEATS*DATA_WIDTH-1:0]      hdr_data,
    output logic                                    hdr_valid
);

    // synthesis translate_off
    initial begin
        if (HEADER_BEATS < 1)
            $fatal(1, "stream_header_stripper: HEADER_BEATS must be >= 1, got %0d", HEADER_BEATS);
    end
    // synthesis translate_on

    localparam int HDR_CNT_W = (HEADER_BEATS > 1) ? $clog2(HEADER_BEATS) : 1;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    typedef enum logic {
        S_HDR_CAP = 1'b0,   // capturing header beats (not forwarding)
        S_PAYLOAD = 1'b1    // passing payload beats through
    } state_e;

    state_e state;

    // -------------------------------------------------------------------------
    // Header capture register and beat index
    // -------------------------------------------------------------------------
    logic [HEADER_BEATS*DATA_WIDTH-1:0] hdr_data_reg;
    logic [HDR_CNT_W-1:0]              hdr_beat;

    // -------------------------------------------------------------------------
    // Internal: last-header-beat condition
    // -------------------------------------------------------------------------
    logic last_hdr_beat;
    assign last_hdr_beat = (state == S_HDR_CAP) && s_valid &&
                           (hdr_beat == HDR_CNT_W'(HEADER_BEATS - 1));

    // -------------------------------------------------------------------------
    // State and capture registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_HDR_CAP;
            hdr_beat     <= '0;
            hdr_data_reg <= '0;
            hdr_valid    <= 1'b0;
        end else begin
            // Default: deassert hdr_valid each cycle (it is a 1-cycle pulse)
            hdr_valid <= 1'b0;

            unique case (state)
                // ---------------------------------------------------------
                S_HDR_CAP: begin
                    if (s_valid) begin
                        // Capture this beat into the appropriate register slice
                        hdr_data_reg[hdr_beat * DATA_WIDTH +: DATA_WIDTH] <= s_data;

                        if (last_hdr_beat) begin
                            // Full header received
                            hdr_valid <= 1'b1;
                            hdr_beat  <= '0;
                            if (!s_last)
                                state <= S_PAYLOAD;
                            // else: degenerate frame (header = whole frame);
                            // stay in S_HDR_CAP for next frame; hdr_valid still fires
                        end else if (s_last) begin
                            // Truncated frame: fewer beats than HEADER_BEATS
                            hdr_beat <= '0;
                            // stay in S_HDR_CAP; no hdr_valid pulse
                        end else begin
                            hdr_beat <= hdr_beat + 1'b1;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_PAYLOAD: begin
                    if (s_valid && m_ready && s_last)
                        state <= S_HDR_CAP;
                end
                // ---------------------------------------------------------
                default: state <= S_HDR_CAP;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // hdr_data output: registered captured header
    // -------------------------------------------------------------------------
    assign hdr_data = hdr_data_reg;

    // -------------------------------------------------------------------------
    // Combinatorial output mux
    // -------------------------------------------------------------------------
    always_comb begin
        s_ready = 1'b0;
        m_valid = 1'b0;
        m_data  = '0;
        m_keep  = '1;
        m_last  = 1'b0;
        m_user  = '0;

        unique case (state)
            S_HDR_CAP: begin
                // Accept header beats; suppress downstream
                s_ready = 1'b1;
                m_valid = 1'b0;
            end

            S_PAYLOAD: begin
                // Transparent pass-through of payload
                s_ready = m_ready;
                m_valid = s_valid;
                m_data  = s_data;
                m_keep  = s_keep;
                m_last  = s_last;
                m_user  = s_user;
            end

            default: ;
        endcase
    end

endmodule
