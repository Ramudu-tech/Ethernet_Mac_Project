// Ethernet_frame_seq_item it consists of data fields required for generating the stimulus and Adding constraints as per requirements.


`include "uvm_macros.svh"
import uvm_pkg::*;

// Creating an ethernet_frame_seq_item class
class ethernet_frame_seq_item extends uvm_sequence_item;
  
  //..............................Ethernet properties...............................//
  /*
  Preamble (7 Bytes): Signals the start of a frame and helps synchronize sender and receiver clocks.
  Start Frame Delimiter (SFD, 1 Byte): Marks the exact beginning of the Ethernet frame. 
  Destination MAC Address (6 Bytes): Identifies the receiving device on the local network.  
  Source MAC Address (6 Bytes): Indicates the sender’s hardware address.
  
  Type/Length (2 Bytes): Specifies either the payload length or the upper-layer protocol type.
  Lenght: If the value is ≤ 1500, it represents the length of the payload (data field) in bytes.   
  Type: If the payload value is ≥ 1536 (0x0600), it indicates the protocol type of the payload.
 
  Payload/Data (46–1500 Bytes): Contains the actual data being transmitted. 
  Frame Check Sequence (FCS, 4 Bytes): Provides error detection using a CRC checksum. */
  rand bit [55:0] preamble; 
  rand bit [7:0] sfd; 
  rand bit [47:0] dest_addr; 
  rand bit [47:0] src_addr; 
  rand bit [15:0] length;
  rand bit [15:0] type_protocol;
  rand int payload[];
  rand bit [31:0] frame_check;
  
  
  //..............................IPV4_PKT properties...............................//
     
  /*
  Version:              4 bits      Specifies the IP protocol version (always 4 for IPv4).
  Header Length (IHL):  4 bits      Indicates the size of the header in 32-bit words.
  Type of Service (ToS):8 bits      Defines priority and handling preferences for the packet.
  Total Length:	        16 bits     Total size of the packet including header and data.
  Identification:       16 bits     Unique ID to help reassemble fragmented packets.
  Flags:                3 bits      Controls fragmentation behavior of the packet.
  Fragment Offset:	    13 bits     Position of a fragment within the original packet.
  Time to Live (TTL):	8 bits      Limits how many hops the packet can take before being discarded.
  Protocol:	            8 bits      Indicates the upper-layer protocol (e.g., TCP, UDP).
  Header Checksum:	    16 bits     Error-checking value for the header only.
  Source IP Addr:       32 bits     IP address of the sender.
  Destination IP Addr:	32 bits     IP address of the receiver.
  Options:	            0-40 bytes  Optional settings for routing, security, or timestamps.
  Padding:	            Extra bytes added to align the header to 32-bit boundaries.  */
  
  rand bit [3:0] ver_ipv4;
  rand bit [3:0] hlen;
  rand bit [7:0] service;
  rand bit [15:0] total_length;
  rand bit [15:0] identification;
  rand bit [2:0] flag;
  rand bit [12:0] fragment_offset;
  rand bit [7:0] time_to_live;
  rand bit [7:0] protocol;
  rand bit [15:0] header_checksum;
  rand bit [31:0] src_ip_addr_ipv4;
  rand bit [31:0] dest_ip_addr_ipv4;
  //@todo Need to check
  //rand bit [7:0] option[]; 
  //rand bit [7:0] padding;
  
  //..............................IPV6_PKT properties...............................//
     
  /*
  Version:	         4 bits	  Specifies the IP version (always 6 for IPv6).
  Traffic Class:     8 bits	  Indicates packet priority and congestion handling.
  Flow Label:	     20 bits  Identifies packets belonging to the same flow for special treatment.
  Payload Length:    16 bits  Size of the payload (data + extension headers).
  Next Header:	     8 bits	  Specifies the type of the next header (e.g., TCP, UDP, or extension).
  Hop Limit:         8 bits	  Maximum number of hops before the packet is discarded.
  Source Address:    128 bits IPv6 address of the sender.
  Dest Address:	     128 bits IPv6 address of the receiver.*/
   
  rand bit [3:0] ver_ipv6;
  rand bit [7:0] traffic_class;
  rand bit [19:0] flow_label;
  rand bit [15:0] payload_length;
  rand bit [7:0] next_header;
  rand bit [7:0] hop_limit;
  rand bit [127:0] src_ip_addr_ipv6;
  rand bit [127:0] dest_ip_addr_ipv6;
  
  
  
  
  
  
  
  
  // Factory registration  
  `uvm_object_utils_begin(ethernet_frame_seq_item)
  //----- Ethenet fields
  `uvm_field_int(preamble, UVM_ALL_ON)
  `uvm_field_int(sfd, UVM_ALL_ON)
  `uvm_field_int(dest_addr, UVM_ALL_ON)
  `uvm_field_int(src_addr, UVM_ALL_ON)
  `uvm_field_int(length, UVM_ALL_ON)
  `uvm_field_int(type_protocol, UVM_ALL_ON)
  `uvm_field_array_int(payload, UVM_ALL_ON)
  `uvm_field_int(frame_check, UVM_ALL_ON)
  
  //----- IPv4   
  `uvm_field_int(ver_ipv4, UVM_ALL_ON)
  `uvm_field_int(hlen, UVM_ALL_ON)
  `uvm_field_int(service, UVM_ALL_ON)
  `uvm_field_int(total_length, UVM_ALL_ON)
  `uvm_field_int(identification, UVM_ALL_ON)
  `uvm_field_int(flag, UVM_ALL_ON)
  `uvm_field_int(fragment_offset, UVM_ALL_ON)
  `uvm_field_int(time_to_live, UVM_ALL_ON)
  `uvm_field_int(protocol, UVM_ALL_ON)
  `uvm_field_int(header_checksum, UVM_ALL_ON)
  `uvm_field_int(src_ip_addr_ipv4, UVM_ALL_ON)
  `uvm_field_int(dest_ip_addr_ipv4, UVM_ALL_ON)
  
  //----- IPv6
  `uvm_field_int(ver_ipv6, UVM_ALL_ON)
  `uvm_field_int(traffic_class, UVM_ALL_ON)
  `uvm_field_int(flow_label, UVM_ALL_ON)
  `uvm_field_int(payload_length, UVM_ALL_ON)
  `uvm_field_int(next_header, UVM_ALL_ON)
  `uvm_field_int(hop_limit, UVM_ALL_ON)
  `uvm_field_int(src_ip_addr_ipv6, UVM_ALL_ON)
  `uvm_field_int(dest_ip_addr_ipv6, UVM_ALL_ON)
  
  `uvm_object_utils_end
  
  // Constructor
  function new(string name = "ethernet_frame_seq_item");
    super.new(name);
  endfunction
  
  typedef enum {ETHERNET_FRAME,IPV4_PKT, IPV6_PKT} pkt_type;
  
 
  // Constraint for fields
  constraint ct_preamble{
    preamble == 56'h55_5555_5555;
    sfd == 8'hd5;
    dest_addr == 48'haa_bb_cc_dd_ee_ff;
    src_addr == 48'h11_22_33_44_55_66;
    //Payload
    
  
  }

  
endclass


