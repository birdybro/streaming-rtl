// =============================================================================
// Example 3: Multi-Source Arbitration
// =============================================================================
// Description:
//   Demonstrates merging four independent AXI-Stream sources into a single
//   output stream using round-robin arbitration, followed by an elastic buffer
//   to decouple the arbiter from a downstream consumer.
//
//   Data flow:
//
//     source_0 ─┐
//     source_1 ─┤
//     source_2 ─┤──► stream_arbiter_round_robin ──► stream_elastic_buffer ──► sink
//     source_3 ─┘
//
//   The round-robin arbiter grants one source at a time and holds the grant
//   for the entire frame (until s_last is accepted), preventing frame
//   interleaving.  The elastic buffer absorbs micro-bursts from the arbiter
//   and presents a stable flow to the downstream consumer.
//
// Parameters:
//   NUM_SOURCES - Number of input streams (default 4)
//   DATA_WIDTH  - Width of the data bus (default 8)
//   BUF_DEPTH   - Depth of the elastic buffer; must be power of 2 (default 32)
//
// Interfaces (AXI-Stream ready/valid):
//   sources: clk, rst_n, s_valid[N], s_ready[N], s_data[N], s_keep[N],
//            s_last[N], s_user[N]
//   sink:    m_valid, m_ready, m_data, m_keep, m_last, m_user
//   status:  almost_full, almost_empty (from elastic buffer)
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module ex3_multi_source_arbitration #(
    parameter int NUM_SOURCES = 4,
    parameter int DATA_WIDTH  = 8,
    parameter int BUF_DEPTH   = 32
) (
    input  logic                                        clk,
    input  logic                                        rst_n,

    // Source interfaces (packed arrays, one entry per source)
    input  logic [NUM_SOURCES-1:0]                      s_valid,
    output logic [NUM_SOURCES-1:0]                      s_ready,
    input  logic [NUM_SOURCES-1:0][DATA_WIDTH-1:0]      s_data,
    input  logic [NUM_SOURCES-1:0]                      s_keep,
    input  logic [NUM_SOURCES-1:0]                      s_last,
    input  logic [NUM_SOURCES-1:0]                      s_user,

    // Sink interface
    output logic                                        m_valid,
    input  logic                                        m_ready,
    output logic [DATA_WIDTH-1:0]                       m_data,
    output logic                                        m_keep,
    output logic                                        m_last,
    output logic                                        m_user,

    // Elastic buffer status
    output logic                                        almost_full,
    output logic                                        almost_empty
);

    // -------------------------------------------------------------------------
    // Internal wires: arbiter → elastic buffer
    // -------------------------------------------------------------------------
    logic                   arb_m_valid;
    logic                   arb_m_ready;
    logic [DATA_WIDTH-1:0]  arb_m_data;
    logic                   arb_m_keep;
    logic                   arb_m_last;
    logic                   arb_m_user;

    // One-hot grant output (available for external monitoring)
    /* verilator lint_off UNUSED */
    logic [NUM_SOURCES-1:0] grant;
    /* verilator lint_on UNUSED */

    // -------------------------------------------------------------------------
    // Stage 1: Round-robin arbiter — frame-locked, starvation-free scheduling
    // -------------------------------------------------------------------------
    stream_arbiter_round_robin #(
        .NUM_INPUTS (NUM_SOURCES),
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_arbiter (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (s_valid),
        .s_ready (s_ready),
        .s_data  (s_data),
        .s_keep  (s_keep),
        .s_last  (s_last),
        .s_user  (s_user),
        .m_valid (arb_m_valid),
        .m_ready (arb_m_ready),
        .m_data  (arb_m_data),
        .m_keep  (arb_m_keep),
        .m_last  (arb_m_last),
        .m_user  (arb_m_user),
        .grant   (grant)
    );

    // -------------------------------------------------------------------------
    // Stage 2: Elastic buffer — decouples arbiter output from the downstream
    //          consumer and provides almost_full/almost_empty status flags
    // -------------------------------------------------------------------------
    stream_elastic_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (BUF_DEPTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_elastic_buf (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_valid      (arb_m_valid),
        .s_ready      (arb_m_ready),
        .s_data       (arb_m_data),
        .s_keep       (arb_m_keep),
        .s_last       (arb_m_last),
        .s_user       (arb_m_user),
        .m_valid      (m_valid),
        .m_ready      (m_ready),
        .m_data       (m_data),
        .m_keep       (m_keep),
        .m_last       (m_last),
        .m_user       (m_user),
        .almost_full  (almost_full),
        .almost_empty (almost_empty)
    );

endmodule

`default_nettype wire
