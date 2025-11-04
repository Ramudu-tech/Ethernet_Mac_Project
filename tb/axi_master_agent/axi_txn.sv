class axi_transaction extends uvm_sequence_item;

parameter int USER_DATA_WIDTH = 8;// USER_DATA_WIDTH is an integer multiple of the width of the data buses in bytes
typedef enum {READ,WRITE} burst_t;
rand burst_t burst_type;
//Declare the fields 

//Write Address (AW) channel signals:
rand bit [3:0]  awid;          //AXI3 and AXI4 
rand bit [31:0] awaddr;        //AXI3 and AXI4 
rand bit [2:0]  awsize;        //AXI3 and AXI4 
rand bit [1:0]  awburst;       //AXI3 and AXI4 
rand bit [3:0]  awcache;       //AXI3 and AXI4 
rand bit [2:0]  awprot;        //AXI3 and AXI4 
rand bit [7:0]  awlen;         //AXI4 only //awlen[3:0]    AXI3 only 
rand bit        awlock;        //AXI4 only //awlock[1:0]   AXI3 only 
rand bit [3:0]  awqos;         //AXI4 only 
rand bit [3:0]  awregion;      //AXI4 only 
rand bit [USER_DATA_WIDTH-1:0] awuser;       //AXI4 only -->USER_DATA_WIDTH User-defined extension to a request

//Write Data (W) channel signals:
rand bit [31:0] wdata[];      //AXI3 and AXI4 -->supports maximum data width 1024 bits 0r 128 bytes
rand bit [3:0]  wstrb[];       // AXI3 and AXI4--> WSTRB width = WDATA width / 8
rand bit [USER_DATA_WIDTH-1:0] wuser;        //AXI4 only 
rand bit        wlast;               //AXI3 and AXI4  //WID[x:0] AXI3 only major difference "ID" will not be there in write_data channel

//Write Response (B) channel signals:  
rand bit [3:0] bid;           //AXI3 and AXI4 
bit [1:0]      bresp;              //AXI3 and AXI4 
rand bit [USER_DATA_WIDTH-1:0] buser;        //AXI4 only

//Read Address (AR) channel signals:  
rand bit [3:0]  arid;          //AXI3 and AXI4 
rand bit [31:0] araddr;        //AXI3 and AXI4
rand bit [2:0]  arsize;        //AXI3 and AXI4 
rand bit [1:0]  arburst;       //AXI3 and AXI4 
rand bit [3:0]  arcache;       //AXI3 and AXI4 
rand bit [2:0]  arprot;        //AXI3 and AXI4 
rand bit [7:0]  arlen;         //AXI4 only    // arlen [3:0]   AXI3 only 
rand bit        arlock;        //AXI4 only    // arlock [1:0]  AXI3 only 
rand bit [3:0]  arqos;         //AXI4 only 
rand bit [3:0]  arregion;      //AXI4 only 
rand bit [USER_DATA_WIDTH-1:0] aruser;        //AXI4 only

//Read Data (R) channel signals  
rand bit        rlast;         //AXI3 and AXI4 
rand bit [31:0] rdata[];       //AXI3 and AXI4 
bit [1:0]       rresp[];       //AXI3 and AXI4 
rand bit [3:0]  rid;           //AXI3 and AXI4 
rand bit [USER_DATA_WIDTH-1:0] ruser;         //AXI4 only 


