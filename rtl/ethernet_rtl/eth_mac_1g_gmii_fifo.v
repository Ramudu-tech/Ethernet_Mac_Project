`timescale 1ns/1ps
`default_nettype none
// -----------------------------------------------------------------------------
// Shim wrapper: eth_mac_1g_gmii_fifo
// Purpose: adapt your available non-FIFO MAC (eth_mac_1g_gmii) to the
//          FIFO-style port map expected by dut_eth_axi4_gmii.
// Notes:
//  - This *does not* implement large FIFOs. It adds a tiny 2-beat skid buffer
//    on RX to tolerate brief backpressure from the consumer. Sustained
//    backpressure can still drop data. For production, swap in the real
//    verilog-ethernet eth_mac_1g_gmii_fifo + deps.
//  - tkeep is ignored on TX and driven to 1'b1 on RX (8-bit datapath).
//  - gtx clock domain for MAC is taken from tx_clk/tx_rst inputs.
//  - gmii_{rx,tx}_clk are passed straight through.
// -----------------------------------------------------------------------------
module eth_mac_1g_gmii_fifo #(
    // pass-throughs for underlying MAC/PHY IF if needed later
    parameter TARGET            = "GENERIC",
    parameter IODDR_STYLE       = "IODDR2",
    parameter CLOCK_INPUT_STYLE = "BUFIO2"
)(
    // Clocks / resets (as expected by dut_eth_axi4_gmii)
    input  wire        rx_clk,   // UNUSED in this shim; logic RX clock comes from MAC
    input  wire        rx_rst,   // UNUSED in this shim
    input  wire        tx_clk,   // used as gtx_clk for the MAC
    input  wire        tx_rst,   // used as gtx_rst for the MAC

    // AXIS TX (to MAC from bridge)
    input  wire [7:0]  tx_axis_tdata,
    input  wire [0:0]  tx_axis_tkeep, // ignored (8-bit path implies keep = 1)
    input  wire        tx_axis_tvalid,
    output wire        tx_axis_tready,
    input  wire        tx_axis_tlast,
    input  wire        tx_axis_tuser,

    // AXIS RX (from MAC to bridge)
    output wire [7:0]  rx_axis_tdata,
    output wire [0:0]  rx_axis_tkeep,
    output wire        rx_axis_tvalid,
    input  wire        rx_axis_tready,
    output wire        rx_axis_tlast,
    output wire        rx_axis_tuser,

    // GMII interface
    input  wire        gmii_rx_clk,
    input  wire [7:0]  gmii_rxd,
    input  wire        gmii_rx_dv,
    input  wire        gmii_rx_er,

    input  wire        gmii_tx_clk,
    output wire [7:0]  gmii_txd,
    output wire        gmii_tx_en,
    output wire        gmii_tx_er,

    // Simple configuration
    input  wire        tx_enable,
    input  wire        rx_enable,
    input  wire [7:0]  tx_ifg_delay,
    input  wire [47:0] mac_addr     // unused by this MAC; kept for compatibility
);

    // ---------------------------------------------------------------------
    // Underlying non-FIFO MAC with GMII
    // ---------------------------------------------------------------------
    wire        mac_rx_clk;
    wire        mac_rx_rst;
    wire        mac_tx_clk;
    wire        mac_tx_rst;

    // MAC AXIS (RX side has no ready)
    wire [7:0]  mac_rx_tdata;
    wire        mac_rx_tvalid;
    wire        mac_rx_tlast;
    wire        mac_rx_tuser;

    // TX side handshake goes through
    wire        mac_tx_tready;

    // Status (unused here)
    wire        mac_tx_error_underflow;
    wire        mac_rx_error_bad_frame;
    wire        mac_rx_error_bad_fcs;
    wire [1:0]  mac_speed;

    eth_mac_1g_gmii #(
        .TARGET            (TARGET),
        .IODDR_STYLE       (IODDR_STYLE),
        .CLOCK_INPUT_STYLE (CLOCK_INPUT_STYLE),
        .ENABLE_PADDING    (1),
        .MIN_FRAME_LENGTH  (64)
    ) u_mac (
        .gtx_clk           (tx_clk),        // use provided tx_clk as MAC logic clock
        .gtx_rst           (tx_rst),

        // MAC exposes these as outputs; we tap them for local logic
        .rx_clk            (mac_rx_clk),
        .rx_rst            (mac_rx_rst),
        .tx_clk            (mac_tx_clk),
        .tx_rst            (mac_tx_rst),

        // AXIS TX (input to MAC)
        .tx_axis_tdata     (tx_axis_tdata),
        .tx_axis_tvalid    (tx_axis_tvalid),
        .tx_axis_tready    (tx_axis_tready),
        .tx_axis_tlast     (tx_axis_tlast),
        .tx_axis_tuser     (tx_axis_tuser),

        // AXIS RX (output from MAC)
        .rx_axis_tdata     (mac_rx_tdata),
        .rx_axis_tvalid    (mac_rx_tvalid),
        .rx_axis_tlast     (mac_rx_tlast),
        .rx_axis_tuser     (mac_rx_tuser),

        // GMII pins
        .gmii_rx_clk       (gmii_rx_clk),
        .gmii_rxd          (gmii_rxd),
        .gmii_rx_dv        (gmii_rx_dv),
        .gmii_rx_er        (gmii_rx_er),
        .mii_tx_clk        (1'b0),          // GMII only
        .gmii_tx_clk       (gmii_tx_clk),
        .gmii_txd          (gmii_txd),
        .gmii_tx_en        (gmii_tx_en),
        .gmii_tx_er        (gmii_tx_er),

        // Status
        .tx_error_underflow(mac_tx_error_underflow),
        .rx_error_bad_frame(mac_rx_error_bad_frame),
        .rx_error_bad_fcs  (mac_rx_error_bad_fcs),
        .speed             (mac_speed),

        // Configuration
        .cfg_ifg           (tx_ifg_delay),
        .cfg_tx_enable     (tx_enable),
        .cfg_rx_enable     (rx_enable)
    );

    // ---------------------------------------------------------------------
    // TX path: simple pass-through (tkeep ignored)
    // ---------------------------------------------------------------------
    // MAC provides proper tx_axis_tready; nothing to do here.
    // tkeep is not used for 8-bit path and is ignored.

    // ---------------------------------------------------------------------
    // RX path: tiny 2-beat skid buffer to tolerate brief backpressure
    // ---------------------------------------------------------------------
    // Interface expectations from wrapper side
    assign rx_axis_tkeep = 1'b1; // 8-bit datapath => always 1

    // Stage 0: capture from MAC
    reg  [7:0] s0_data;
    reg        s0_last;
    reg        s0_user;
    reg        s0_valid;

    // Stage 1: output stage
    reg  [7:0] s1_data;
    reg        s1_last;
    reg        s1_user;
    reg        s1_valid;

    // Drop control when both stages occupied and more data arrives
    reg        drop_frame;  // when asserted, ignore until end-of-frame

    // Capture from MAC (no ready available from MAC)
    always @(posedge mac_rx_clk) begin
        if (mac_rx_rst) begin
            s0_valid   <= 1'b0;
            s1_valid   <= 1'b0;
            drop_frame <= 1'b0;
        end else begin
            // default: no change

            // Output stage handshake
            if (s1_valid && rx_axis_tready) begin
                s1_valid <= 1'b0;
            end

            // Move s0 -> s1 if s1 free
            if (!s1_valid && s0_valid) begin
                s1_valid <= 1'b1;
                s1_data  <= s0_data;
                s1_last  <= s0_last;
                s1_user  <= s0_user;
                s0_valid <= 1'b0;
            end

            // Accept from MAC when valid and not dropping
            if (mac_rx_tvalid) begin
                if (drop_frame) begin
                    // keep dropping until end-of-frame
                    if (mac_rx_tlast)
                        drop_frame <= 1'b0;
                end else begin
                    if (!s0_valid) begin
                        s0_valid <= 1'b1;
                        s0_data  <= mac_rx_tdata;
                        s0_last  <= mac_rx_tlast;
                        s0_user  <= mac_rx_tuser;
                    end else if (!s1_valid) begin
                        // bypass into stage 1 if s0 busy
                        s1_valid <= 1'b1;
                        s1_data  <= mac_rx_tdata;
                        s1_last  <= mac_rx_tlast;
                        s1_user  <= mac_rx_tuser;
                    end else begin
                        // both stages full -> overflow: drop remainder of frame
                        drop_frame <= 1'b1;
                    end
                end
            end
        end
    end

    assign rx_axis_tvalid = s1_valid;
    assign rx_axis_tdata  = s1_data;
    assign rx_axis_tlast  = s1_last;
    assign rx_axis_tuser  = s1_user;

endmodule

`default_nettype wire
