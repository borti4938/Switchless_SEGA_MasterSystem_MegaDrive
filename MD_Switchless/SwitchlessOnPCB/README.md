This small subprject is not initialted be myself. All thanks to this go to user _ArcadeTV_ and user _wshadow_; both members of the [Circuit-Board.de](https://circuit-board.de/forum/) community.
So what is this?

Histroy
---

Once I started designing my own switchless mod for the Sega Mega Drive, ArcadeTV drew a printed circuit board.
Although I was not ready with the implementation, ArcadeTV [published the PCB on circuit-board](https://circuit-board.de/forum/index.php/Thread/14691-Mega-Drive-Mod-Platinen-RGB-Bypass-Switchless-Mod-Mega-Amp/).  
This board is available in this repository.

Time was running and I lost the focus to this PCB.
Instead I made design decisions which made PCB pinout incompatible to my code.
Reasons were being pin compatible to [Sebs popular code](https://knzl.at/saturnmod/), which is used for Multi-BIOS extension on the MegaCD as well as the [build-in-game project](https://github.com/borti4938/MD-Build-In-Game).
The code went into a final state as it is presented in the top-folder here in the repository.
Another long time period passed by.

CiBo user wshadow [picked up both](https://circuit-board.de/forum/index.php/Thread/14691-Mega-Drive-Mod-Platinen-RGB-Bypass-Switchless-Mod-Mega-Amp/?postID=736815#post736815) - the PCB and code - and made both compatible again.
He worked hard, learned assembler, and finally made it.
I reviewed the changes and now publish code and PCB.

Notes
---

I don't own a Mega Drive!
So please be patient if there are any misstakes in the text comming from my misunderstanding.

### PCB

PCB is made with EAGLE and has two layers.
I tested to upload the PCB on OSHPark and it works.
Of course, you can also use any other PCB manufacturer you want.

### Parts for PCB and Installation

- 1x RND 1500805Y1041
- 1x BAT 54A SMD
- 1x PIC 16F630-I/SL
- 2x SMD-0805 1,0K
- 1x RND 0805 1 20K
- 2x SMD-0805 220
- 1x RG-LED or RGB-LED with 3mm or 5mm head  
  For installation, Code supports both common anode and common cathod LEDs

### Code

The code is made for the PIC16F630.
There is an ICSP header on the PCB.

### Additional notes

Additional notes can be found in the top comment section of the *.asm file.


### Feedback

Feedback is very welcome!

