// =============================================================================
// Example 1: Streaming Pipeline
// =============================================================================
// Description:
//   Demonstrates a three-stage streaming pipeline composed from library
//   primitives.  Data flows:
//
//     source → stream_register_slice → stream_fifo → stream_perf_monitor → sink
//
//   The register slice fully registers both the data and backpressure paths,
//   isolating the source from downstream timing.  The FIFO absorbs bursts up
//   to FIFO_DEPTH beats deep.  The performance monitor sits at the output and
//   accumulates throughput statistics without adding latency.
//
// Parameters:
//   DATA_WIDTH  - Width of the data bus (default 8)
//   FIFO_DEPTH  - Depth of the FIFO buffer; must be power of 2 (default 16)
//
// Interfaces (all AXI-Stream ready/valid):
//   source side: clk, rst_n, s_valid, s_ready, s_data, s_keep, s_last, s_user
//   sink   side: m_valid, m_ready, m_data, m_keep, m_last, m_user
//   stats  side: stats_clear, beat_count, byte_count, cycle_count,
//                idle_cycles, bp_cycles
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module ex1_streaming_pipeline #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16
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
    output logic                   m_user,

    // Performance counter interface
    input  logic                   stats_clear,
    output logic [31:0]            beat_count,
    output logic [31:0]            byte_count,
    output logic [31:0]            cycle_count,
    output logic [31:0]            idle_cycles,
    output logic [31:0]            bp_cycles
);

    // -------------------------------------------------------------------------
    // Internal wires: register_slice → fifo
    // -------------------------------------------------------------------------
    logic                  rs_m_valid;
    logic                  rs_m_ready;
    logic [DATA_WIDTH-1:0] rs_m_data;
    logic                  rs_m_keep;
    logic                  rs_m_last;
    logic                  rs_m_user;

    // -------------------------------------------------------------------------
    // Internal wires: fifo → perf_monitor
    // -------------------------------------------------------------------------
    logic                  fifo_m_valid;
    logic                  fifo_m_ready;
    logic [DATA_WIDTH-1:0] fifo_m_data;
    logic                  fifo_m_keep;
    logic                  fifo_m_last;
    logic                  fifo_m_user;

    // FIFO status (available for external monitoring if desired)
    /* verilator lint_off UNUSED */
    logic [$clog2(FIFO_DEPTH):0] fifo_count;
    logic fifo_full, fifo_empty, fifo_almost_full, fifo_almost_empty;
    /* verilator lint_on UNUSED */

    // -------------------------------------------------------------------------
    // Stage 1: Register slice — fully registers data and backpressure paths
    // -------------------------------------------------------------------------
    stream_register_slice #(
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_reg_slice (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (s_valid),
        .s_ready (s_ready),
        .s_data  (s_data),
        .s_keep  (s_keep),
        .s_last  (s_last),
        .s_user  (s_user),
        .m_valid (rs_m_valid),
        .m_ready (rs_m_ready),
        .m_data  (rs_m_data),
        .m_keep  (rs_m_keep),
        .m_last  (rs_m_last),
        .m_user  (rs_m_user)
    );

    // -------------------------------------------------------------------------
    // Stage 2: FIFO buffer — absorbs bursts up to FIFO_DEPTH beats
    // -------------------------------------------------------------------------
    stream_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_valid      (rs_m_valid),
        .s_ready      (rs_m_ready),
        .s_data       (rs_m_data),
        .s_keep       (rs_m_keep),
        .s_last       (rs_m_last),
        .s_user       (rs_m_user),
        .m_valid      (fifo_m_valid),
        .m_ready      (fifo_m_ready),
        .m_data       (fifo_m_data),
        .m_keep       (fifo_m_keep),
        .m_last       (fifo_m_last),
        .m_user       (fifo_m_user),
        .count        (fifo_count),
        .full         (fifo_full),
        .empty        (fifo_empty),
        .almost_full  (fifo_almost_full),
        .almost_empty (fifo_almost_empty)
    );

    // -------------------------------------------------------------------------
    // Stage 3: Performance monitor — zero-latency pass-through with counters
    // -------------------------------------------------------------------------
    stream_perf_monitor #(
        .DATA_WIDTH (DATA_WIDTH),
        .STAT_WIDTH (32),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_perf_mon (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_valid     (fifo_m_valid),
        .s_ready     (fifo_m_ready),
        .s_data      (fifo_m_data),
        .s_keep      (fifo_m_keep),
        .s_last      (fifo_m_last),
        .s_user      (fifo_m_user),
        .m_valid     (m_valid),
        .m_ready     (m_ready),
        .m_data      (m_data),
        .m_keep      (m_keep),
        .m_last      (m_last),
        .m_user      (m_user),
        .stats_clear (stats_clear),
        .beat_count  (beat_count),
        .byte_count  (byte_count),
        .cycle_count (cycle_count),
        .idle_cycles (idle_cycles),
        .bp_cycles   (bp_cycles)
    );

endmodule

`default_nettype wire