//factory registration
`uvm_object_utils_begin(axi_transaction)

   //write address channel 
   `uvm_field_int(awid,UVM_ALL_ON)
   `uvm_field_int(awaddr,UVM_ALL_ON)
   `uvm_field_int(awsize,UVM_ALL_ON)
   `uvm_field_int(awburst,UVM_ALL_ON)
   `uvm_field_int(awcache,UVM_ALL_ON)
   `uvm_field_int(awprot,UVM_ALL_ON)
   `uvm_field_int(awlen,UVM_ALL_ON)
   `uvm_field_int(awlock,UVM_ALL_ON)
   `uvm_field_int(awqos,UVM_ALL_ON)
   `uvm_field_int(awregion,UVM_ALL_ON)
   `uvm_field_int(awuser,UVM_ALL_ON)
   `uvm_field_int(awvalid,UVM_ALL_ON)
   `uvm_field_int(awready,UVM_ALL_ON)
   `uvm_field_enum(burst_t, burst_type, UVM_ALL_ON)


   //write data channel
   `uvm_field_array_int(wdata,UVM_ALL_ON)
   `uvm_field_array_int(wstrb,UVM_ALL_ON)
   `uvm_field_int(wuser,UVM_ALL_ON)
   `uvm_field_int(wlast,UVM_ALL_ON)
   `uvm_field_int(wvalid,UVM_ALL_ON)
   `uvm_field_int(wready,UVM_ALL_ON)

   //write response channel
   `uvm_field_int(bid,UVM_ALL_ON)
   `uvm_field_int(bresp,UVM_ALL_ON)
   `uvm_field_int(buser,UVM_ALL_ON)
   `uvm_field_int(bvalid,UVM_ALL_ON)
   `uvm_field_int(bready,UVM_ALL_ON)

   //read address channel
   `uvm_field_int(arid,UVM_ALL_ON)
   `uvm_field_int(araddr,UVM_ALL_ON)
   `uvm_field_int(arsize,UVM_ALL_ON)
   `uvm_field_int(arburst,UVM_ALL_ON)
   `uvm_field_int(arcache,UVM_ALL_ON)
   `uvm_field_int(arprot,UVM_ALL_ON)
   `uvm_field_int(arlen,UVM_ALL_ON)
   `uvm_field_int(arlock,UVM_ALL_ON)
   `uvm_field_int(arqos,UVM_ALL_ON)
   `uvm_field_int(arregion,UVM_ALL_ON)
   `uvm_field_int(aruser,UVM_ALL_ON)
   `uvm_field_int(arvalid,UVM_ALL_ON)
   `uvm_field_int(arready,UVM_ALL_ON)

   //read response channel
   `uvm_field_int(rid,UVM_ALL_ON)
   `uvm_field_int(rlast,UVM_ALL_ON)
   `uvm_field_array_int(rdata,UVM_ALL_ON)
   `uvm_field_array_int(rresp,UVM_ALL_ON)
   `uvm_field_int(ruser,UVM_ALL_ON)
   `uvm_field_int(rvalid,UVM_ALL_ON)
   `uvm_field_int(rready,UVM_ALL_ON)

`uvm_object_utils_end

//constructor
function new(string name = "axi_transaction");
   super.new(name);
endfunction

//constraints

//Address Alignment
constraint addr_alignment_c {
  awaddr % (1 << awsize) == 0;
  araddr % (1 << arsize) == 0;
}

//Burst Type (AxBURST)	FIXED, INCR, WRAP
constraint burst_type_c {
  awburst inside {2'b00, 2'b01, 2'b10}; // FIXED, INCR, WRAP
  arburst inside {2'b00, 2'b01, 2'b10}; // FIXED, INCR, WRAP
}

//Data Array Constraints
//Ensure your dynamic arrays match the burst length:
constraint match_data_c{wdata.size() == awlen + 1; rdata.size() == arlen + 1; wstrb.size() == awlen + 1;}

//for Strobe
constraint strobe_c0 {
  foreach (wstrb[i]) wstrb[i] == 4'b1111;//All 4 bytes of the 32-bit WDATA being valid and full-word write for each beat.
}
//constraint strobe_c1 {
//  foreach (wstrb[i]) wstrb[i] inside {4'b0001, 4'b0011, 4'b1111, 4'b1100};//If the DUT supports both full and partial writes,then this constraint suitable.
//}


//If you're using WRAP bursts, make sure to also constrain AWADDR and ARADDR for proper alignment:
constraint wrap_boundary_c {
  if (awburst == 2'b10)
    awaddr % ((1 << awsize) * (awlen + 1)) == 0;//awaddr is aligned to the total wrap boundary size(wrap_boundary = [num_bytes](1 << awsize) * (awlen + 1)[burst_length])
  
  if (arburst == 2'b10)
    araddr % ((1 << arsize) * (arlen + 1)) == 0;//araddr is aligned to the total wrap boundary size(wrap_boundary = (1 << arsize) * (arlen + 1))
}

