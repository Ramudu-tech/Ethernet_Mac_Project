`timescale 1ns/1ps
`default_nettype none
// -----------------------------------------------------------------------------
// Minimal stub for verilog-ethernet's eth_mac_1g_gmii_fifo
// Only the ports used by dut_eth_axi4_gmii are declared here.
// This is a *functional stub* for compile; replace with the real RTL from the repo.
// -----------------------------------------------------------------------------
module eth_mac_1g_gmii_fifo (
    // Clocks / resets
    input  wire        rx_clk,
    input  wire        rx_rst,
    input  wire        tx_clk,
    input  wire        tx_rst,

    // AXIS TX (to MAC from bridge)
    input  wire [7:0]  tx_axis_tdata,
    input  wire [0:0]  tx_axis_tkeep,
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
    output wire [0:0]  rx_axis_tuser,

    // GMII interface
    input  wire        gmii_rx_clk,
    input  wire [7:0]  gmii_rxd,
    input  wire        gmii_rx_dv,
    input  wire        gmii_rx_er,

    input  wire        gmii_tx_clk,
    output wire [7:0]  gmii_txd,
    output wire        gmii_tx_en,
    output wire        gmii_tx_er,

    // Simple config
    input  wire        tx_enable,
    input  wire        rx_enable,
    input  wire [7:0]  tx_ifg_delay,
    input  wire [47:0] mac_addr
);
    // -------------------------------------------------------------------------
    // Dummy behavior for compile: drive safe, deterministic values.
    // You can enhance this with simple pass-through if desired.
    // -------------------------------------------------------------------------
    assign tx_axis_tready = 1'b1;       // always ready (no backpressure)
    assign rx_axis_tdata  = 8'h00;
    assign rx_axis_tkeep  = 1'b1;
    assign rx_axis_tvalid = 1'b0;
    assign rx_axis_tlast  = 1'b0;
    assign rx_axis_tuser  = 1'b0;

    assign gmii_txd       = 8'h00;
    assign gmii_tx_en     = 1'b0;
    assign gmii_tx_er     = 1'b0;
endmodule
`default_nettype wire
