# Simple compile Makefile for the AXI-side Ethernet controller (GMII 1G stubbed)
# Tools: Questa/ModelSim (vlog), Verilator (lint/sim), and iverilog (SV subset)
# Usage:
#   make questa
#   make verilator
#   make iverilog

TOP       ?= dut_eth_axi4_gmii
FILELIST  ?= filelist.f

# -------- Questa / ModelSim --------
questa:
	@mkdir -p work
	vlib work
	vlog -sv -timescale=1ns/1ps -work work -f $(FILELIST)

# -------- Verilator (lint or C++ sim skeleton) --------
verilator:
	verilator -sv --cc --top-module $(TOP) -f $(FILELIST) --exe --build \
	  -Wno-fatal -Wno-UNUSED -Wno-PINMISSING -Wno-ASSIGNDLY

# -------- Icarus (limited SV support) --------
iverilog:
	iverilog -g2012 -s $(TOP) -f $(FILELIST) -o build.out

clean:
	rm -rf work *.log *.out obj_dir

.PHONY: questa verilator iverilog clean
