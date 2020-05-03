#include <p16f630.inc>

;
; -----------------------------------------------------------------------
;
;	Sega Master System switchless mod
;   supports:   Dual-BIOS (Eu and Jap) - needs an electrinic switch,
;                                        e.g., using a 74*125
;               FMSEB-PCB from etim - see link below
;
;   Copyright (C) 2013 by Peter Bartmann
;
;   This program is free software; you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation; version 2 of the License only.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program; if not, write to the Free Software
;   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
;
; -----------------------------------------------------------------------
;
;   pin configuration: 
;
;                         ,-----_-----.
;                     +5V |1        14| GND
;      /BIOS_EU  (in/out) |2  A5 A0 13| /RESET (in) (from Reset Button)
;      /BIOS_JAP (in/out) |3  A4 A1 12| VIDEOMODE (out) (50/60Hz)
;      /BIOS_SUPP    (in) |4  A3 A2 11| /RESET (in/out) (line to Console)
;       (green) LED (out) |5  C5 C0 10| /FMSEB_EN (in/out) 
;         (red) LED (out) |6  C4 C1  9| /FMSEB_SUPP (in)
;           LED_TYPE (in) |7  C3 C2  8| /JFMSEB_EN (in/out)
;                         `-----------'
;
; Special purposes for pins:
;
;   Pin 4 (/BIOS_SUPP) sets the support for possible BIOS-pack
;      low = BIOS-pack is present - you shall connect pin 2 (/BIOS_EU) and
;                                   pin 3 (/BIOS_JAP) to pin 20 of the current
;                                   BIOS-chip
;      high = BIOS-pack is not present - pin 2 and pin 3 stay in input mode with
;										 weak pull-ups enabled
;
;   Pin 7 (LED_TYPE) sets the output mode for the LED pins
;   (must be tied to either level):
;      low  = common cathode
;      high = common anode   (output inverted)
;
;   Pin 9 (/FMSEB_SUPP) sets the support for possible BIOS-pack
;      low = FMSEB is present - you shall connect pin 8 (/JFMSEB_EN) and 
;                               pin 10 (/FMSEB_EN) to the corresponding pins of
;                               the Sega Master System FM Sound Expansion Board
;      high = FMSEB is not present - you should not connect pin 8 and pin 10
;                                    to anything else as they stay in output
;                                    mode
;
; more information about the FMSEB:
; http://members.iinet.net.au/~stinkyfist/reviletim/smsfm/smsfm.html
;
; more information about the BIOS pack:
; http://www.smspower.org/forums/viewtopic.php?t=10908
;
; -----------------------------------------------------------------------
;
; mode description:
;
; mode 1 = PAL:           50Hz, LED green,
;                         jap. BIOS not active, FMSEB not active
;
; mode 2 = NTSC:          60Hz, LED red,
;                         jap. BIOS not active, FMSEB not active
;
; mode 3 = Fake JAP NTSC: 60Hz, LED orange,
;                         jap. BIOS not active, FMSEB with FM_EN#-Signal active
;
; mode 4 = JAP NTSC:      60Hz, LED orange,
;                         jap. BIOS active, FMSEB with JPFM_EN#-Signal active
;
;
;
; NB: - All four modes are available if the FMSEB is present (pin 9 on low).
;     - The jap. BIOS can only be activated if the BIOS pack is present
;       (pin 4 on low).
;     - If mode 3 and 4 are available the LED flashes three times. If the 
;       FMSEB is not present but the BIOS pack, i.e., mode 1, 2 and 4 are
;       available, the LED does not flash.
;     - If there is a mode change, where the BIOS- or the FMSEB mode is also
;       changed, the console requires a hard reset
;       (off and on over the power button).
;       If this is needed the console shows you you have to do so by flashing
;       the LED.
;       (current color -> off -> red -> green -> orange -> off -> current color)
;       Mode changes between 50Hz and 60Hz are done while the console is
;       running.
;      
; -----------------------------------------------------------------------
; Configuration bits: adapt to your setup and needs

    __CONFIG _INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _CPD_OFF

; -----------------------------------------------------------------------
; macros and definitions

M_movff macro   fromReg, toReg  ; move filereg to filereg
        movfw   fromReg
        movwf   toReg
        endm

M_movpf macro   fromPORT, toReg ; move PORTx to filereg
        movfw   fromPORT
        andlw   0x3f
        movwf   toReg
        endm

M_movlf macro   literal, toReg  ; move literal to filereg
        movlw   literal
        movwf   toReg
        endm

M_beff  macro   compReg1, compReg2, branch  ; branch if two fileregs are equal
        movfw   compReg1
        xorwf	compReg2, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_bepf  macro   compPORT, compReg, branch   ; brach if PORTx equals compReg (ignoring bit 6 and 7)
        movfw   compPORT
        xorwf   compReg, w
        andlw   0x3f
        btfsc   STATUS, Z
        goto    branch
        endm

M_belf  macro   literal, compReg, branch  ; branch if a literal is stored in filereg
        movlw   literal
        xorwf	compReg, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_celf  macro   literal, compReg, call_func  ; call if a literal is stored in filereg
        movlw   literal
        xorwf	compReg, w
        btfsc   STATUS, Z
        call    call_func
        endm

M_delay_x10ms   macro   literal ; delay about literal x 10ms
                movlw   literal
                movwf   reg_repetition_cnt
                call    delay_x10ms
                endm

M_push_reset    macro
                banksel TRISA
                bcf     TRISA, NRESET_OUT
                banksel PORTA
                bcf     PORTA, NRESET_OUT
                endm

M_release_reset macro
                bsf     PORTA, NRESET_OUT
                banksel TRISA
                bsf     TRISA, NRESET_OUT
                banksel PORTA
                endm

M_setBIOS_EU    macro
                banksel TRISA
                bcf     TRISA, NBIOS_EU
                bsf     TRISA, NBIOS_JAP
                banksel PORTA
                bcf     PORTA, NBIOS_EU
                endm

M_setBIOS_JAP   macro
                banksel TRISA
                bcf     TRISA, NBIOS_JAP
                bsf     TRISA, NBIOS_EU
                banksel PORTA
                bcf     PORTA, NBIOS_JAP
                endm

M_setFMSEB_EN   macro   ; led has to be set afterwards
                clrf    PORTC
                banksel TRISC
                bcf     TRISC, NFMSEB_EN
                bsf     TRISC, NJFMSEB_EN
                banksel PORTC
                endm

M_setJFMSEB_EN  macro   ; led has to be set afterwards
                clrf    PORTC
                banksel TRISC
                bcf     TRISC, NJFMSEB_EN
                bsf     TRISC, NFMSEB_EN
                banksel PORTC
                endm
                

#define M_skipnext_bios_present     btfsc   PORTA, NBIOS_SUPP
#define M_skipnext_bios_notpresent  btfss   PORTA, NBIOS_SUPP
#define M_skipnext_fm_present       btfsc   PORTC, NFMSEB_SUPP
#define M_skipnext_fm_notpresent    btfss   PORTC, NFMSEB_SUPP

#define M_set50 bsf PORTA, VIDEOMODE
#define M_set60 bcf PORTA, VIDEOMODE

#define M_skipnext_rst_pressed      btfsc   PORTA, NRESET_BUTTON
#define M_skipnext_rst_notpressed   btfss   PORTA, NRESET_BUTTON

; -----------------------------------------------------------------------

;port a
NRESET_BUTTON   EQU 0
VIDEOMODE       EQU 1
NRESET_OUT      EQU 2
NBIOS_SUPP      EQU 3
NBIOS_JAP       EQU 4
NBIOS_EU        EQU 5

;port c
NFMSEB_EN   EQU 0
NFMSEB_SUPP EQU 1
NJFMSEB_EN  EQU 2
LED_TYPE    EQU 3
LED_RED     EQU 4
LED_GREEN   EQU 5

; registers
reg_overflow_cnt    EQU 0x20
reg_repetition_cnt  EQU 0x21
reg_current_mode    EQU 0x30
reg_previous_mode   EQU 0x31
reg_led_buffer      EQU 0x40

; codes and bits
code_pal            EQU 0x00
code_ntsc           EQU 0x01
code_ntsc_fm        EQU 0x02
code_ntsc_jfm_jbios EQU 0x03

default_mode    EQU code_ntsc

bit_videomode       EQU 0     
bit_special_modes   EQU 1
bit_mode_overflow   EQU 2

code_led_off    EQU 0x00
code_led_green  EQU (1<<LED_GREEN)
code_led_red    EQU (1<<LED_RED)
code_led_yellow EQU code_led_green ^ code_led_red

code_led_invert EQU code_led_green ^ code_led_red

;mode_delay_t0_overflows EQU 0x12    ; prescaler T0 set to 1:256
delay_10ms_t0_overflows EQU 0x0a    ; prescaler T0 set to 1:4 @ 4MHz
repetitions_100ms       EQU 0x0a
repetitions_200ms       EQU 0x14
repetitions_300ms       EQU 0x1e
repetitions_mode_delay  EQU 0x4a    ; around 740ms

; -----------------------------------------------------------------------

; code memory
 org    0x0000
    clrf  STATUS  ; 00h Page 0, Bank 0
    nop           ; 01h
    nop           ; 02h
    goto  start   ; 03h begin program / Initializing

 org    0x0004  ; jump here on interrupt with GIE set (should not appear)
    return      ; return with GIE unset

 org    0x0005
idle
    M_skipnext_rst_notpressed
    goto    check_rst
    bcf     INTCON, RAIF
;    sleep

idle_wait
    btfss   INTCON, RAIF
    goto    idle_wait

check_rst
    call    delay_10ms                      ; software debounce
    call    delay_10ms                      ; software debounce
    M_skipnext_rst_pressed
    goto    idle

    M_movlf repetitions_mode_delay, reg_repetition_cnt

check_rst_loop
    call    delay_10ms
    M_skipnext_rst_pressed
    goto    doreset
    decfsz  reg_repetition_cnt, 1
    goto    check_rst_loop
    
next_mode
    incf    reg_current_mode, 1
    btfss   reg_current_mode, bit_special_modes
    goto    next_mode_end
    M_skipnext_fm_notpresent
    goto    next_mode_end
    incf    reg_current_mode, 1
    M_skipnext_bios_present
    incf    reg_current_mode, 1

next_mode_end
    btfsc   reg_current_mode, bit_mode_overflow
    clrf    reg_current_mode

    M_movlf repetitions_mode_delay, reg_repetition_cnt
    call    setled

mode_delay_loop
    call    delay_10ms
    M_skipnext_rst_pressed
    goto    apply_mode
    decfsz  reg_repetition_cnt, 1
    goto    mode_delay_loop
    goto    next_mode

doreset
    M_push_reset
    M_delay_x10ms   repetitions_300ms
    M_release_reset
    goto    idle

apply_mode
    call    save_mode
    ; strategie: mode can only be changed in non special modes
    btfsc   reg_previous_mode, bit_special_modes
    goto    check_hard_reset_needed
    btfsc   reg_current_mode, bit_special_modes
    goto    show_hard_reset_needed

    btfss   reg_current_mode, bit_videomode
    M_set50
    btfsc   reg_current_mode, bit_videomode
    M_set60
    goto    idle

check_hard_reset_needed
    M_beff  reg_current_mode, reg_previous_mode, idle   ; nothing has changed

show_hard_reset_needed
    movfw   PORTC
    andlw   0x30
    movwf   reg_led_buffer
    M_delay_x10ms   repetitions_100ms
    call    setled_off
    M_delay_x10ms   repetitions_300ms
    call    setled_green
    M_delay_x10ms   repetitions_300ms
    call    setled_red
    M_delay_x10ms   repetitions_300ms
    call    setled_yellow
    M_delay_x10ms   repetitions_300ms
    call    setled_off
    M_delay_x10ms   repetitions_300ms
    M_movff reg_led_buffer, PORTC
    goto    idle

; --------calls--------
setled
    M_belf  code_pal, reg_current_mode, setled_green
    M_belf  code_ntsc, reg_current_mode, setled_red
    M_belf  code_ntsc_fm, reg_current_mode, setled_yellow
    M_belf  code_ntsc_jfm_jbios, reg_current_mode, setled_yellow_flash

setled_off
    movlw   code_led_off
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_green
    movlw   code_led_green
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_red
    movlw   code_led_red
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_yellow
    movlw   code_led_yellow
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_yellow_flash
    M_skipnext_fm_present
    goto            setled_yellow
;    call            setled_yellow
;    M_delay_x10ms   repetitions_300ms
    call            setled_off
    M_delay_x10ms   repetitions_300ms
    call            setled_yellow
    M_delay_x10ms   repetitions_300ms
    call            setled_off
    M_delay_x10ms   repetitions_300ms
    call            setled_yellow
    M_movlf repetitions_300ms, reg_repetition_cnt   ; short the mode delay time (this line has no effect on startup)
    return

save_mode
    movfw   reg_current_mode
    banksel EEADR
    movwf   EEDAT
    bsf     EECON1,WREN
    movlw   0x55
    movwf   EECON2
    movlw   0xaa
    movwf   EECON2
    bsf     EECON1, WR
    banksel PORTA
    return


delay_10ms
    M_movlf delay_10ms_t0_overflows, reg_overflow_cnt
    clrf    W
    movwf   TMR0    ; start timer

delay_10ms_loop_pre
    bcf     INTCON, T0IF

delay_10ms_loop
    btfss   INTCON, T0IF
    goto    delay_10ms_loop
    decfsz  reg_overflow_cnt, 1
    goto    delay_10ms_loop_pre
    return

delay_x10ms
    call    delay_10ms
    decfsz  reg_repetition_cnt, 1
    goto    delay_x10ms
    return

; --------initialization--------

start
    clrf    PORTA
    clrf    PORTC
    M_movlf 0x07, CMCON                 ; GPIO2..0 are digital I/O (not connected to comparator)
    M_movlf 0x28, INTCON                ; enable interrupts: T0IE and RAIE
    banksel TRISA                       ; Bank 1
    call    3FFh                        ; Get the cal value
    movwf   OSCCAL                      ; Calibrate
    M_movlf 0x3d, TRISA                 ; in in in in out in
    M_movlf 0x0f, TRISC                 ; out out in in in in
    M_movlf (1<<NRESET_BUTTON), IOCA    ; IOC at reset button
    M_movlf 0x31, WPUA                  ; weak pullup on BIOS pins and reset button
    M_movlf 0x01, OPTION_REG            ; global pullup disable, prescaler T0 1:4
    banksel PORTA                       ; Bank 0

load_mode
    clrf    reg_current_mode
    clrf    reg_previous_mode
    bcf     STATUS, C           ; clear carry
    banksel EEADR               ; fetch current mode from EEPROM
    clrf    EEADR               ; address 0
    bsf     EECON1, RD
    movf    EEDAT, w
    banksel PORTA
    movwf   reg_current_mode    ; last mode saved
    movwf   reg_previous_mode   ; last mode saved to compare

set_initial_mode
    ; strategie: try to set mode, set if valid, set to default if not
    M_belf  code_pal, reg_current_mode, set_pal
    M_belf  code_ntsc, reg_current_mode, set_ntsc
    M_belf  code_ntsc_fm, reg_current_mode, set_ntsc_fm
    M_belf  code_ntsc_jfm_jbios, reg_current_mode, set_ntsc_jap
    goto    set_default  ; should not appear

set_pal
    M_set50
    M_setBIOS_EU
    goto    init_end

set_default
    movlw   default_mode
    movwf   reg_current_mode
    movwf   reg_previous_mode

set_ntsc
    M_set60
    M_setBIOS_EU
    goto    init_end

set_ntsc_fm
    M_skipnext_fm_present
    goto    set_default
    M_setFMSEB_EN
    M_setBIOS_EU
    goto    init_end

set_ntsc_jap
    M_skipnext_fm_present
    goto    set_ntsc_jbios_only
    M_setJFMSEB_EN
    M_setBIOS_JAP
    goto    init_end

set_ntsc_jbios_only
    M_skipnext_bios_present
    goto    set_default
    M_setBIOS_JAP

init_end
    call    save_mode
    call    setled
    goto    idle

; -----------------------------------------------------------------------
; eeprom data
DEEPROM	CODE
	de	default_mode

theend
    END
; ------------------------------------------------------------------------
