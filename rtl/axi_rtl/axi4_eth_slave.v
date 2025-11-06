// ============================================================================
// AXI4-Full Ethernet Slave (CSRs + TX/RX FIFO windows)
// - Single AXI4-Full slave used for both control/status and frame data
// - INCR bursts supported to TX/RX windows
// - CSRs are single-beat accesses (awlen/arlen must be 0 for CSR region)
// - Interrupts: W1C status + enables; single IRQ output
// - No MDIO here (leave reserved space if desired)
// ----------------------------------------------------------------------------
// Address map (byte offsets from BASE):
//   0x000 : ID_VERSION        (RO)  [31:16]=ID, [15:0]=VER
//   0x004 : CTRL              (RW)  [0]=MAC_EN, [1]=LOOPBACK, [2]=SOFT_RST (W1P)
//   0x008 : MAC_ADDR_L        (RW)  31:0
//   0x00C : MAC_ADDR_H        (RW)  15:0 (LSBs)
//   0x010 : TX_LEN            (WO)  Byte count for next TX frame (LEN mode)
//   0x014 : TX_STATUS         (RO)  {BUSY, UNDERRUN, TX_LEVEL[15:0]}
//   0x018 : RX_STATUS         (RO)  {FRAME_RDY, BAD_FCS, OVFL, LEN[15:0], RX_LEVEL[15:0]}
//   0x01C : INT_STATUS        (W1C) {RX_DONE, TX_DONE, ERR}
//   0x020 : INT_ENABLE        (RW)  {RX_DONE, TX_DONE, ERR}
//   0x024..0x02C : reserved (MDIO placeholders if needed)
//
//   0x400 : TX_FIFO_WIN (WO)  Write INCR bursts of frame bytes (WSTRB honored)
//   0x800 : RX_FIFO_WIN (RO)  Read  INCR bursts of frame bytes
// ----------------------------------------------------------------------------
// Notes:
// - DATA_WIDTH must be a power-of-two bytes. SIZE must match (log2(DATA_BYTES)).
// - TX window writes fan out as word pushes with byte enables to the TX bridge/FIFO.
// - RX window reads pull words from RX bridge/FIFO.
// - One in-flight read and one in-flight write supported (common + simple).
// ============================================================================

