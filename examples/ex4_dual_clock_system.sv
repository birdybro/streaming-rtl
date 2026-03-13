// =============================================================================
// Example 4: Dual-Clock Streaming System
// =============================================================================
// Description:
//   Demonstrates safe clock-domain crossing (CDC) for an AXI-Stream bus.
//   Data is produced in a fast write domain and consumed in a slow read domain.
//   An asynchronous FIFO bridges the two clock domains using Gray-coded
//   pointers.  A register slice on the output side fully registers the read-
//   domain backpressure path.
//
//   Data flow:
//
//     s_clk domain                       m_clk domain
//     ─────────────────────              ──────────────────────────
//     source  ──►  stream_async_fifo  ──►  stream_register_slice  ──►  sink
//
//   The async FIFO uses SYNC_STAGES=2 synchronizer stages on each pointer
//   crossing.  Increasing SYNC_STAGES to 3 reduces the MTBF of metastability
//   at the cost of higher pointer-crossing latency.
//
// Parameters:
//   DATA_WIDTH  - Width of the data bus (default 8)
//   FIFO_DEPTH  - Depth of the async FIFO; must be power of 2 (default 16)
//
// Interfaces:
//   Write domain: s_clk, s_rst_n, s_valid, s_ready, s_data, s_keep,
//                 s_last, s_user
//   Read  domain: m_clk, m_rst_n, m_valid, m_ready, m_data, m_keep,
//                 m_last, m_user
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module ex4_dual_clock_system #(
    parameter int DATA_WIDTH = 8,
    parameter int FIFO_DEPTH = 16
) (
    // Write-domain (fast) clock and reset
    input  logic                   s_clk,
    input  logic                   s_rst_n,

    // Source interface (write domain)
    input  logic                   s_valid,
    output logic                   s_ready,
    input  logic [DATA_WIDTH-1:0]  s_data,
    input  logic                   s_keep,
    input  logic                   s_last,
    input  logic                   s_user,

    // Read-domain (slow) clock and reset
    input  logic                   m_clk,
    input  logic                   m_rst_n,

    // Sink interface (read domain)
    output logic                   m_valid,
    input  logic                   m_ready,
    output logic [DATA_WIDTH-1:0]  m_data,
    output logic                   m_keep,
    output logic                   m_last,
    output logic                   m_user
);

    // -------------------------------------------------------------------------
    // Internal wires: async FIFO read side → register slice (both in m_clk)
    // -------------------------------------------------------------------------
    logic                  afifo_m_valid;
    logic                  afifo_m_ready;
    logic [DATA_WIDTH-1:0] afifo_m_data;
    logic                  afifo_m_keep;
    logic                  afifo_m_last;
    logic                  afifo_m_user;

    // -------------------------------------------------------------------------
    // Stage 1: Asynchronous FIFO — Gray-coded pointer CDC
    //
    // Write side runs at s_clk; read side runs at m_clk.
    // Both resets must be asserted before releasing for correct operation.
    // -------------------------------------------------------------------------
    stream_async_fifo #(
        .DATA_WIDTH  (DATA_WIDTH),
        .DEPTH       (FIFO_DEPTH),
        .SYNC_STAGES (2),
        .USER_WIDTH  (1),
        .KEEP_WIDTH  (1)
    ) u_async_fifo (
        // Write (slave) side
        .s_clk   (s_clk),
        .s_rst_n (s_rst_n),
        .s_valid (s_valid),
        .s_ready (s_ready),
        .s_data  (s_data),
        .s_keep  (s_keep),
        .s_last  (s_last),
        .s_user  (s_user),
        // Read (master) side
        .m_clk   (m_clk),
        .m_rst_n (m_rst_n),
        .m_valid (afifo_m_valid),
        .m_ready (afifo_m_ready),
        .m_data  (afifo_m_data),
        .m_keep  (afifo_m_keep),
        .m_last  (afifo_m_last),
        .m_user  (afifo_m_user)
    );

    // -------------------------------------------------------------------------
    // Stage 2: Register slice (read domain) — fully registers data and
    //          backpressure paths on the m_clk side
    // -------------------------------------------------------------------------
    stream_register_slice #(
        .DATA_WIDTH (DATA_WIDTH),
        .USER_WIDTH (1),
        .KEEP_WIDTH (1)
    ) u_reg_slice (
        .clk     (m_clk),
        .rst_n   (m_rst_n),
        .s_valid (afifo_m_valid),
        .s_ready (afifo_m_ready),
        .s_data  (afifo_m_data),
        .s_keep  (afifo_m_keep),
        .s_last  (afifo_m_last),
        .s_user  (afifo_m_user),
        .m_valid (m_valid),
        .m_ready (m_ready),
        .m_data  (m_data),
        .m_keep  (m_keep),
        .m_last  (m_last),
        .m_user  (m_user)
    );

endmodule

`default_nettype wire
