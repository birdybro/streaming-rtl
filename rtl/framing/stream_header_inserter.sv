// =============================================================================
// Module:      stream_header_inserter
// Description: Prepends a fixed-width header to each incoming AXI-Stream
//              frame.  Header data is supplied via a sideband ready/valid
//              handshake port.  For each frame the module:
//                1. (S_HDR_WAIT) Stalls the payload stream and waits for
//                   hdr_valid to be asserted; latches hdr_data and asserts
//                   hdr_ready for one cycle to complete the handshake.
//                2. (S_HDR_SEND) Outputs HEADER_BEATS beats sourced from the
//                   captured header register, holding the payload stream back.
//                3. (S_PAYLOAD) Transparently passes the payload stream to
//                   the master until s_last is accepted, then returns to
//                   S_HDR_WAIT for the next frame.
//              m_last follows s_last from the payload; header beats have
//              m_last deasserted.  m_keep is all-ones during header beats.
//
// Parameters:
//   DATA_WIDTH    - Width of data payload in bits          (default: 8)
//   HEADER_BEATS  - Number of header beats to prepend      (default: 4)
//   USER_WIDTH    - Width of sideband user signal          (default: 1)
//   KEEP_WIDTH    - Number of byte-enable keep bits        (default: DATA_WIDTH/8)
//
// Ports:
//   clk           - Clock
//   rst_n         - Active-low synchronous reset
//   s_valid       - Payload stream upstream valid
//   s_ready       - Payload stream upstream ready
//   s_data        - Payload stream data
//   s_keep        - Payload stream byte enables
//   s_last        - Payload stream packet end
//   s_user        - Payload stream sideband data
//   hdr_valid     - Header sideband valid
//   hdr_ready     - Header sideband ready
//   hdr_data      - Header sideband data (HEADER_BEATS*DATA_WIDTH bits wide)
//   m_valid       - Downstream valid
//   m_ready       - Downstream ready
//   m_data        - Downstream data
//   m_keep        - Downstream byte enables
//   m_last        - Downstream packet end
//   m_user        - Downstream sideband data
//
// Latency:       0 additional payload cycles (header prepended before payload)
// Throughput:    1 transfer/cycle during header and payload phases
// Backpressure:  s_ready deasserted during header phase; m_ready causes
//                backpressure normally in payload phase
// Limitations:   HEADER_BEATS >= 1; each frame must be terminated with s_last
// =============================================================================

module stream_header_inserter #(
    parameter int DATA_WIDTH   = 8,
    parameter int HEADER_BEATS = 4,
    parameter int USER_WIDTH   = 1,
    parameter int KEEP_WIDTH   = DATA_WIDTH / 8
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    // Payload slave interface
    input  logic                                    s_valid,
    output logic                                    s_ready,
    input  logic [DATA_WIDTH-1:0]                   s_data,
    input  logic [KEEP_WIDTH-1:0]                   s_keep,
    input  logic                                    s_last,
    input  logic [USER_WIDTH-1:0]                   s_user,

    // Header sideband interface
    input  logic                                    hdr_valid,
    output logic                                    hdr_ready,
    input  logic [HEADER_BEATS*DATA_WIDTH-1:0]      hdr_data,

    // Master interface
    output logic                                    m_valid,
    input  logic                                    m_ready,
    output logic [DATA_WIDTH-1:0]                   m_data,
    output logic [KEEP_WIDTH-1:0]                   m_keep,
    output logic                                    m_last,
    output logic [USER_WIDTH-1:0]                   m_user
);

    // synthesis translate_off
    initial begin
        if (HEADER_BEATS < 1)
            $fatal(1, "stream_header_inserter: HEADER_BEATS must be >= 1, got %0d", HEADER_BEATS);
    end
    // synthesis translate_on

    localparam int HDR_CNT_W = (HEADER_BEATS > 1) ? $clog2(HEADER_BEATS) : 1;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_HDR_WAIT = 2'd0,   // waiting for header sideband handshake
        S_HDR_SEND = 2'd1,   // streaming header beats to master
        S_PAYLOAD  = 2'd2    // passing payload through to master
    } state_e;

    state_e state;

    // -------------------------------------------------------------------------
    // Captured header register and beat index
    // -------------------------------------------------------------------------
    logic [HEADER_BEATS*DATA_WIDTH-1:0] hdr_reg;
    logic [HDR_CNT_W-1:0]              hdr_beat;

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_HDR_WAIT;
            hdr_beat <= '0;
            hdr_reg  <= '0;
        end else begin
            unique case (state)
                // ---------------------------------------------------------
                S_HDR_WAIT: begin
                    if (hdr_valid) begin
                        hdr_reg  <= hdr_data;
                        hdr_beat <= '0;
                        state    <= S_HDR_SEND;
                    end
                end
                // ---------------------------------------------------------
                S_HDR_SEND: begin
                    if (m_ready) begin
                        if (hdr_beat == HDR_CNT_W'(HEADER_BEATS - 1)) begin
                            hdr_beat <= '0;
                            state    <= S_PAYLOAD;
                        end else begin
                            hdr_beat <= hdr_beat + 1'b1;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_PAYLOAD: begin
                    if (s_valid && m_ready && s_last)
                        state <= S_HDR_WAIT;
                end
                // ---------------------------------------------------------
                default: state <= S_HDR_WAIT;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Combinatorial output mux
    // -------------------------------------------------------------------------
    always_comb begin
        // Defaults
        hdr_ready = 1'b0;
        s_ready   = 1'b0;
        m_valid   = 1'b0;
        m_data    = '0;
        m_keep    = '1;
        m_last    = 1'b0;
        m_user    = '0;

        unique case (state)
            S_HDR_WAIT: begin
                // Accept header; payload stalled
                hdr_ready = 1'b1;
            end

            S_HDR_SEND: begin
                // Drive current header beat; payload stalled
                m_valid = 1'b1;
                m_data  = hdr_reg[hdr_beat * DATA_WIDTH +: DATA_WIDTH];
                m_keep  = '1;
                m_last  = 1'b0;
                m_user  = '0;
            end

            S_PAYLOAD: begin
                // Transparent pass-through of payload
                m_valid = s_valid;
                s_ready = m_ready;
                m_data  = s_data;
                m_keep  = s_keep;
                m_last  = s_last;
                m_user  = s_user;
            end

            default: ;
        endcase
    end

endmodule
