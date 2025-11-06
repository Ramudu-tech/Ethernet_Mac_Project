`timescale 1ns/1ps
`default_nettype none
// ============================================================================
/* Generic W1C interrupt block
 * - Latches event pulses into sticky status bits.
 * - Write-1-to-Clear interface for software.
 * - Enable mask controls which status bits OR into 'irq'.
 *
 * Typical hookup:
 *   status <= status | event_pulse;
 *   if (w1c[i]) status[i] <= 0;
 */
// ============================================================================
module irq_w1c #(
  parameter int NUM = 3  // number of interrupt sources
)(
  input  logic                 clk,
  input  logic                 rst,          // sync reset

  input  logic [NUM-1:0]       event_pulse,  // 1-cycle set pulses
  input  logic [NUM-1:0]       enable,       // mask bits
  input  logic [NUM-1:0]       w1c,          // software clear (1 clears bit)

  output logic [NUM-1:0]       status,       // sticky status
  output logic                 irq           // OR(status & enable)
);
  always_ff @(posedge clk) begin
    if (rst) begin
      status <= '0;
    end else begin
      // set on pulses
      status <= (status | event_pulse);
      // clear on W1C
      status <= status & ~w1c;
    end
  end

  assign irq = |(status & enable);

endmodule
`default_nettype wire

