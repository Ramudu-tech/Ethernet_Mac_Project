class axi_agent extends uvm_agent;
 `uvm_component_utils(axi_agent)

// constructor
 function new(string name,uvm_component parent);
  super.new(name,parent);
 endfunction

//declaring agent components
 axi_sequencer sqr;
 axi_driver    drv;
 axi_monitor   mon;
 
// build_phase
 function void build_phase(uvm_phase phase);
  super.build_phase(phase);

    if(get_is_active() == UVM_ACTIVE) begin
      sqr = axi_sequencer::type_id::create("sqr",this);   
      drv = axi_driver::type_id::create("drv",this);  
    end 

  mon = axi_monitor::type_id::create("mon",this);   

 endfunction

 // connect_phase
 function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);

    if(get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end 
    
 endfunction
 
endclass

