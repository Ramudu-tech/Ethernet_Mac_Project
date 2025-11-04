//1. Preamble and Start Frame Delimiter (SFD)
//Check the preamble is always 0x55 repeated 7 times, and the SFD is always 0xD5 immediately after:

property preamble_and_sfd_check;
  @(posedge clk)
    sop |-> ##7 (preamble == 56'h55555555555555) ##1 (sfd == 8'hD5);
endproperty
assert property (preamble_and_sfd_check);

//2. Destination/Source Address Fields
//Enforce presence and non-zero MAC addresses

property mac_address_check;
  @(posedge clk)
    sfd |-> ##6 (dest_addr != 48'h0) ##6 (src_addr != 48'h0);
endproperty
assert property (mac_address_check);


//3. Payload Size Compliance
//The sum of the payload and (optional) pad must be ≥46 and ≤1500 bytes:

property payload_pad_size_check;
  @(posedge clk)
    sop |-> ##5 (payload_pad_size >= 46 && payload_pad_size <= 1500);
endproperty
assert property (payload_pad_size_check);

//4. Pad Field
//Pad is only present and non-zero when payload <46 bytes:

property pad_present_for_small_payload;
  @(posedge clk)
    (payload_size < 46) |-> (pad_size == (46 - payload_size));
endproperty
assert property (pad_present_for_small_payload);

//5. Frame Check Sequence (FCS)
//Assert CRC32 field (FCS) correctness at frame end:

property fcs_correct;
  @(posedge clk)
    eop |-> (fcs == calculated_crc);   //end of preamble (eop)
endproperty
assert property (fcs_correct);



//6. TX_EN (Transmit Enable)
//Assert TX_EN is high only during valid transmit (when transmitting data with valid TXD):
// TX_EN must only be active if TXD holds valid data (not idle).

property tx_en_when_txd_valid;
  @(posedge clk)
  TX_EN |-> (TXD !== IDLE); // Assume IDLE is defined for your bus
endproperty
assert property (tx_en_when_txd_valid);

//7. TXD (Transmit Data Bus)
//Assert TXD is stable across the transmit period:
// During TX_EN, TXD should remain stable (especially at each clock).

property txd_stable_when_enabled;
  @(posedge clk)
  TX_EN |=> ($stable(TXD)); // for strict/idealized stability
endproperty
assert property (txd_stable_when_enabled);

//8. TX_ER (Transmit Error)
//Assert TX_ER is only high during TX_EN:

property tx_er_only_during_tx;
  @(posedge clk)
  TX_ER |-> TX_EN;
endproperty
assert property (tx_er_only_during_tx);

//9. RX_DV (Receive Data Valid)
//Assert RX_DV is only asserted when RXD holds valid data (not idle):

property rx_dv_data_present;
  @(posedge clk)
  RX_DV |-> (RXD !== IDLE);
endproperty
assert property (rx_dv_data_present);

//10. RXD (Receive Data Bus)
//Assert RXD changes only on RX_DV asserted:


property rxd_changes_with_rxdv;
  @(posedge clk)
  (!RX_DV && $rose(RXD)) |-> 0; // RXD should not change when RX_DV is low
endproperty
assert property (rxd_changes_with_rxdv);

//11. RX_ER (Receive Error)
//Assert RX_ER can only assert when RX_DV is asserted:

property rx_er_info_only_if_valid;
  @(posedge clk)
  RX_ER |-> RX_DV;
endproperty
assert property (rx_er_info_only_if_valid);

//12. COL (Collision Detect, half-duplex)
//Assert that COL cannot occur during receive (full-duplex):

property col_validly_asserted;
  @(posedge clk)
  COL |-> TX_EN && RX_DV; // Typically, collision can only be detected when both TX and RX activity on the line
endproperty
assert property (col_validly_asserted);


//13. CRS (Carrier Sense)
//Carrier Sense should only be high when channel is active (transmitting or receiving):

property crs_when_busy;
  @(posedge clk)
  CRS |-> (TX_EN || RX_DV);
endproperty
assert property (crs_when_busy);

//14. MDC/MDIO (Management Interface)
//MDIO must only change on rising edge of MDC:

property mdio_sync_with_mdc;
  @(posedge clk)
  $changed(MDIO) |-> $rose(MDC);
endproperty
assert property (mdio_sync_with_mdc);
