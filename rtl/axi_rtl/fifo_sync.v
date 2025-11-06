`timescale 1ns/1ps
`default_nettype none
// ============================================================================
// Simple synchronous FIFO
// - One clock, synchronous reset
// - Optional FWFT (first-word fall-through)
// - Exposes level, full/empty and almost_full/empty
// - Depth should be a power of two for best QoR (not required)
// ============================================================================
module fifo_sync #(
  parameter int WIDTH               = 32,
  parameter int DEPTH               = 512,   // entries
  parameter bit FWFT                = 1,     // 1 = rdata shows oldest word when !empty
  parameter int ALMOST_FULL_THRESH  = 4,     // assert when <= this many free
  parameter int ALMOST_EMPTY_THRESH = 4      // assert when <= this many used
)(
  input  logic               clk,
  input  logic               rst,    // sync reset

  // write side
  input  logic               wr_en,
  input  logic [WIDTH-1:0]   wdata,
  output logic               full,
  output logic               almost_full,

  // read side
  input  logic               rd_en,
  output logic [WIDTH-1:0]   rdata,
  output logic               empty,
  output logic               almost_empty,

  // status
  output logic [$clog2(DEPTH+1)-1:0] level
);

  localparam int PTR_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int COUNT_W = $clog2(DEPTH+1);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wptr, rptr;
  logic [COUNT_W-1:0] count;

  // write
  always_ff @(posedge clk) begin
    if (rst) begin
      wptr  <= '0;
    end else begin
      if (wr_en && !full) begin
        mem[wptr] <= wdata;
        wptr      <= wptr + 1'b1;
      end
    end
  end

  // read + output
  generate
    if (FWFT) begin : g_fwft
      // combinational read data (fall-through)
      assign rdata = mem[rptr];
      always_ff @(posedge clk) begin
        if (rst) begin
          rptr <= '0;
        end else if (rd_en && !empty) begin
          rptr <= rptr + 1'b1;
        end
      end
    end else begin : g_reg
      // registered read data (valid next cycle)
      always_ff @(posedge clk) begin
        if (rst) begin
          rptr  <= '0;
          rdata <= '0;
        end else if (rd_en && !empty) begin
          rdata <= mem[rptr];
          rptr  <= rptr + 1'b1;
        end
      end
    end
  endgenerate

  // occupancy
  always_ff @(posedge clk) begin
    if (rst) begin
      count <= '0;
    end else begin
      unique case ({(wr_en && !full), (rd_en && !empty)})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: /* hold */ ;
      endcase
    end
  end

  // flags
  assign level        = count;
  assign full         = (count == DEPTH[COUNT_W-1:0]);
  assign empty        = (count == '0);
  assign almost_full  = (DEPTH - count) <= ALMOST_FULL_THRESH[COUNT_W-1:0];
  assign almost_empty = (count <= ALMOST_EMPTY_THRESH[COUNT_W-1:0]);

endmodule
`default_nettype wire

