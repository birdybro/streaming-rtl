// =============================================================================
// Example 2: Packet Processing Pipeline
// =============================================================================
// Description:
//   Demonstrates frame-aware packet processing using header strip/insert
//   primitives.  Each incoming frame is split into a header sideband and a
//   payload stream, the payload passes through a register slice for pipeline
//   depth, and the original (or modified) header is reattached before the
//   frame exits.
//
//   Data flow:
//
//     source
//       │
//       ▼
//     stream_header_stripper  ──hdr_data──►  stream_header_inserter
//       │  (payload)                               │  (header sideband)
//       ▼                                          │
//     stream_register_slice ─────────────────────► │
//       │  (registered payload)                    │
//       └──────────────────────────────────────────►
//                                                  ▼
//                                                sink
//
//   The hdr_valid pulse from the stripper connects directly to hdr_valid of
//   the inserter, and hdr_data is looped back so that headers are preserved
//   verbatim.  Replace the pass-through with header-rewrite logic as needed.
//
// Parameters:
//   DATA_WIDTH    - Width of the data bus (default 8)
//   HEADER_BEATS  - Number of beats forming the frame header (default 4)
//
// Interfaces (AXI-Stream ready/valid):
//   source side: clk, rst_n, s_valid, s_ready, s_data, s_keep, s_last, s_user
//   sink   side: m_valid, m_ready, m_data, m_keep, m_last, m_user
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module ex2_packet_processing #(
    parameter int DATA_WIDTH   = 8,
    parameter int HEADER_BEATS = 4
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Source interface
    input  logic                   s_valid,
    output logic                   s_ready,
    input  logic [DATA_WIDTH-1:0]  s_data,
    input  logic                   s_keep,
    input  logic                   s_last,
    input  logic                   s_user,

    // Sink interface
    output logic                   m_valid,
    input  logic                   m_ready,
    output logic [DATA_WIDTH-1:0]  m_data,
    output logic                   m_keep,
    output logic                   m_last,
    output logic                   m_user
);

    // -------------------------------------------------------------------------
    // Wires: header stripper → register slice (payload path)
    // -------------------------------------------------------------------------
    logic                                   strip_m_valid;
    logic                                   strip_m_ready;
    logic [DATA_WIDTH-1:0]                  strip_m_data;
    logic                                   strip_m_keep;
    logic                                   strip_m_last;
    logic                                   strip_m_user;

    // -------------------------------------------------------------------------
    // Wires: header stripper sideband output
    // -------------------------------------------------------------------------
    logic [HEADER_BEATS*DATA_WIDTH-1:0]     hdr_data;
    logic                                   hdr_valid;

    // -------------------------------------------------------------------------
    // Wires: register slice → header inserter (registered payload path)
    // -------------------------------------------------------------------------
    logic                                   rs_m_valid;
    logic                                   rs_m_ready;
    logic [DATA_WIDTH-1:0]                  rs_m_data;
    logic                                   rs_m_keep;
    logic                                   rs_m_last;
    logic                                   rs_m_user;

    // -------------------------------------------------------------------------
    // Wire: header inserter sideband handshake (hdr_ready consumed internally)
    // -------------------------------------------------------------------------
    logic                                   hdr_ready;

    // -------------------------------------------------------------------------
    // Stage 1: Header stripper — absorbs first HEADER_BEATS beats per frame
    // -------------------------------------------------------------------------
    stream_header_stripper #(
        .DATA_WIDTH   (DATA_WIDTH),
        .HEADER_BEATS (HEADER_BEATS),
        .USER_WIDTH   (1),
        .KEEP_WIDTH   (1)
    ) u_stripper (
        .clk       (clk),
        .rst_n     (rst_n),
        .s_valid   (s_valid),
        .s_ready   (s_ready),
        .s_data    (s_data),
        .s_keep    (s_keep),
        .s_last    (s_last),
        .s_user    (s_user),
        .m_valid   (strip_m_valid),
        .m_ready   (strip_m_ready),
        .m_data    (strip_m_data),
        .m_keep    (strip_m_keep),
        .m_last    (strip_m_last),
        .m_user    (strip_m_user),
        .hdr_data  (hdr_data),
        .hdr_valid (hdr_valid)
    );

    // -------------------------------------------------------------------------
    // Stage 2: Register slice — pipeline the payload path
    // -------------------------------------------------------------------------
    stream_register_slice #(
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_reg_slice (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (strip_m_valid),
        .s_ready (strip_m_ready),
        .s_data  (strip_m_data),
        .s_keep  (strip_m_keep),
        .s_last  (strip_m_last),
        .s_user  (strip_m_user),
        .m_valid (rs_m_valid),
        .m_ready (rs_m_ready),
        .m_data  (rs_m_data),
        .m_keep  (rs_m_keep),
        .m_last  (rs_m_last),
        .m_user  (rs_m_user)
    );

    // -------------------------------------------------------------------------
    // Stage 3: Header inserter — prepends the captured header to each payload
    //
    // hdr_valid from the stripper pulses exactly once per frame, immediately
    // after the last header beat is captured.  The inserter latches hdr_data
    // on the hdr_valid/hdr_ready handshake and prepends it before passing
    // the payload through.
    // -------------------------------------------------------------------------
    stream_header_inserter #(
        .DATA_WIDTH   (DATA_WIDTH),
        .HEADER_BEATS (HEADER_BEATS),
        .USER_WIDTH   (1),
        .KEEP_WIDTH   (1)
    ) u_inserter (
        .clk       (clk),
        .rst_n     (rst_n),
        .s_valid   (rs_m_valid),
        .s_ready   (rs_m_ready),
        .s_data    (rs_m_data),
        .s_keep    (rs_m_keep),
        .s_last    (rs_m_last),
        .s_user    (rs_m_user),
        .hdr_valid (hdr_valid),
        .hdr_ready (hdr_ready),
        .hdr_data  (hdr_data),
        .m_valid   (m_valid),
        .m_ready   (m_ready),
        .m_data    (m_data),
        .m_keep    (m_keep),
        .m_last    (m_last),
        .m_user    (m_user)
    );

    // hdr_ready is driven by the inserter; no external logic required.
    // Suppress unused-signal lint warnings in tools that check it.
    /* verilator lint_off UNUSED */
    logic _unused_hdr_ready;
    assign _unused_hdr_ready = hdr_ready;
    /* verilator lint_on UNUSED */

endmodule

`default_nettype wire
