// MONITOR: Captures AXI4 transactions from interface
class axi_monitor extends uvm_monitor;

  virtual interface vif;

  uvm_analysis_port #(axi_transaction) ap;

  `uvm_component_utils(axi_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   if(!uvm_config_db#(virtual interface)::get(this,"","vif",vif)) begin
  	 `uvm_error("AXI_MONITOR","Virtual interface is not received")
   end
  endfunction


 virtual task run_phase(uvm_phase phase);
    forever begin
      // Write Transaction Capture
       wait (vif.awvalid && vif.awready);

        axi_transaction tr = axi_transaction::type_id::create("tr");
        // Capture the write address channel
        tr.awid     = vif.awid;
        tr.awaddr   = vif.awaddr;
        tr.awsize   = vif.awsize;
        tr.awburst  = vif.awburst;
        tr.awcache  = vif.awcache;
        tr.awprot   = vif.awprot;
        tr.awlen    = vif.awlen;
        tr.awlock   = vif.awlock;
        tr.awqos    = vif.awqos;
        tr.awregion = vif.awregion;
        tr.awuser   = vif.awuser;

        // Allocate dynamic arrays for data & strb,last 
        tr.wdata = new[tr.awlen + 1];
        tr.wstrb = new[tr.awlen + 1];
        tr.wlast = new[tr.awlen + 1];

       // Capture the write data channel
        for (int i = 0; i <= tr.awlen; i++) begin
          wait (vif.wvalid && vif.wready);
          tr.wdata[i] = vif.wdata;
          tr.wstrb[i] = vif.wstrb;
	  tr.wlast[i] = vif.wlast;
        end

        // Capture the write response channel
        wait (vif.bvalid && vif.bready);
          tr.bid   = vif.bid;
          tr.bresp = vif.bresp;
	
        `uvm_info("MON_WRITE_RESP",$sformatf("BID=%0d BRESP=%0b", vif.bid, vif.bresp),UVM_MEDIUM);

        ap.write(tr);

      end

      // Read Transaction Capture
      if (vif.arvalid && vif.arready) begin
        axi_transaction tr = axi_transaction::type_id::create("tr");
        // Capture the Read address channel
        tr.arid     = vif.arid;
        tr.araddr   = vif.araddr;
        tr.arsize   = vif.arsize;
        tr.arburst  = vif.arburst;
        tr.arcache  = vif.arcache;
        tr.arprot   = vif.arprot;
        tr.arlen    = vif.arlen;
        tr.arlock   = vif.arlock;
        tr.arqos    = vif.arqos;
        tr.arregion = vif.arregion;
        tr.aruser   = vif.aruser;

        // Allocate dynamic array for read data
        tr.rdata = new[tr.arlen + 1];
	tr.rresp = new[tr.arlen + 1];
        tr.rlast = new[tr.arlen + 1];
 
         // Capture the read data + response channel
        for (int i = 0; i <= tr.arlen; i++) begin
          wait (vif.rvalid && vif.rready);
          tr.rdata[i] = vif.rdata;
	  tr.rresp[i] = vif.rresp;
          tr.rlast[i] = vif.rlast;

          `uvm_info("MON_READ_RESP",$sformatf("RID=%0d RDATA=%h RRESP=%0b RLAST=%0b",vif.rid, vif.rdata, vif.rresp, vif.rlast),UVM_MEDIUM);
        end

        ap.write(tr);

      end

    end
  endtask

endclass
	

