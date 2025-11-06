`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// DUT top: AXI4-Full slave + TX/RX bridges + 1G GMII MAC (FIFO variant)
// - Single AXI4-Full slave for CSRs + TX/RX windows
// - TX: MM -> AXIS bridge (uses TX_LEN to emit TLAST)
// - RX: AXIS -> MM bridge (queues frame lengths, flags BAD_FCS)
// - MAC: eth_mac_1g_gmii_fifo from verilog-ethernet (AXIS 8-bit sides)
// - Fixed 1G simulation: provide 125 MHz tx_clk/rx_clk from TB
// ============================================================================

module dut_eth_axi4_gmii #(
  parameter int AXI_ADDR_WIDTH   = 16,
  parameter int AXI_DATA_WIDTH   = 32, // 32 or 64
  parameter int AXI_ID_WIDTH     = 4
)(
  // ---------------- AXI4-Full slave ----------------
  input  logic                           aclk,
  input  logic                           aresetn,

  input  logic [AXI_ID_WIDTH-1:0]        s_axi_awid,
  input  logic [AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
  input  logic [7:0]                     s_axi_awlen,
  input  logic [2:0]                     s_axi_awsize,
  input  logic [1:0]                     s_axi_awburst,
  input  logic                           s_axi_awvalid,
  output logic                           s_axi_awready,

  input  logic [AXI_DATA_WIDTH-1:0]      s_axi_wdata,
  input  logic [AXI_DATA_WIDTH/8-1:0]    s_axi_wstrb,
  input  logic                           s_axi_wlast,
  input  logic                           s_axi_wvalid,
  output logic                           s_axi_wready,

  output logic [AXI_ID_WIDTH-1:0]        s_axi_bid,
  output logic [1:0]                     s_axi_bresp,
  output logic                           s_axi_bvalid,
  input  logic                           s_axi_bready,

  input  logic [AXI_ID_WIDTH-1:0]        s_axi_arid,
  input  logic [AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
  input  logic [7:0]                     s_axi_arlen,
  input  logic [2:0]                     s_axi_arsize,
  input  logic [1:0]                     s_axi_arburst,
  input  logic                           s_axi_arvalid,
  output logic                           s_axi_arready,

  output logic [AXI_ID_WIDTH-1:0]        s_axi_rid,
  output logic [AXI_DATA_WIDTH-1:0]      s_axi_rdata,
  output logic [1:0]                     s_axi_rresp,
  output logic                           s_axi_rlast,
  output logic                           s_axi_rvalid,
  input  logic                           s_axi_rready,

  output logic                           irq,

  // ---------------- GMII clocks & pins ----------------
  input  logic                           tx_clk,   // 125 MHz (GTX) from TB
  input  logic                           tx_rst,   // sync to tx_clk (from TB)
  input  logic                           rx_clk,   // 125 MHz from TB (GMII RX)
  input  logic                           rx_rst,   // sync to rx_clk (from TB)

  output logic [7:0]                     gmii_txd,
  output logic                           gmii_tx_en,
  output logic                           gmii_tx_er,
  input  logic [7:0]                     gmii_rxd,
  input  logic                           gmii_rx_dv,
  input  logic                           gmii_rx_er
);

  // ==========================================================================
  // Internal wires between blocks
  // ==========================================================================

  // CTRL/CSRs
  logic              ctrl_mac_en;
  logic              ctrl_loopback;
  logic              ctrl_soft_reset_pulse;
  logic [47:0]       mac_addr;

  // TX command/status/events
  logic [15:0]       tx_len;
  logic              tx_len_we;
  logic              tx_busy, tx_underrun;
  logic [15:0]       tx_level;
  logic              ev_tx_done;

  // RX status/events
  logic              rx_frame_ready;
  logic [15:0]       rx_len;
  logic              rx_bad_fcs;
  logic              rx_overflow;
  logic [15:0]       rx_level;
  logic              ev_rx_done;

  // Aggregate error event into INT. You can refine this policy later.
  logic              ev_err = rx_overflow | tx_underrun | rx_bad_fcs;

  // AXI write window -> TX bridge
  logic [AXI_DATA_WIDTH-1:0]   txw_data;
  logic [AXI_DATA_WIDTH/8-1:0] txw_strb;
  logic                        txw_push;
  logic                        txw_ready;

  // RX bridge -> AXI read window
  logic [AXI_DATA_WIDTH-1:0]   rxw_data;
  logic                        rxw_valid;
  logic                        rxw_pop;

  // AXIS wires (MAC side is 8-bit for GMII)
  localparam int AXIS_W = 8;
  logic [AXIS_W-1:0]          tx_axis_tdata;
  logic [(AXIS_W/8)-1:0]      tx_axis_tkeep;
  logic                       tx_axis_tvalid;
  logic                       tx_axis_tready;
  logic                       tx_axis_tlast;
  logic                       tx_axis_tuser;   // not used; tie 0

  logic [AXIS_W-1:0]          rx_axis_tdata;
  logic [(AXIS_W/8)-1:0]      rx_axis_tkeep;
  logic                       rx_axis_tvalid;
  logic                       rx_axis_tready;
  logic                       rx_axis_tlast;
  logic [0:0]                 rx_axis_tuser;   // [0] = bad frame (repo-specific)

  // ==========================================================================
  // AXI4-Full slave (CSRs + TX/RX windows + IRQ)
  // ==========================================================================
  axi4_eth_slave #(
    .ADDR_WIDTH (AXI_ADDR_WIDTH),
    .DATA_WIDTH (AXI_DATA_WIDTH),
    .ID_WIDTH   (AXI_ID_WIDTH),
    .VERSION    (16'h0001),
    .ID_VALUE   (16'hE711)
  ) u_axi4_eth_slave (
    .aclk                (aclk),
    .aresetn             (aresetn),

    .s_axi_awid          (s_axi_awid),
    .s_axi_awaddr        (s_axi_awaddr),
    .s_axi_awlen         (s_axi_awlen),
    .s_axi_awsize        (s_axi_awsize),
    .s_axi_awburst       (s_axi_awburst),
    .s_axi_awvalid       (s_axi_awvalid),
    .s_axi_awready       (s_axi_awready),

    .s_axi_wdata         (s_axi_wdata),
    .s_axi_wstrb         (s_axi_wstrb),
    .s_axi_wlast         (s_axi_wlast),
    .s_axi_wvalid        (s_axi_wvalid),
    .s_axi_wready        (s_axi_wready),

    .s_axi_bid           (s_axi_bid),
    .s_axi_bresp         (s_axi_bresp),
    .s_axi_bvalid        (s_axi_bvalid),
    .s_axi_bready        (s_axi_bready),

    .s_axi_arid          (s_axi_arid),
    .s_axi_araddr        (s_axi_araddr),
    .s_axi_arlen         (s_axi_arlen),
    .s_axi_arsize        (s_axi_arsize),
    .s_axi_arburst       (s_axi_arburst),
    .s_axi_arvalid       (s_axi_arvalid),
    .s_axi_arready       (s_axi_arready),

    .s_axi_rid           (s_axi_rid),
    .s_axi_rdata         (s_axi_rdata),
    .s_axi_rresp         (s_axi_rresp),
    .s_axi_rlast         (s_axi_rlast),
    .s_axi_rvalid        (s_axi_rvalid),
    .s_axi_rready        (s_axi_rready),

    // CSRs out
    .ctrl_mac_en         (ctrl_mac_en),
    .ctrl_loopback       (ctrl_loopback),
    .ctrl_soft_reset_pulse(ctrl_soft_reset_pulse),
    .mac_addr            (mac_addr),

    .tx_len              (tx_len),
    .tx_len_we           (tx_len_we),

    // TX status in
    .tx_busy             (tx_busy),
    .tx_underrun         (tx_underrun),
    .tx_level            (tx_level),

    // RX status in
    .rx_frame_ready      (rx_frame_ready),
    .rx_len_i            (rx_len),
    .rx_bad_fcs          (rx_bad_fcs),
    .rx_overflow         (rx_overflow),
    .rx_level            (rx_level),

    // Events
    .ev_tx_done          (ev_tx_done),
    .ev_rx_done          (ev_rx_done),
    .ev_err              (ev_err),
    .irq                 (irq),

    // TX window out
    .txw_data            (txw_data),
    .txw_strb            (txw_strb),
    .txw_push            (txw_push),
    .txw_ready           (txw_ready),

    // RX window in
    .rxw_data            (rxw_data),
    .rxw_valid           (rxw_valid),
    .rxw_pop             (rxw_pop)
  );

  // ==========================================================================
  // TX bridge: MM → AXIS (to MAC)
  // ==========================================================================
  tx_mm2axis_bridge #(
    .DATA_WIDTH      (AXI_DATA_WIDTH),
    .AXIS_DATA_WIDTH (AXIS_W),
    .FIFO_BYTES      (4096)
  ) u_tx_bridge (
    .clk             (aclk),
    .rst             (~aresetn | ctrl_soft_reset_pulse),

    .mac_enable      (ctrl_mac_en),

    .tx_len          (tx_len),
    .tx_len_we       (tx_len_we),

    .tx_busy         (tx_busy),
    .tx_underrun     (tx_underrun),
    .tx_level        (tx_level),
    .ev_tx_done      (ev_tx_done),

    .txw_data        (txw_data),
    .txw_strb        (txw_strb),
    .txw_push        (txw_push),
    .txw_ready       (txw_ready),

    .m_axis_tdata    (tx_axis_tdata),
    .m_axis_tkeep    (tx_axis_tkeep),
    .m_axis_tvalid   (tx_axis_tvalid),
    .m_axis_tready   (tx_axis_tready),
    .m_axis_tlast    (tx_axis_tlast)
  );

  // ==========================================================================
  // RX bridge: AXIS (from MAC) → MM
  // ==========================================================================
  rx_axis2mm_bridge #(
    .DATA_WIDTH      (AXI_DATA_WIDTH),
    .AXIS_DATA_WIDTH (AXIS_W),
    .FIFO_BYTES      (4096),
    .LENFIFO_DEPTH   (8)
  ) u_rx_bridge (
    .clk                 (aclk),
    .rst                 (~aresetn | ctrl_soft_reset_pulse),

    .s_axis_tdata        (rx_axis_tdata),
    .s_axis_tkeep        (rx_axis_tkeep),
    .s_axis_tvalid       (rx_axis_tvalid),
    .s_axis_tready       (rx_axis_tready),
    .s_axis_tlast        (rx_axis_tlast),
    .s_axis_tuser_bad_fcs(rx_axis_tuser[0]), // NOTE: adjust if your repo exposes a differently named error bit

    .rx_frame_ready      (rx_frame_ready),
    .rx_len              (rx_len),
    .rx_bad_fcs          (rx_bad_fcs),
    .rx_overflow         (rx_overflow),
    .rx_level            (rx_level),

    .ev_rx_done          (ev_rx_done),

    .rxw_data            (rxw_data),
    .rxw_valid           (rxw_valid),
    .rxw_pop             (rxw_pop)
  );

  // ==========================================================================
  // MAC (verilog-ethernet): eth_mac_1g_gmii_fifo
  // - AXIS width = 8 bits on both RX/TX
  // - GMII pins connect directly
  // - Provide tx_clk/rx_clk from TB at 125 MHz; resets from TB
  // ==========================================================================
  // NOTE: Port names below follow common versions of the repo.
  // If your copy differs, align the names accordingly.
  assign tx_axis_tuser  = 1'b0; // we don't use per-frame error on TX

  eth_mac_1g_gmii_fifo u_mac (
    // Clocks / resets
    .rx_clk            (rx_clk),
    .rx_rst            (rx_rst),
    .tx_clk            (tx_clk),
    .tx_rst            (tx_rst),

    // AXIS TX (to MAC from bridge)
    .tx_axis_tdata     (tx_axis_tdata),
    .tx_axis_tkeep     (tx_axis_tkeep),
    .tx_axis_tvalid    (tx_axis_tvalid),
    .tx_axis_tready    (tx_axis_tready),
    .tx_axis_tlast     (tx_axis_tlast),
    .tx_axis_tuser     (tx_axis_tuser),

    // AXIS RX (from MAC to bridge)
    .rx_axis_tdata     (rx_axis_tdata),
    .rx_axis_tkeep     (rx_axis_tkeep),
    .rx_axis_tvalid    (rx_axis_tvalid),
    .rx_axis_tready    (rx_axis_tready),
    .rx_axis_tlast     (rx_axis_tlast),
    .rx_axis_tuser     (rx_axis_tuser),    // [0] often indicates bad frame/FCS

    // GMII interface
    .gmii_rx_clk       (rx_clk),           // some variants take explicit gmii clocks
    .gmii_rxd          (gmii_rxd),
    .gmii_rx_dv        (gmii_rx_dv),
    .gmii_rx_er        (gmii_rx_er),

    .gmii_tx_clk       (tx_clk),           // if the core expects gtx_clk/tx_clk
    .gmii_txd          (gmii_txd),
    .gmii_tx_en        (gmii_tx_en),
    .gmii_tx_er        (gmii_tx_er),

    // Configuration (tie-offs; expose later if you want)
    .tx_enable         (ctrl_mac_en),      // if present; otherwise tie 1'b1
    .rx_enable         (ctrl_mac_en),      // if present
    .tx_ifg_delay      (8'd0),             // default IFG
    .mac_addr          (mac_addr)
  );

endmodule

`default_nettype wire

