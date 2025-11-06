// ============================================================================
// TX MM → AXIS Bridge
// - MM side: accepts DATA_WIDTH-bit writes from axi4_eth_slave TX window
//            (txw_data, txw_strb, txw_push, txw_ready)
// - AXIS side: emits AXI-Stream beats (AXIS_DATA_WIDTH) toward MAC
// - Packet boundary is commanded by TX_LEN write (tx_len/tx_len_we)
// - Emits ev_tx_done pulse on final tlast handshake
// - Reports tx_busy, tx_level (bytes in FIFO), tx_underrun (reserved)
// ----------------------------------------------------------------------------
// Notes
// * One frame in flight at a time (do not assert tx_len_we while busy).
// * tvalid only asserts when enough bytes are available for the next beat
//   (so underrun cannot occur unless you add a timeout policy).
// * txw_ready deasserts when byte FIFO has < DATA_WIDTH/8 free bytes.
//   (conservative but safe; avoids partial acceptance hazards).
// ============================================================================

module tx_mm2axis_bridge #(
  parameter int DATA_WIDTH       = 32,  // AXI write-beat width (bytes pushed from CPU)
  parameter int AXIS_DATA_WIDTH  = 8,   // AXIS width to MAC (8 for GMII)
  parameter int FIFO_BYTES       = 4096 // internal byte FIFO depth (power of 2 recommended)
)(
  input  logic                     clk,
  input  logic                     rst,

  // Enable (from CTRL.MAC_EN), optional gating
  input  logic                     mac_enable,

  // Commanded frame length (bytes)
  input  logic [15:0]              tx_len,
  input  logic                     tx_len_we,   // strobe when TX_LEN written

  // Status/IRQ up to CSRs
  output logic                     tx_busy,
  output logic                     tx_underrun, // stays 0 unless you add timeout policy
  output logic [15:0]              tx_level,    // bytes in FIFO (saturated)
  output logic                     ev_tx_done,  // 1-cycle pulse when last beat handshakes

  // Write window (from axi4_eth_slave)
  input  logic [DATA_WIDTH-1:0]    txw_data,
  input  logic [DATA_WIDTH/8-1:0]  txw_strb,
  input  logic                     txw_push,    // accept this beat
  output logic                     txw_ready,   // backpressure towards AXI

  // AXI-Stream out to MAC
  output logic [AXIS_DATA_WIDTH-1:0]        m_axis_tdata,
  output logic [(AXIS_DATA_WIDTH/8)-1:0]    m_axis_tkeep,
  output logic                              m_axis_tvalid,
  input  logic                               m_axis_tready,
  output logic                               m_axis_tlast
);

  // -------------------- Sanity checks --------------------
  localparam int MM_BYTES   = DATA_WIDTH/8;
  localparam int AXIS_BYTES = AXIS_DATA_WIDTH/8;
  initial begin
    if (DATA_WIDTH % 8 != 0)      $fatal(1, "DATA_WIDTH must be byte-multiple");
    if (AXIS_DATA_WIDTH % 8 != 0) $fatal(1, "AXIS_DATA_WIDTH must be byte-multiple");
    if (AXIS_BYTES == 0)          $fatal(1, "AXIS_DATA_WIDTH too small");
  end

  // -------------------- Simple byte FIFO -----------------
  localparam int CNT_W = $clog2(FIFO_BYTES+1);

  logic [7:0] byte_mem [0:FIFO_BYTES-1];
  logic [$clog2(FIFO_BYTES)-1:0] wr_ptr, rd_ptr;
  logic [CNT_W-1:0]              fifo_count; // number of bytes stored

  // push up to MM_BYTES per cycle (respecting WSTRB order: lane 0 first)
  function automatic int popcount8 (input logic [MM_BYTES-1:0] v);
    int c; c = 0;
    for (int i=0;i<MM_BYTES;i++) c += v[i];
    return c;
  endfunction

  // Conservative ready: only accept when there is room for a full DATA beat
  assign txw_ready = (fifo_count <= FIFO_BYTES - MM_BYTES);

  // MM -> FIFO push
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr     <= '0;
      fifo_count <= '0;
    end else begin
      if (txw_push && txw_ready) begin
        // write bytes for each asserted strobe bit, lane order 0..MM_BYTES-1
        for (int i=0;i<MM_BYTES;i++) begin
          if (txw_strb[i]) begin
            byte_mem[wr_ptr] <= txw_data[8*i +: 8];
            wr_ptr           <= wr_ptr + 1'b1;
            fifo_count       <= fifo_count + 1'b1;
          end
        end
      end
      // pops handled below in the streaming logic
    end
  end

  // level for status (saturate to 16b)
  always_comb begin
    tx_level = (fifo_count[15:0] == fifo_count) ? fifo_count[15:0] : 16'hFFFF;
  end

  // -------------------- Frame control --------------------
  typedef enum logic [1:0] {IDLE, STREAM} state_e;
  state_e state;

  logic [15:0] bytes_rem;  // bytes remaining in current frame
  logic        have_cmd;   // a TX_LEN command is latched
  logic        done_pulse;


  // Stream generation registers
  logic [AXIS_DATA_WIDTH-1:0] tdata_r;
  logic [(AXIS_BYTES)-1:0]    tkeep_r;
  logic                       tlast_r;
  logic                       tvalid_r;

  assign m_axis_tdata  = tdata_r;
  assign m_axis_tkeep  = tkeep_r;
  assign m_axis_tlast  = tlast_r;
  assign m_axis_tvalid = tvalid_r;

  // Underrun (not used unless you add timeout); keep low for now
  always_ff @(posedge clk or posedge rst) begin
    if (rst) tx_underrun <= 1'b0;
    else      tx_underrun <= 1'b0;
  end

  // Busy + tx_done pulse
  assign ev_tx_done = done_pulse;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state      <= IDLE;
      bytes_rem  <= 16'd0;
      have_cmd   <= 1'b0;
      tdata_r    <= '0;
      tkeep_r    <= '0;
      tlast_r    <= 1'b0;
      tvalid_r   <= 1'b0;
      rd_ptr     <= '0;
      done_pulse <= 1'b0;
      tx_busy    <= 1'b0;
    end else begin
      done_pulse <= 1'b0;

      // Latch a new TX_LEN command if idle; ignore if busy (simple policy)
      if (tx_len_we && !tx_busy) begin
        bytes_rem <= tx_len;
        have_cmd  <= (tx_len != 16'd0);
      end

      case (state)
        IDLE: begin
          tvalid_r <= 1'b0;
          tlast_r  <= 1'b0;
          tx_busy  <= (have_cmd); // go busy once a command exists
          if (have_cmd && mac_enable) begin
            // Only start when we have enough bytes for the first beat
            if (fifo_count >= (bytes_rem < AXIS_BYTES ? bytes_rem : AXIS_BYTES)) begin
              // assemble one beat
              int nbytes = (bytes_rem < AXIS_BYTES) ? bytes_rem : AXIS_BYTES;
              // pack nbytes from FIFO into tdata
              for (int b=0; b<AXIS_BYTES; b++) begin
                if (b < nbytes) begin
                  tdata_r[8*b +: 8] <= byte_mem[rd_ptr + b];
                  tkeep_r[b]        <= 1'b1;
                end else begin
                  tdata_r[8*b +: 8] <= 8'h00;
                  tkeep_r[b]        <= 1'b0;
                end
              end
              tlast_r  <= (nbytes == bytes_rem);
              tvalid_r <= 1'b1;
              state    <= STREAM;
            end
          end else begin
            tx_busy <= 1'b0;
          end
        end

        STREAM: begin
          // Wait for downstream ready; when handshake occurs, advance pointers/counters
          if (tvalid_r && m_axis_tready) begin
            // pop nbytes from FIFO
            int nbytes = 0;
            for (int b=0; b<AXIS_BYTES; b++) if (tkeep_r[b]) nbytes++;
            rd_ptr     <= rd_ptr + nbytes[$bits(rd_ptr)-1:0];
            fifo_count <= fifo_count - nbytes[CNT_W-1:0];
            bytes_rem  <= bytes_rem - nbytes[15:0];

            if (tlast_r) begin
              // frame completed
              tvalid_r   <= 1'b0;
              tlast_r    <= 1'b0;
              have_cmd   <= 1'b0;
              tx_busy    <= 1'b0;
              done_pulse <= 1'b1;
              state      <= IDLE;
            end else begin
              // Prepare the next beat; assert valid only when enough bytes are buffered
              if (fifo_count - nbytes >= AXIS_BYTES || (bytes_rem - nbytes) < AXIS_BYTES) begin
                int next_need = (bytes_rem - nbytes < AXIS_BYTES) ? (bytes_rem - nbytes) : AXIS_BYTES;
                if (next_need != 0 && (fifo_count - nbytes) >= next_need) begin
                  for (int b=0; b<AXIS_BYTES; b++) begin
                    if (b < next_need) begin
                      tdata_r[8*b +: 8] <= byte_mem[rd_ptr + b + nbytes];
                      tkeep_r[b]        <= 1'b1;
                    end else begin
                      tdata_r[8*b +: 8] <= 8'h00;
                      tkeep_r[b]        <= 1'b0;
                    end
                  end
                  tlast_r  <= (next_need == (bytes_rem - nbytes));
                  tvalid_r <= 1'b1;
                end else begin
                  // not enough buffered yet; deassert valid and wait
                  tvalid_r <= 1'b0;
                  tlast_r  <= 1'b0;
                end
              end else begin
                // not enough buffered yet; deassert valid and wait
                tvalid_r <= 1'b0;
                tlast_r  <= 1'b0;
              end
            end
          end else if (!tvalid_r) begin
            // Try to (re)assert valid if we have enough bytes buffered
            if (have_cmd && mac_enable && bytes_rem != 0) begin
              int need = (bytes_rem < AXIS_BYTES) ? bytes_rem : AXIS_BYTES;
              if (fifo_count >= need) begin
                for (int b=0; b<AXIS_BYTES; b++) begin
                  if (b < need) begin
                    tdata_r[8*b +: 8] <= byte_mem[rd_ptr + b];
                    tkeep_r[b]        <= 1'b1;
                  end else begin
                    tdata_r[8*b +: 8] <= 8'h00;
                    tkeep_r[b]        <= 1'b0;
                  end
                end
                tlast_r  <= (need == bytes_rem);
                tvalid_r <= 1'b1;
              end
            end
          end
        end
      endcase
    end
  end

endmodule

