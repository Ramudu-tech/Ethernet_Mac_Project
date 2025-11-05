// Ethernet_driver is inherited from uvm_driver, Methods and TLM port (seq_item_port) are defined for communication between sequencer and driver. 
// The driver is a parameterized class and it is parameterized with the type of the request sequence_item and the type of the response sequence_item.

`include "uvm_macros.svh"
import uvm_pkg::*;


// Creating an ethernet_driver class
class ethernet_driver extends uvm_driver #(ethernet_frame_seq_item);
  
  // Factory registration
  `uvm_component_utils(ethernet_driver)
  
  // Seq_item handle
  ethernet_frame_seq_item tnx;
  
  // Virtual interface handle
  virtual gmii_intf vif;
  
  // To store the frame fileds
  bit [175:0] frame_concat;
  
  // Construtor
  function new(string name = "ethernet_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  // Build_phase 
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tnx = ethernet_frame_seq_item::type_id::create("tnx");
    // Virtual interface access
    if(!uvm_config_db #(virtual gmii_intf)::get(this, " ", "vif", vif)) 
      `uvm_fatal("ETH_DRIVER", "Unable to access the interface");
  endfunction
  
  virtual task run_phase(uvm_phase phase);
    `uvm_info("ETH_DRIVER", "Inside the Eth_driver run_phase", UVM_NONE);
    forever begin
      seq_item_port.get_next_item(tnx);
     // `uvm_info("
      send_to_dut();
      
      seq_item_export.item_done();   
    end
  endtask
  
  
endclass


task mac_driver::send_to_dut();
  `uvm_info("ETH_DRIVER", " Ethernet driver run_phase start", UVM_NONE);
  
  // Active high reset
  if(vif.reset) begin
    vif.tx_en <= 1'b0;
    vif.tx_er <= 1'b0;
    vif.txd <= 8'h0;
    `uvm_info("ETH_DRIVER", $sformatf(" When reset done, Reset : %b, Tx_en : %b, Tx_er : %b, Txd : %0h", vif.reset, vif.tx_en, vif.tx_er, vif.txd), UVM_NONE); 
  end
  else if(!vif.reset) begin
    
    //------------ Frame 
    //`uvm_info("ETH_DRIVER", " After reseting the system", UVM_NONE);
    if(tnx.pkt_type == FRAME) begin
      `uvm_info("ETH_DRIVER", " Ethernet driver with FRAME", UVM_NONE);
      vif.tx_en <= 1'b1;
      vif.tx_er <= 1'b0;
      
      //frame_concat = {tnx.preamble, tnx.sfd, tnx.dest_addr, tnx.src_addr, tnx.length};
      frame_concat = {tnx.length, tnx.src_addr, tnx.dest_addr, tnx.sfd, tnx.preamble};
      
      // Sending ethernet frame fields
      for(int i = 0; i < 22; i++) begin        
        @(posedge vif.clk);                        
        vif.txd <= frame_concat[7+i*8:0+i*8];
      end
      
      // Sending payload
      for(int i = 0; i < tnx.payload.size(); i++) begin
        @(posedge vif.clk);
        vif.txd <= tnx.payload[i];
      end
      
      // Sending CRC
      for(int i = 0; i < 4; i++) begin
        @(posedge vif.clk);
        vif.txd = tnx.crc[7+i*8:0+i*8];        
      end     
      
      // Reseting the  en, er, txd
      vif.tx_en <= 1'b0;
      vif.tx_er <= 1'b0;
      vif.txd <= 8'h0;     
    end // pkt_type == FRAME
    
//-------------- IPv4    
    
    
    // When pkt_type == IPv4
    else if(tnx.pkt_type == IPV4_PKT) begin
      `uvm_info("ETH_DRIVER", " Ethernet driver with IPv4 PKT", UVM_NONE);
      vif.tx_en <= 1'b1;
      vif.tx_er <= 1'b0;
   
      
      
      //Reseting the en, er, txd
      
    end // When IPv4 PKT
    
 //--------------- IPv6
    
    // When Pkt_type == IPv6
    else if(tnx.pkt_type == IPV6_PKT) begin
      `uvm_info("ETH_DRIVER", " Ethernet driver with IPv6 PKT", UVM_NONE);
      vif.tx_en <= 1'b1;
      vif.tx_er <= 1'b0;
      
      
      // Reseting the en, er, txd
    
      
    end // When IPv6 Pkt
  end // when RST = 0
 
endtask
                
                
