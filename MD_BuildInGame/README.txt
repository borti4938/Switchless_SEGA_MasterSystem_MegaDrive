Build-In Game Project for Sega Genesis / Mega Drive  
===================================================  
  
Main idea by ArcadeTV  
Development by srdwa, ArcadeTV and borti4938  
  
See logs and discussions here: http://circuit-board.de/forum/index.php/Thread/17706-Idee-Mega-Drive-mit-eingebautem-Spiel/  
  
===================================================  

This work here is still WIP!!! It has been never tested so far!!!  

===================================================  

Main idea:  
- start a game from internal rom if no device is present at the extension port or no cartridge is present  
- use indentification signals from cart slot and extension slot for detection  
- internal rom can be separated in one, two or four banks (selected by two pins)  
- bank switch is accessed by a 2bit counter  
- TMSS disable mod as described here: http://assemblergames.com/l/threads/md-genny-auto-switching-tmss-bypass-mod.19781/ can be enabled optionally  
  
===================================================  
  
ToDo:  
- test 2bit counter addition for switchless code (code by borti4938)  
- write installation tips  
  
===================================================  
  
Pinout of the PLD (G16V8) as used on the PCB:  
  
/* *************** INPUT PINS ******************** */  
PIN  1 = DISKn;     /* /DISK (ExpPort B2)                       */  
PIN  2 = ROM_Mode2; /* high/open = 1 game     , low = 2 games   */  
PIN  3 = ROM_Mode4; /* high/open = 1/2 game(s), low = 4 games   */  
                    /* low = 4 games (beats ROM_Mode2)          */  
PIN  4 = CARTn;     /* /CART (from ASIC cart slot B32,          */  
                    /*        cutted from ASIC)                 */  
PIN  5 = ASIC_OEn;  /* /OE (from ASIC; cutted from cart slot    */  
                    /*                 B17 if TMSS Mod is used) */  
PIN  6 = CEn;       /* /CE (cart slot B16)                      */  
PIN  7 = A23;       /* A23 (cart slot B11)                      */  
PIN  8 = AMSB0;     /* A19 (cart slot  B7)                      */  
PIN  9 = AMSB1;     /* A20 (cart slot  B8)                      */  
                    /* (addressbus counts from A1)              */  
  
/* *************** I/O PINS ******************** */  
PIN 19 = BIG_Sel0;   /* bank switch LSB                         */  
PIN 18 = BIG_Sel1;   /* bank switch MSB                         */  
PIN 17 = ASIC_CARTn; /* /CART (from ASIC; cutted from cart      */  
                     /*                   slot B32)             */  
PIN 16 = ROM_OEn;    /* /OE internal EEPROM (29F1610 Pin 14)    */  
PIN 15 = ROM_CEn;    /* /CE internal EEPROM (29F1610 Pin 12)    */  
PIN 14 = CART_OEn;   /* /OE cartridge (cart slot B17)           */  
PIN 13 = ROM_AMSB0;  /* A18 internal EEPROM (29F1610 Pin  2)    */  
PIN 12 = ROM_AMSB1;  /* A19 internal EEPROM (29F1610 Pin 43)    */  
PIN 11 = TMSS_ENn;   /* high = disabled, low = enabled          */  
                     /* /M3 (cart slot B30) AND TMSS-Mod_en     */  