// Ethernet slave agent, for driving and receving stimulus for DUT.


// Creating a class
class ethernet_slave_agent extends uvm_agent;
  // Factory registration
  `uvm_component_utils(ethernet_slave_agent)
  
  // Constructor
  function new(string name = "ethernet_slave_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction 
  
  // Driver, seqr, monitor handles
  ethernet_driver eth_drv;
  ethernet_sequencer eth_seqr;
  ethernet_monitor eth_mon;
  
  // Build phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    `uvm_info("ETH_AGENT", " Inside the build_phase", UVM_NONE);
    eth_drv = ethernet_driver::type_id::create("eth_drv", this);
    eth_seqr = ethernet_sequencer::type_id::create("eth_seqr", this);
    eth_mon = ethernet_monitor::type_id::create("eth_mon", this);
  endfunction
  
  // Connect phase
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    `uvm_info("ETH_AGENT", " Inside the connect_phase", UVM_NONE);
    eth_drv.seq_item_port.connect(eth_seqr.seq_item_export);
  endfunction
  
  
endclass