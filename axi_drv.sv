class axi_driver extends uvm_driver#(axi_transaction);
virtual interface vif;
`uvm_component_utils(axi_driver)

function new(string name,uvm_component parent);
 super.new(name,parent);
endfunction

function void build_phase(uvm_phase phase);
 super.build_phase(phase);
 if(!uvm_config_db#(virtual interface)::get(this,"","vif",vif)) begin
	 `uvm_error("AXI_DRIVER","Virtual interface is not received")
 end
endfunction

task run_phase(uvm_phase phase);
  axi_transaction tr;
forever begin
	seq_item_port.get_next_item(tr);
              if(tr.burst_type == READ) begin
	         drive_read(tr);
              end 
	      if(tr.burst_type == WRITE) begin
	         drive_write(tr);
              end
	seq_item_port.item_done();
end
endtask

task drive_write(axi_transaction tr);
// Write Address Phase
 `uvm_info("DRIVER - WRITE ADDRESS BUS","",UVM_HIGH);
    @(posedge vif.aclk);
    vif.awid     <= tr.awid;         
    vif.awaddr   <= tr.awaddr;       
    vif.awsize   <= tr.awsize;       
    vif.awburst  <= tr.awburst;      
    vif.awcache  <= tr.awcache;      
    vif.awprot   <= tr.awprot;       
    vif.awlen    <= tr.awlen;        
    vif.awlock   <= tr.awlock;       
    vif.awqos    <= tr.awqos;        
    vif.awregion <= tr.awregion;     
    vif.awuser   <= tr.awuser;      
    vif.awvalid  <= 1;  
    @(posedge vif.aclk iff vif.awready);
    vif.awvalid  <= 0;  

// Write Data Phase
foreach (tr.wdata[i]) begin
 `uvm_info("DRIVER - WRITE DATA BUS","",UVM_HIGH);
    @(posedge vif.aclk);
    vif.wdata  <= tr.wdata[i];
    vif.wstrb  <= tr.wstrb[i];
    vif.wlast  <= (i == tr.awlen);
    vif.wuser  <= tr.wuser;
    vif.wvalid <= 1;
    @(posedge vif.aclk iff vif.wready);
    vif.wvalid <= 0;
end
// Write Response Phase
  `uvm_info("DRIVER - WRITE RESPONSE BUS","",UVM_HIGH);
    vif.bready <= 1;
    @(posedge vif.aclk iff vif.bvalid);
    `uvm_info("WRITE_RESP", $sformatf("BID=%0d BRESP=%0b", vif.bid, vif.bresp), UVM_MEDIUM);
    vif.bready <= 0;
endtask

task drive_read(axi_transaction tr);
// Read Address Phase
 `uvm_info("DRIVER - READ ADDRESS BUS","",UVM_HIGH);
@(posedge vif.aclk);
    vif.arid     <= tr.arid;
    vif.araddr   <= tr.araddr;
    vif.arsize   <= tr.arsize;
    vif.arburst  <= tr.arburst;
    vif.arcache  <= tr.arcache;
    vif.arprot   <= tr.arprot;
    vif.arlen    <= tr.arlen;
    vif.arlock   <= tr.arlock;
    vif.arqos    <= tr.arqos;
    vif.arregion <= tr.arregion;
    vif.aruser   <= tr.aruser;
    vif.arvalid  <= 1;
    @(posedge vif.aclk iff vif.arready);
    vif.arvalid  <= 0;


 // Allocate memory for read data arrays
    tr.rdata = new[tr.arlen + 1];
    tr.rresp = new[tr.arlen + 1];

    // Read Data Phase
  `uvm_info("DRIVER - READ RESPONSE BUS","",UVM_HIGH);
    vif.rready <= 1;
    foreach (tr.rdata[i]) begin
      @(posedge vif.aclk iff vif.rvalid);
      tr.rdata[i] = vif.rdata;
      tr.rresp[i] = vif.rresp;
      `uvm_info("READ_DATA", $sformatf("Beat %0d: RID=%0d RDATA=%h RRESP=%b", i, vif.rid, tr.rdata[i], tr.rresp[i]), UVM_MEDIUM);
    end
    vif.rready <= 0;
  
endtask
endclass

