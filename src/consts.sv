parameter FLAGS_LEN = 28;

// Individual flag bit positions
parameter AI_BIT = 0;
parameter BI_BIT = 1;
parameter CI_BIT = 2;
parameter DI_BIT = 3;
parameter EI_BIT = 4;
parameter FI_BIT = 5;
parameter GI_BIT = 6;
parameter HI_BIT = 7;
parameter RAMI_BIT = 8;
parameter MARI_BIT = 9;
parameter MPAGEI_BIT = 10;
parameter OI_BIT = 11;
parameter AO_BIT = 12;
parameter BO_BIT = 13;
parameter CO_BIT = 14;
parameter DO_BIT = 15;
parameter EO_BIT = 16;
parameter FO_BIT = 17;
parameter GO_BIT = 18;
parameter HO_BIT = 19;
parameter ALUO_BIT = 20;
parameter ROMO_BIT = 21;
parameter RAMO_BIT = 22;
parameter JMPO_BIT = 23;
parameter IO_BIT = 24;
parameter PCC_BIT = 25;
parameter HALT_BIT = 26;
parameter AC_BIT = 27;

// Flag constants for control unit
parameter UPDATE_IR_FLAGS = (1 << PCC_BIT | 1 << ROMO_BIT);