// Ethernet Monitor is a passive entity that samples the DUT signals through the virtual interface and converts the signal level activity to the transaction level
// Monitor samples DUT signals but does not drive them The monitor should have an analysis port (TLM port) and a virtual interface handle that points to DUT signals.


`include "uvm_macros.svh"
import uvm_pkg::*;

class ethernet_monitor extends uvm_monitor;
  // Factory registration
  `uvm_components_utils(ethernet_monitor)

  // Seq_item handle
  ethernet_frame_seq_item tnx;
  
  // Creating analysis port to send data to Scoreboard
  uvm_analysis_port #(ethernet_frame_seq_item) tnx_send;
  
  // Virtual interface handle
  virtual gmii_intf vif;
  
  //Collecting data variables
  bit [7:0] txd_data[22];
  bit [7:0] rxd_data[22];
  int count = 0;
  
   // Constructor
  function new(string name = "ethernet_monitor", uvm_component parent = null);
    super.new(name, parent);
    tnx_send = new("tnx_send", this);
  endfunction
    
  // Build phase
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
     tnx = ethernet_frame_seq_item::type_id::create("tnx");
    // Virtual interface access
    if(!uvm_config_db #(virtual gmii_intf)::get(this, " ", "vif", vif)) 
      `uvm_fatal("ETH_MONITOR", "Unable to access the interface");
  endfunction
  
  //-----------------------------------------------------------
  // Receiving TXD from DUT
  task sample_txd()
    `uvm_info("ETH_MONITOR", " Inside the Sample_txd task", UVM_NONE);
    // Seq_item handle, to collect the frame fields details.
    ethernet_frame_seq_item tnx;
    
    tnx = ethernet_frame_seq_item::type_id::create("tnx");
    //@(  ); // Adding delay 
    if(vif.tx_en && !vif.tx_er) begin      
      txd_data[count] = vif.txd;
      `uvm_info("ETH_MONITOR", $sformatf(" Value of vif.tx_en : %b, vif.tx_er : %b, Txd_data : %0h, Count : %0d", vif.tx_en, vif.tx_er, txd_data, count), UVM_NONE);
      count++;      
    end
    
    tnx.preamble = {txd_data[0],txd_data[1],txd_data[2],txd_data[3],txd_data[4],txd_data[5],txd_data[6]}
    tnx.sfd = txd_data[7];
    tnx.dest_addr = {txd_data[8],txd_data[9],txd_data[10],txd_data[11],txd_data[12],txd_data[13]};
    tnx.src_addr = {txd_data[14],txd_data[15],txd_data[16],txd_data[17],txd_data[18],txd_data[19]};
    tnx.lenght = {txd_data[20], txd_data[21]};
    
    // GMII(Txd) ethernet displays
    `uvm_info("ETH_MONITOR", " Receving from GMII(txd)", UVM_NONE); 
    `uvm_info("ETH_MONITOR", $sformatf(" txd to tnx.PREAMBLE : %b", tnx.preamble), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" txd to tnx.SFD : %0h", tnx.sfd), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" txd to tnx.DEST_ADDR : %0h", tnx.dest_addr), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" txd to tnx.SRC_ADDR: %0h", tnx.src_addr), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" txd to tnx.LENGTH : %0d", tnx.length), UVM_NONE);
    
    
    
    //{tnx.length, tnx.src_addr, tnx.dest_addr, tnx.sfd, tnx.preamble} = { txd_data[175:160],txd_data[159:112],txd_data[111:64],txd_data[63:56],txd_data[55:0]}; 
    
    
    
  endtask
  
  
  // Receiving RXD from DUT
  task sample_rxd()
    `uvm_info("ETH_MONITOR", " Inside the Sample_rxd task", UVM_NONE);
    // Seq_item handle, to collect the frame fields details.
    ethernet_frame_seq_item tnx;
    
    tnx = ethernet_frame_seq_item::type_id::create("tnx");
    //@(  ); // Adding delay 
    if(vif.rx_en && !vif.rx_er) begin
      rxd_data[count] = vif.rxd;
      `uvm_info("ETH_MONITOR", $sformatf(" Value of vif.rx_en : %b, vif.rx_er : %b, Rxd_data : %0h, Count : %0d", vif.rx_en, vif.rx_er, rxd_data, count), UVM_NONE);
      count++;
      
    end
    
    tnx.preamble = {rxd_data[0],rxd_data[1],rxd_data[2],rxd_data[3],rxd_data[4],rxd_data[5],rxd_data[6]}
    tnx.sfd = rxd_data[7];
    tnx.dest_addr = {rxd_data[8],rxd_data[9],rxd_data[10],rxd_data[11],rxd_data[12],rxd_data[13]};
    tnx.src_addr = {rxd_data[14],rxd_data[15],rxd_data[16],rxd_data[17],rxd_data[18],rxd_data[19]};
    tnx.lenght = {rxd_data[20], rxd_data[21]};
    
    // GMII(Rxd) ethernet displays
    `uvm_info("ETH_MONITOR", " Receving from GMII(rxd)", UVM_NONE); 
    `uvm_info("ETH_MONITOR", $sformatf(" rxd to tnx.PREAMBLE : %b", tnx.preamble), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" rxd to tnx.SFD : %0h", tnx.sfd), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" rxd to tnx.DEST_ADDR : %0h", tnx.dest_addr), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" rxd to tnx.SRC_ADDR: %0h", tnx.src_addr), UVM_NONE);
    `uvm_info("ETH_MONITOR", $sformatf(" rxd to tnx.LENGTH : %0d", tnx.length), UVM_NONE);
    
    
    
  endtask             
              
  //----------------------------------------------------------
  
    
  // Run_phase
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      fork
        begin
          sample_txd();
        end
        begin
          sample_rxd();
        end
      join     
    end    
  endtask
 
endclass




  
  
  
  
  








