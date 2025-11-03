

//Interface (MAC to PHY layer)

interface gmii_intf;
 

GMII: Is a hardware interface standard defined by IEEE 802.3 Clause 35 that connects the MAC (Media Access Control) layer to the PHY (Physical Layer) in Gigabit Ethernet systems.

// Interface signals
TX_EN:   Output   1 bit      Transmit Enable – asserts during frame transmission
TXD:     Output   4/8 bits   Transmit Data bus – 4 bits (MII), 8 bits (GMII)
TX_ER:   Output   1 bit      Transmit Error – optional, indicates coding error
RX_DV:   Input    1 bit      Receive Data Valid – asserts when frame is incoming
RXD:     Input    4/8        bits Receive Data bus
RX_ER:   Input    1 bit      Receive Error
COL:     Input    1 bit      Collision Detect – half-duplex mode only
CRS:     Input    1 bit      Carrier Sense – indicates channel is busy
MDC:     Output   1 bit      MDIO Clock – management interface clock
MDIO:    Inout    1 bit      Management Data I/O (register read/write with PHY)//@todo Not confirmed signal



  logic tx_en;
  logic [7:0] txd;
  logic tr_er;
  //logic rx_dv;  // @todo check once - Standard name from GMII spec.
  logic rx_en;    // Added by me need confirm name between rx_dv & rx_en
  logic [7:0] rxd;
  logic rx_er;
  logic col;
  logic crs;
  logic mdc;
  // logic mdio; // Currently on hold, check once anirudh mail.
  logic reset;
  
  
  
  
endinterface

