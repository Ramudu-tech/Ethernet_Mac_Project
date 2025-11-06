// ============================================================================
// RX AXIS → MM Bridge
// - AXIS from MAC (s_axis_*)
// - Internally buffers bytes (byte FIFO) and frame descriptors (length + bad_fcs)
// - MM read window interface for axi4_eth_slave: rxw_data/rxw_valid/rxw_pop
// - Pulses ev_rx_done when a frame completes on AXIS
// - Exposes rx_frame_ready, rx_len (oldest frame), rx_bad_fcs, rx_overflow(=0), rx_level
// ----------------------------------------------------------------------------
// Notes
// * AXIS width default 8 (GMII). Any byte-multiple AXIS width works.
// * MM width 32/64 typical. Last word of a frame is zero-padded.
// * Safe backpressure: s_axis_tready deasserts when there isn't space for the
//   incoming beat or the length FIFO is full on a tlast beat.
// ============================================================================

module rx_axis2mm_bridge #(
  parameter int DATA_WIDTH        = 32,    // MM read-beat width seen by CPU (word from RX window)
  parameter int AXIS_DATA_WIDTH   = 8,     // AXIS width from MAC (8 for GMII)
  parameter int FIFO_BYTES        = 4096,  // byte FIFO depth (power-of-two recommended)
  parameter int LENFIFO_DEPTH     = 8      // number of frames that can queue
)(
  input  logic                          clk,
  input  logic                          rst,

  // AXI-Stream from MAC
  input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_tdata,
  input  logic [(AXIS_DATA_WIDTH/8)-1:0] s_axis_tkeep,
  input  logic                          s_axis_tvalid,
  output logic                          s_axis_tready,
  input  logic                          s_axis_tlast,
  input  logic                          s_axis_tuser_bad_fcs, // 1=bad frame (if provided by MAC)

  // Status outward (to CSRs)
  output logic                          rx_frame_ready, // at least 1 frame queued
  output logic [15:0]                   rx_len,         // length of current (oldest) frame
  output logic                          rx_bad_fcs,     // bad_fcs for current frame
  output logic                          rx_overflow,    // sticky; stays 0 with backpressure policy
  output logic [15:0]                   rx_level,       // bytes currently in byte FIFO

  // Event pulse
  output logic                          ev_rx_done,     // 1-cycle pulse when a frame is enqueued

  // Read window toward axi4_eth_slave
  output logic [DATA_WIDTH-1:0]         rxw_data,
  output logic                          rxw_valid,
  input  logic                          rxw_pop
);

  // ------------------ Sanity checks ------------------
  localparam int MM_BYTES   = DATA_WIDTH/8;
  localparam int AXIS_BYTES = AXIS_DATA_WIDTH/8;
  initial begin
    if (DATA_WIDTH % 8 != 0)      $fatal(1, "DATA_WIDTH must be a byte multiple");
    if (AXIS_DATA_WIDTH % 8 != 0) $fatal(1, "AXIS_DATA_WIDTH must be a byte multiple");
    if (AXIS_BYTES == 0)          $fatal(1, "AXIS_DATA_WIDTH too small");
  end

  // ------------------ Byte FIFO ----------------------
  localparam int PTR_W   = $clog2(FIFO_BYTES);
  localparam int COUNT_W = $clog2(FIFO_BYTES+1);

  logic [7:0]                byte_mem [0:FIFO_BYTES-1];
  logic [PTR_W-1:0]          wr_ptr, rd_ptr;
  logic [COUNT_W-1:0]        fifo_count;  // number of bytes stored

  // n_bytes on current AXIS beat
  function automatic int popcount_axis (input logic [AXIS_BYTES-1:0] v);
    int c; c = 0;
    for (int i=0;i<AXIS_BYTES;i++) c += v[i];
    return c;
  endfunction

  // Free space and accept condition
  logic [COUNT_W-1:0] free_bytes;
  assign free_bytes = FIFO_BYTES[COUNT_W-1:0] - fifo_count;

  // ------------------ Frame descriptor FIFO (length + bad_fcs) -------------
  localparam int LFW = $clog2(LENFIFO_DEPTH+1);
  logic [15:0] len_q   [0:LENFIFO_DEPTH-1];
  logic        bad_q   [0:LENFIFO_DEPTH-1];
  logic [$clog2(LENFIFO_DEPTH)-1:0] len_wr_ptr, len_rd_ptr;
  logic [LFW-1:0]                   len_count;

  wire len_fifo_empty = (len_count == 0);
  wire len_fifo_full  = (len_count == LENFIFO_DEPTH);

  assign rx_frame_ready = !len_fifo_empty;
  assign rx_len         = len_fifo_empty ? 16'd0 : len_q[len_rd_ptr];
  assign rx_bad_fcs     = len_fifo_empty ? 1'b0  : bad_q[len_rd_ptr];

  // ------------------ AXIS ingest --------------------
  logic                 in_frame;
  logic [15:0]          frame_len_accum;
  logic                 frame_bad_accum;

  // Compute prospective accept count
  int beat_bytes;
  always @* begin
    beat_bytes = s_axis_tvalid ? popcount_axis(s_axis_tkeep) : 0;
  end

  // Ready: enough FIFO space for this beat AND (if tlast) length FIFO not full
  assign s_axis_tready = (!rst) &&
                         ( (!s_axis_tvalid) ||
                           (free_bytes >= beat_bytes && (!s_axis_tlast || !len_fifo_full)) );

  // Push/pop accounting for byte FIFO (single always block updates count/ptrs)
  int push_bytes, pop_bytes;

  // ------------------ Read-window planner ------------------
  // Track how many bytes are left to serve from the *current* (oldest) frame
  logic [15:0] bytes_left_cur;     // decremented on each rxw_pop (min with MM_BYTES)
  logic        have_frame_cur;     // len_count > 0 latched for convenience

  // rxw_valid when we have enough bytes to serve one word OR it's the final partial word
  logic [15:0] need_bytes;
  always @* begin
    have_frame_cur = (len_count != 0);
    need_bytes     = have_frame_cur
                    ? ((bytes_left_cur >= MM_BYTES) ? MM_BYTES : bytes_left_cur)
                    : 16'd0;

    // Serve only if enough bytes are already in byte FIFO for this beat
    rxw_valid = (have_frame_cur && (need_bytes != 0) && (fifo_count >= need_bytes));
  end

  // Compose rxw_data from byte FIFO (zero-pad for the final partial word)
  always @* begin
    rxw_data = '0;
    if (rxw_valid) begin
      for (int b=0; b<MM_BYTES; b++) begin
        if (b < need_bytes)
          rxw_data[8*b +: 8] = byte_mem[(rd_ptr + b) & ((1<<PTR_W)-1)];
        else
          rxw_data[8*b +: 8] = 8'h00;
      end
    end
  end

  // ------------------ State & counters ------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      // FIFOs
      wr_ptr      <= '0;
      rd_ptr      <= '0;
      fifo_count  <= '0;

      len_wr_ptr  <= '0;
      len_rd_ptr  <= '0;
      len_count   <= '0;

      // AXIS state
      in_frame         <= 1'b0;
      frame_len_accum  <= 16'd0;
      frame_bad_accum  <= 1'b0;

      // Read-window state
      bytes_left_cur   <= 16'd0;

      // Status / events
      rx_overflow  <= 1'b0;
      rx_level     <= 16'd0;
      ev_rx_done   <= 1'b0;
    end else begin
      ev_rx_done <= 1'b0; // default: pulse

      // ------------------ Accept bytes from AXIS ------------------
      push_bytes = 0;
      if (s_axis_tvalid && s_axis_tready) begin
        // Start-of-frame detect (no explicit s_axis_tfirst, use in_frame flag)
        if (!in_frame) begin
          in_frame        <= 1'b1;
          frame_len_accum <= 16'd0;
          frame_bad_accum <= 1'b0;
        end

        // Write accepted bytes into byte FIFO in lane order 0..AXIS_BYTES-1
        for (int i=0;i<AXIS_BYTES;i++) begin
          if (s_axis_tkeep[i]) begin
            byte_mem[wr_ptr] <= s_axis_tdata[8*i +: 8];
            wr_ptr           <= wr_ptr + 1'b1;
            push_bytes++;
          end
        end
        frame_len_accum <= frame_len_accum + push_bytes[15:0];
        frame_bad_accum <= frame_bad_accum | s_axis_tuser_bad_fcs;

        if (s_axis_tlast) begin
          // End of frame: enqueue descriptor (length + bad flag)
          // At this point len_fifo_full is guaranteed false (ready condition)
          len_q[len_wr_ptr] <= frame_len_accum + push_bytes[15:0];
          bad_q[len_wr_ptr] <= frame_bad_accum;
          len_wr_ptr        <= len_wr_ptr + 1'b1;
          len_count         <= len_count + 1'b1;

          // If this was the only/first frame queued, prime bytes_left_cur
          if (len_count == 0)
            bytes_left_cur <= frame_len_accum + push_bytes[15:0];

          // Event pulse
          ev_rx_done <= 1'b1;

          // Reset accumulators for the next frame
          in_frame        <= 1'b0;
          frame_len_accum <= 16'd0;
          frame_bad_accum <= 1'b0;
        end
      end

      // ------------------ Serve MM reads ------------------
      pop_bytes = 0;
      if (rxw_pop && rxw_valid) begin
        // Pop min(MM_BYTES, bytes_left_cur) from byte FIFO
        int n = (bytes_left_cur >= MM_BYTES) ? MM_BYTES : bytes_left_cur;
        rd_ptr       <= rd_ptr + n[$bits(rd_ptr)-1:0];
        pop_bytes    <= n;
        bytes_left_cur <= bytes_left_cur - n[15:0];

        // When current frame fully drained, advance to next descriptor
        if (bytes_left_cur == n[15:0]) begin
          // consume length entry
          len_rd_ptr  <= len_rd_ptr + 1'b1;
          len_count   <= len_count - 1'b1;

          // next frame (if any): prime bytes_left_cur
          if (len_count > 1) begin
            // len_count was >1 before decrement → next exists after ++rd_ptr
            bytes_left_cur <= len_q[(len_rd_ptr + 1'b1) & (LENFIFO_DEPTH-1)];
          end else begin
            bytes_left_cur <= 16'd0;
          end
        end
      end

      // ------------------ Update byte FIFO count & level ------------
      fifo_count <= fifo_count + push_bytes[COUNT_W-1:0] - pop_bytes[COUNT_W-1:0];
      rx_level   <= (fifo_count[15:0] == fifo_count) ? fifo_count[15:0] : 16'hFFFF;

      // ------------------ Overflow flag (sticky) --------------------
      // With strict backpressure policy, we don't drop; keep 0.
      // You can set this if you later add a "drop-on-full" mode.
      rx_overflow <= rx_overflow; // unchanged
    end
  end

endmodule

