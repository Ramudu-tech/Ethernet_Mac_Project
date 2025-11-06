# AXI-side Ethernet Controller (GMII 1G) — Compile-Clean Setup

This bundle compiles the AXI-facing pieces you shared and stubs the MAC so you can get a clean compile without pulling the whole *verilog-ethernet* repo yet.

## Contents
- `axi4_eth_slave.sv` — AXI4-Full CSR + TX/RX windows and IRQ
- `tx_mm2axis_bridge.sv` — TX write-window → AXIS bridge
- `rx_axis2mm_bridge.sv` — RX AXIS → read-window bridge
- `fifo_sync.sv`, `irq_w1c.sv`, `lfsr.v` — helpers (some may be unused)
- `dut_eth_axi4_gmii.sv` — Top tying AXI slave + bridges + MAC
- `eth_mac_1g_gmii_fifo_stub.sv` — **temporary** stub for the MAC core
- `filelist.f` — compile order
- `Makefile` — quick compile targets

## Build
```sh
# Questa / ModelSim
make questa

# Verilator (C++ sim skeleton)
make verilator

# Icarus (SystemVerilog subset; may not cover all features)
make iverilog
```

Top: `dut_eth_axi4_gmii`

## Next steps (when you hook the real MAC)
1. Replace `eth_mac_1g_gmii_fifo_stub.sv` with the real `eth_mac_1g_gmii_fifo.v` from the verilog-ethernet repo.
2. Confirm the AXIS error-bit naming (`rx_axis_tuser[0]`) matches your copy; adjust in `dut_eth_axi4_gmii.sv` if needed.
3. Provide the 125 MHz `tx_clk`/`rx_clk` and synchronous resets from your TB.
4. Drive AXI transactions to the CSR/TX/RX windows per the address map in `axi4_eth_slave.sv`.

## Notes
- The stub intentionally drives `tx_axis_tready=1` and never produces RX traffic; it exists solely to satisfy elaboration.
- If you want a simple loopback for smoke tests, replace the stub logic with a trivial RX generator or hook TX→RX internally.
