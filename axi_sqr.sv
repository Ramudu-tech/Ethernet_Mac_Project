class axi_sequencer extends uvm_sequencer#(axi_transaction);
 `uvm_component_utils(axi_sequencer)
 
 function new(string name, uvm_component parent);
   super.new(name,parent);
 endfunction
 
 function void build_phase(uvm_phase phase);
   super.build_phase(phase);
 endfunction

endclass
