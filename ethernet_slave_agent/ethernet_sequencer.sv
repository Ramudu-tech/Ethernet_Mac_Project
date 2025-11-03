// Ethernet_sequencer controls the flow of request and response sequence items between sequences and the driver Sequencer and driver. Uses TLM Interface to communicate transactions

`include "uvm_macros.svh"
import uvm_pkg::*;


// Creating an ethernet_sequencer class
class ethernet_sequencer extends uvm_sequencer #(ethernet_frame_seq_item);
  
  // Factory registration
  `uvm_component_utils(ethernet_sequencer)
  
  // Constructor 
  function new(string name = "ethernet_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  // Build_phase
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  endfunction 
  
endclass