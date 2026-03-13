// =============================================================================
// stream_pulse_on_frame.sv
// =============================================================================
// Description:
//   Generates a single-cycle pulse at the start-of-frame (SoF) or
//   end-of-frame (EoF) of each stream frame. The stream is passed through
//   unchanged. SoF is the first accepted beat of a new frame; EoF is the
//   accepted beat where s_last is asserted.
//
// Parameters:
//   DATA_WIDTH    - Width of data bus (default: 8)
//   PULSE_ON_SOF  - 1: pulse on SoF; 0: pulse on EoF (default: 0)
//   USER_WIDTH    - Width of user sideband (default: 1)
//   KEEP_WIDTH    - Number of byte-enable bits (default: DATA_WIDTH/8)
//
// Ports:
//   clk/rst_n        - Clock and active-low synchronous reset
//   s_*/m_*          - Stream in/out (zero-latency pass-through)
//   pulse            - Single-cycle pulse on SoF or EoF
//
// Latency: 0 cycles
// Throughput: 1 beat/cycle
// Backpressure: passes m_ready to s_ready
// =============================================================================

module stream_pulse_on_frame #(
    parameter int DATA_WIDTH   = 8,
    parameter bit PULSE_ON_SOF = 1'b0,
    parameter int USER_WIDTH   = 1,
    parameter int KEEP_WIDTH   = DATA_WIDTH / 8
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   s_valid,
    output logic                   s_ready,
    input  logic [DATA_WIDTH-1:0]  s_data,
    input  logic [KEEP_WIDTH-1:0]  s_keep,
    input  logic                   s_last,
    input  logic [USER_WIDTH-1:0]  s_user,

    output logic                   m_valid,
    input  logic                   m_ready,
    output logic [DATA_WIDTH-1:0]  m_data,
    output logic [KEEP_WIDTH-1:0]  m_keep,
    output logic                   m_last,
    output logic [USER_WIDTH-1:0]  m_user,

    output logic                   pulse
);

    // Pass-through
    assign m_valid = s_valid;
    assign s_ready = m_ready;
    assign m_data  = s_data;
    assign m_keep  = s_keep;
    assign m_last  = s_last;
    assign m_user  = s_user;

    // Track whether we are at the start of a new frame
    logic in_frame;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            in_frame <= 1'b0;
            pulse    <= 1'b0;
        end else begin
            pulse <= 1'b0;
            if (s_valid && m_ready) begin
                if (PULSE_ON_SOF) begin
                    // Pulse on first beat of frame (in_frame == 0)
                    if (!in_frame) begin
                        pulse    <= 1'b1;
                        in_frame <= 1'b1;
                    end
                    if (s_last) begin
                        in_frame <= 1'b0;
                    end
                end else begin
                    // Pulse on last beat of frame
                    if (s_last) begin
                        pulse    <= 1'b1;
                        in_frame <= 1'b0;
                    end else begin
                        in_frame <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