module axi4_eth_slave #(
  parameter int ADDR_WIDTH = 16,
  parameter int DATA_WIDTH = 32,   // 32 or 64 typical
  parameter int ID_WIDTH   = 4,
  parameter int VERSION    = 16'h0001,
  parameter int ID_VALUE   = 16'hE711  // "ETH1"ish
) (
  input  logic                       aclk,
  input  logic                       aresetn,

  // ---------------- AXI4-Full Slave ----------------
  // Write address
  input  logic [ID_WIDTH-1:0]        s_axi_awid,
  input  logic [ADDR_WIDTH-1:0]      s_axi_awaddr,
  input  logic [7:0]                 s_axi_awlen,
  input  logic [2:0]                 s_axi_awsize,
  input  logic [1:0]                 s_axi_awburst,
  input  logic                       s_axi_awvalid,
  output logic                       s_axi_awready,

  // Write data
  input  logic [DATA_WIDTH-1:0]      s_axi_wdata,
  input  logic [DATA_WIDTH/8-1:0]    s_axi_wstrb,
  input  logic                       s_axi_wlast,
  input  logic                       s_axi_wvalid,
  output logic                       s_axi_wready,

  // Write response
  output logic [ID_WIDTH-1:0]        s_axi_bid,
  output logic [1:0]                 s_axi_bresp,
  output logic                       s_axi_bvalid,
  input  logic                       s_axi_bready,

  // Read address
  input  logic [ID_WIDTH-1:0]        s_axi_arid,
  input  logic [ADDR_WIDTH-1:0]      s_axi_araddr,
  input  logic [7:0]                 s_axi_arlen,
  input  logic [2:0]                 s_axi_arsize,
  input  logic [1:0]                 s_axi_arburst,
  input  logic                       s_axi_arvalid,
  output logic                       s_axi_arready,

  // Read data
  output logic [ID_WIDTH-1:0]        s_axi_rid,
  output logic [DATA_WIDTH-1:0]      s_axi_rdata,
  output logic [1:0]                 s_axi_rresp,
  output logic                       s_axi_rlast,
  output logic                       s_axi_rvalid,
  input  logic                       s_axi_rready,

  // ---------------- CSR outputs / inputs ----------------
  // CTRL
  output logic                       ctrl_mac_en,
  output logic                       ctrl_loopback,
  output logic                       ctrl_soft_reset_pulse, // W1P pulse (1 clk)
  // MAC address
  output logic [47:0]                mac_addr,
  // TX length command
  output logic [15:0]                tx_len,
  output logic                       tx_len_we,            // strobe when TX_LEN written

  // TX status inputs from TX bridge
  input  logic                       tx_busy,
  input  logic                       tx_underrun,
  input  logic [15:0]                tx_level,

  // RX status inputs from RX bridge
  input  logic                       rx_frame_ready,
  input  logic [15:0]                rx_len_i,
  input  logic                       rx_bad_fcs,
  input  logic                       rx_overflow,
  input  logic [15:0]                rx_level,

  // Interrupt event inputs (edge-detected inside)
  input  logic                       ev_tx_done,
  input  logic                       ev_rx_done,
  input  logic                       ev_err,
  output logic                       irq,

  // ---------------- Data windows to bridges ----------------
  // TX write window -> push to TX MM FIFO/bridge
  output logic [DATA_WIDTH-1:0]      txw_data,
  output logic [DATA_WIDTH/8-1:0]    txw_strb,
  output logic                       txw_push,     // one beat accepted
  input  logic                       txw_ready,    // backpressure toward AXI wready

  // RX read window <- pop from RX MM FIFO/bridge
  input  logic [DATA_WIDTH-1:0]      rxw_data,
  input  logic                       rxw_valid,    // data available
  output logic                       rxw_pop       // one beat consumed
);

  // ------------------- Local params / helpers -------------------
  localparam int BYTES     = DATA_WIDTH/8;
  localparam int SIZE_CODE = $clog2(BYTES);
  localparam [ADDR_WIDTH-1:0] OFFS_ID_VERSION   = 'h000;
  localparam [ADDR_WIDTH-1:0] OFFS_CTRL         = 'h004;
  localparam [ADDR_WIDTH-1:0] OFFS_MAC_ADDR_L   = 'h008;
  localparam [ADDR_WIDTH-1:0] OFFS_MAC_ADDR_H   = 'h00C;
  localparam [ADDR_WIDTH-1:0] OFFS_TX_LEN       = 'h010;
  localparam [ADDR_WIDTH-1:0] OFFS_TX_STATUS    = 'h014;
  localparam [ADDR_WIDTH-1:0] OFFS_RX_STATUS    = 'h018;
  localparam [ADDR_WIDTH-1:0] OFFS_INT_STATUS   = 'h01C;
  localparam [ADDR_WIDTH-1:0] OFFS_INT_ENABLE   = 'h020;

  localparam [ADDR_WIDTH-1:0] BASE_TX_WIN       = 'h400;
  localparam [ADDR_WIDTH-1:0] BASE_RX_WIN       = 'h800;

  // Regions by [11:10] if you stick to the suggested map (0x000,0x400,0x800):
  // 00x = CSR, 01x = TX window, 10x = RX window
  function automatic logic [1:0] region_of (input logic [ADDR_WIDTH-1:0] a);
    if (a[11:10] == 2'b01) return 2'd1;      // TX
    else if (a[11:10] == 2'b10) return 2'd2; // RX
    else return 2'd0;                        // CSR
  endfunction

  // ------------------- CSRs -------------------
  logic [31:0] id_version;
  assign id_version = {ID_VALUE, VERSION};

  // CTRL
  logic [2:0]  ctrl_reg; // [0]=mac_en [1]=loopback [2]=soft_rst(W1P)
  assign ctrl_mac_en  = ctrl_reg[0];
  assign ctrl_loopback= ctrl_reg[1];

  // soft reset pulse generation
  logic soft_rst_pulse_q;
  assign ctrl_soft_reset_pulse = soft_rst_pulse_q;

  // MAC address
  logic [31:0] mac_addr_l;
  logic [15:0] mac_addr_h;
  assign mac_addr = {mac_addr_h, mac_addr_l};

  // TX_LEN (write-only command, but we retain the last value so reads are harmless)
  logic [15:0] tx_len_q;
  assign tx_len = tx_len_q;
  logic        tx_len_we_q;

  // INT
  typedef struct packed {logic err, tx_done, rx_done;} int_bits_t;
  int_bits_t int_enable, int_status;

  // Sticky W1C status update (from events)
  logic ev_tx_done_q, ev_rx_done_q, ev_err_q;
  logic ev_tx_done_rise, ev_rx_done_rise, ev_err_rise;

  // IRQ output
  assign irq = (int_status.rx_done & int_enable.rx_done)
             | (int_status.tx_done & int_enable.tx_done)
             | (int_status.err     & int_enable.err);

  // TX_STATUS and RX_STATUS assembly (read-only views)
  logic [31:0] tx_status_ro;
  logic [31:0] rx_status_ro;
  always_comb begin
    tx_status_ro = 32'b0;
    tx_status_ro[31]    = tx_busy;
    tx_status_ro[30]    = tx_underrun;
    tx_status_ro[15:0]  = tx_level;
  end
  always_comb begin
    rx_status_ro = 32'b0;
    rx_status_ro[31]    = rx_frame_ready;
    rx_status_ro[30]    = rx_bad_fcs;
    rx_status_ro[29]    = rx_overflow;
    rx_status_ro[28:16] = rx_len_i;
    rx_status_ro[15:0]  = rx_level;
  end

  // ------------------- Event edge detectors -------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      {ev_tx_done_q, ev_rx_done_q, ev_err_q} <= '0;
    end else begin
      ev_tx_done_q <= ev_tx_done;
      ev_rx_done_q <= ev_rx_done;
      ev_err_q     <= ev_err;
    end
  end
  assign ev_tx_done_rise =  ev_tx_done & ~ev_tx_done_q;
  assign ev_rx_done_rise =  ev_rx_done & ~ev_rx_done_q;
  assign ev_err_rise     =  ev_err     & ~ev_err_q;

  // Latched W1C status
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      int_status <= '{default:0};
    end else begin
      // Set on event rises
      if (ev_rx_done_rise) int_status.rx_done <= 1'b1;
      if (ev_tx_done_rise) int_status.tx_done <= 1'b1;
      if (ev_err_rise)     int_status.err     <= 1'b1;
    end
  end

  // ------------------- AXI write channel -------------------
  typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_e;
  wr_state_e wr_state;

  logic [ID_WIDTH-1:0]   awid_q;
  logic [ADDR_WIDTH-1:0] awaddr_q;
  logic [7:0]            awlen_q;    // beats-1
  logic [2:0]            awsize_q;   // must == SIZE_CODE
  logic [1:0]            awburst_q;  // must be INCR(01)
  logic [1:0]            aw_region_q;// 0=CSR,1=TX,2=RX(invalid for write)
  logic [7:0]            wr_beats_rem;
  logic                  wr_error;
  logic [7:0]            bytev;

  // default
  assign s_axi_awready = (wr_state == WR_IDLE);

  // WREADY depends on region
  always_comb begin
    unique case (aw_region_q)
      2'd1: s_axi_wready = (wr_state == WR_DATA) && txw_ready; // TX window backpressure
      default: s_axi_wready = (wr_state == WR_DATA);           // CSR: always ready
    endcase
  end

  // forward TX window writes
  assign txw_data = s_axi_wdata;
  assign txw_strb = s_axi_wstrb;
  assign txw_push = (wr_state == WR_DATA) && (aw_region_q == 2'd1) &&
                    s_axi_wvalid && s_axi_wready;

  // write FSM
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      wr_state   <= WR_IDLE;
      awid_q     <= '0;
      awaddr_q   <= '0;
      awlen_q    <= '0;
      awsize_q   <= '0;
      awburst_q  <= '0;
      aw_region_q<= '0;
      wr_beats_rem <= '0;
      wr_error   <= 1'b0;

      s_axi_bid   <= '0;
      s_axi_bresp <= 2'b00; // OKAY
      s_axi_bvalid<= 1'b0;

      // CSRs
      ctrl_reg          <= 3'b000;
      soft_rst_pulse_q  <= 1'b0;
      mac_addr_l        <= 32'h0;
      mac_addr_h        <= 16'h0;
      tx_len_q          <= 16'h0;
      tx_len_we_q       <= 1'b0;
      int_enable        <= '{default:0};
    end else begin
      // defaults
      soft_rst_pulse_q <= 1'b0;
      tx_len_we_q      <= 1'b0;

      // W1C clear for INT_STATUS handled below on CSR write
      // FSM
      case (wr_state)
        WR_IDLE: begin
          s_axi_bvalid <= 1'b0;
          wr_error     <= 1'b0;
          if (s_axi_awvalid && s_axi_awready) begin
            awid_q      <= s_axi_awid;
            awaddr_q    <= s_axi_awaddr;
            awlen_q     <= s_axi_awlen;
            awsize_q    <= s_axi_awsize;
            awburst_q   <= s_axi_awburst;
            aw_region_q <= region_of(s_axi_awaddr);
            wr_beats_rem<= s_axi_awlen; // beats-1 counter
            wr_state    <= WR_DATA;

            // protocol checks
            if (s_axi_awsize != SIZE_CODE) wr_error <= 1'b1;
            if (s_axi_awburst != 2'b01)    wr_error <= 1'b1; // only INCR
            if (region_of(s_axi_awaddr)==2'd2) wr_error <= 1'b1; // cannot write RX window
            // CSR writes must be single-beat
            if (region_of(s_axi_awaddr)==2'd0 && s_axi_awlen != 8'd0) wr_error <= 1'b1;
          end
        end

        WR_DATA: begin
          if (s_axi_wvalid && s_axi_wready) begin
            // Handle CSR register writes
            if (aw_region_q == 2'd0) begin
              unique case (awaddr_q & 'h3FC) // mask to 32B boundary window
                OFFS_CTRL: begin
                  // apply WSTRB
                  for (int i=0;i<BYTES;i++) begin
                    if (s_axi_wstrb[i]) begin
		      bytev = s_axi_wdata[8*i +: 8];
                      if (i==0) begin
                        // bits [7:0]: [2]=soft_rst W1P, [1]=loopback, [0]=mac_en
                        ctrl_reg[0] <= bytev[0];
                        ctrl_reg[1] <= bytev[1];
                        if (bytev[2]) soft_rst_pulse_q <= 1'b1; // write-1 pulse
                      end
                    end
                  end
                end
                OFFS_MAC_ADDR_L: begin
                  for (int i=0;i<BYTES;i++)
                    if (s_axi_wstrb[i]) mac_addr_l[8*i +: 8] <= s_axi_wdata[8*i +: 8];
                end
                OFFS_MAC_ADDR_H: begin
                  for (int i=0;i<2;i++) // only low 2 bytes valid
                    if (s_axi_wstrb[i]) mac_addr_h[8*i +: 8] <= s_axi_wdata[8*i +: 8];
                end
                OFFS_TX_LEN: begin
                  for (int i=0;i<2;i++)
                    if (s_axi_wstrb[i]) tx_len_q[8*i +: 8] <= s_axi_wdata[8*i +: 8];
                  tx_len_we_q <= 1'b1;
                end
                OFFS_INT_ENABLE: begin
                  // {---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ERR TXD RXD}
                  logic [31:0] v = s_axi_wdata;
                  if (s_axi_wstrb[0]) begin
                    int_enable.rx_done <= v[0];
                    int_enable.tx_done <= v[1];
                    int_enable.err     <= v[2];
                  end
                end
                OFFS_INT_STATUS: begin
                  // W1C: clear bits written as '1'
                  logic [31:0] v = s_axi_wdata;
                  if (s_axi_wstrb[0]) begin
                    if (v[0]) int_status.rx_done <= 1'b0;
                    if (v[1]) int_status.tx_done <= 1'b0;
                    if (v[2]) int_status.err     <= 1'b0;
                  end
                end
                default: begin
                  // reserved: ignore
                end
              endcase
            end

            // decrement beats
            if (wr_beats_rem != 0)
              wr_beats_rem <= wr_beats_rem - 1;

            // last-beat checks
            if (wr_beats_rem == 0) begin
              // expect WLAST on last
              if (!s_axi_wlast) wr_error <= 1'b1;
              wr_state <= WR_RESP;
              s_axi_bid   <= awid_q;
              s_axi_bresp <= wr_error ? 2'b10 /*SLVERR*/ : 2'b00 /*OKAY*/;
              s_axi_bvalid<= 1'b1;
            end
          end
        end

        WR_RESP: begin
          if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
            wr_state     <= WR_IDLE;
          end
        end
      endcase
    end
  end

  // ------------------- AXI read channel -------------------
  typedef enum logic [1:0] {RD_IDLE, RD_STREAM, RD_RESP} rd_state_e;
  rd_state_e rd_state;

  logic [ID_WIDTH-1:0]   arid_q;
  logic [ADDR_WIDTH-1:0] araddr_q;
  logic [7:0]            arlen_q;
  logic [2:0]            arsize_q;
  logic [1:0]            arburst_q;
  logic [1:0]            ar_region_q;
  logic [7:0]            rd_beats_rem;
  logic                  rd_error;

  assign s_axi_arready = (rd_state == RD_IDLE);

  // drive read data defaults
  always_comb begin
    s_axi_rresp = rd_error ? 2'b10 /*SLVERR*/ : 2'b00 /*OKAY*/;
    s_axi_rid   = arid_q;
    s_axi_rlast = (rd_state == RD_STREAM) && (rd_beats_rem == 8'd0) && s_axi_rvalid && s_axi_rready;
  end

  // when streaming RX window, rvalid follows rxw_valid; when CSR, rvalid is simple
  logic csr_read_pending;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      rd_state       <= RD_IDLE;
      arid_q         <= '0;
      araddr_q       <= '0;
      arlen_q        <= '0;
      arsize_q       <= '0;
      arburst_q      <= '0;
      ar_region_q    <= '0;
      rd_beats_rem   <= '0;
      rd_error       <= 1'b0;
      s_axi_rdata    <= '0;

      s_axi_rvalid   <= 1'b0;
      csr_read_pending <= 1'b0;
      rxw_pop        <= 1'b0;
    end else begin
      // default
      rxw_pop <= 1'b0;

      case (rd_state)
        RD_IDLE: begin
          s_axi_rvalid <= 1'b0;
          rd_error     <= 1'b0;
          if (s_axi_arvalid && s_axi_arready) begin
            arid_q      <= s_axi_arid;
            araddr_q    <= s_axi_araddr;
            arlen_q     <= s_axi_arlen;
            arsize_q    <= s_axi_arsize;
            arburst_q   <= s_axi_arburst;
            ar_region_q <= region_of(s_axi_araddr);
            rd_beats_rem<= s_axi_arlen;

            // protocol checks
            if (s_axi_arsize != SIZE_CODE) rd_error <= 1'b1;
            if (s_axi_arburst != 2'b01)    rd_error <= 1'b1; // INCR only
            if (region_of(s_axi_araddr)==2'd0 && s_axi_arlen != 8'd0) rd_error <= 1'b1; // CSR single-beat

            if (region_of(s_axi_araddr)==2'd2) begin
              // RX window streaming
              rd_state <= RD_STREAM;
            end else begin
              // CSR read
              rd_state <= RD_RESP;
              csr_read_pending <= 1'b1;
            end
          end
        end

        RD_STREAM: begin
          // Wait until data valid to present RVALID
          if (!s_axi_rvalid) begin
            if (rxw_valid && !rd_error) begin
              s_axi_rvalid <= 1'b1;
              s_axi_rdata  <= rxw_data;
            end
          end else begin
            // Handshake beat
            if (s_axi_rvalid && s_axi_rready) begin
              // pop one word from RX window source
              rxw_pop <= 1'b1;

              if (rd_beats_rem == 8'd0) begin
                // last beat done
                s_axi_rvalid <= 1'b0;
                rd_state     <= RD_IDLE;
              end else begin
                rd_beats_rem <= rd_beats_rem - 1;
                // next beat: present data on next cycle when rxw_valid
                s_axi_rvalid <= 1'b0; // deassert and wait for next rxw_valid
              end
            end
          end
        end

        RD_RESP: begin
          // Single-beat CSR read
          if (csr_read_pending) begin
            csr_read_pending <= 1'b0;
            s_axi_rvalid <= 1'b1;

            // mux CSR data
            unique case (araddr_q & 'h3FC)
              OFFS_ID_VERSION: s_axi_rdata <= id_version;
              OFFS_CTRL:       s_axi_rdata <= {29'b0, 1'b0 /*soft rst is pulse*/, ctrl_loopback, ctrl_mac_en};
              OFFS_MAC_ADDR_L: s_axi_rdata <= mac_addr_l;
              OFFS_MAC_ADDR_H: s_axi_rdata <= {16'h0, mac_addr_h};
              OFFS_TX_LEN:     s_axi_rdata <= {16'h0, tx_len_q};
              OFFS_TX_STATUS:  s_axi_rdata <= tx_status_ro;
              OFFS_RX_STATUS:  s_axi_rdata <= rx_status_ro;
              OFFS_INT_STATUS: s_axi_rdata <= {29'b0, int_status.err, int_status.tx_done, int_status.rx_done};
              OFFS_INT_ENABLE: s_axi_rdata <= {29'b0, int_enable.err, int_enable.tx_done, int_enable.rx_done};
              default:         s_axi_rdata <= '0;
            endcase
          end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
            rd_state     <= RD_IDLE;
          end
        end
      endcase
    end
  end

  // ------------------- Outputs for strobes -------------------
  assign tx_len_we = tx_len_we_q;

endmodule

