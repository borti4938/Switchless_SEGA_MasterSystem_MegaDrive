#include <p16f630.inc>

;
; -----------------------------------------------------------------------
;
;	Sega Mega Drive switchless mod
;
;   Copyright (C) 2016 by Peter Bartmann
;
;   Adapted to ArcadeTV PCB by wshadow in 2018
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
;                    n.c. |2  A5 A0 13| Reset Button (in)
;              /RoMC (in) |3  A4 A1 12|  Videomode (out)
;                    n.c. |4  A3 A2 11| Reset Line (out)
;         (red) LED (out) |5  C5 C0 10| /Videomode (out)
;       (green) LED (out) |6  C4 C1  9|  Language  (out)
;           LED_TYPE (in) |7  C3 C2  8| /Language  (out)
;                         `-----------'
;
; Special purposes for pins and other common notes:
;
;   Pin 3 (/RoMC = reset on mode change, neg. logic)
;      low = RoMC on   - PIC resets console if mode has been changed
;     high = RoMC off  - in this case only the bit at pin 9 (Videomode) is changed
;                        (the bit at pin 8 is unchanged until a reset to not change the
;                         memory bank in the MegaCD MultiBIOS)
;
;   Pin 12 (Videomode)   Pin 10 (/Videomode)
;      low = 50Hz           low = 60Hz
;     high = 60Hz          high = 50Hz
;                          -> Opposite of Pin 9
;
;   Pin 9 (Language)     Pin 8 (/Language)
;      low = Japanese       low = English
;     high = English       high = Japanese
;                          -> Opposite of Pin 11
;
;   Pin 13 (Reset Button)
;     The code should be able to detect the reset type by it's own without
;     any other components.
;     
;     
; -----------------------------------------------------------------------
;
; mode description:
;
; mode 0x00 = PAL:           50Hz, LED green   (alternative: green)
; mode 0x01 = NTSC:          60Hz, LED red     (alternative: orange)
; mode 0x02 = JAP NTSC:      60Hz, LED orange  (alternative: red)
;      
; -----------------------------------------------------------------------
; Configuration bits: adapt to your setup and needs

    __CONFIG _INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _CPD_OFF

use_alternative_color_scheme set 1 ; 0 = normal, 1 = alternative
; -----------------------------------------------------------------------
; macros and definitions

M_movff macro   fromReg, toReg  ; move filereg to filereg
        movfw   fromReg
        movwf   toReg
        endm

M_movlf macro   literal, toReg  ; move literal to filereg
        movlw   literal
        movwf   toReg
        endm

M_movpf macro   fromPort, toReg
        movfw   fromPort
        andlw   0x3F
        movwf   toReg
        endm

M_beff  macro   compReg1, compReg2, branch  ; branch if two fileregs are equal
        movfw   compReg1
        xorwf	compReg2, w
        btfsc   STATUS, Z
        goto    branch
        endm

M_delay_x10ms   macro   literal ; delay about literal x 10ms
                movlw   literal
                movwf   reg_repetition_cnt
                call    delay_x10ms
                endm

M_push_reset    macro
                banksel TRISA
                bcf     TRISA, RST_OUT
                banksel PORTA
                bcf     PORTA, RST_OUT
                endm

M_release_reset macro
                bsf     PORTA, RST_OUT
                banksel TRISA
                bsf     TRISA, RST_OUT
                banksel PORTA
                endm

M_set50 macro
        bcf PORTA, VIDMODE
        bsf PORTC, NVIDMODE
        endm

M_set60 macro
        bsf PORTA, VIDMODE
        bcf PORTC, NVIDMODE
        endm

M_setEN macro
        bsf PORTC, LANGUAGE
        bcf PORTC, NLANGUAGE
        endm

M_setJA macro
        bcf PORTC, LANGUAGE
        bsf PORTC, NLANGUAGE
        endm

M_skipnext_rst_pressed  macro
                        movfw   PORTA
                        xorwf   reg_reset_type, 0
                        andlw   (1<<RST_BUTTON)
                        btfss   STATUS, Z
                        endm

M_skipnext_rst_notpressed   macro
                            movfw   PORTA
                            xorwf   reg_reset_type, 0
                            andlw   (1<<RST_BUTTON)
                            btfsc   STATUS, Z
                            endm
; -----------------------------------------------------------------------

;port a
RST_BUTTON  EQU 0
VIDMODE     EQU 1
RST_OUT     EQU 2
NRoMC       EQU 4

;port c
NVIDMODE    EQU 0
LANGUAGE    EQU 1
NLANGUAGE   EQU 2
LED_TYPE    EQU 3
LED_GREEN   EQU 4
LED_RED     EQU 5

; registers
reg_overflow_cnt    EQU 0x20
reg_repetition_cnt  EQU 0x21
reg_current_mode    EQU 0x30
reg_previous_mode   EQU 0x31
reg_reset_type      EQU 0x40
reg_first_boot_done EQU 0x41

; codes and bits
code_ntsc           EQU 0x00
code_pal            EQU 0x01
code_jap            EQU 0x02

mode_overflow       EQU 0x03
bit_language        EQU 1
bit_videomode       EQU 0


code_led_off    EQU 0x00
code_led_green  EQU (1<<LED_GREEN)
code_led_red    EQU (1<<LED_RED)
code_led_orange EQU code_led_green ^ code_led_red

code_led_invert EQU code_led_green ^ code_led_red

delay_10ms_t0_overflows EQU 0x14    ; prescaler T0 set to 1:2 @ 4MHz
repetitions_100ms       EQU 0x0a
repetitions_200ms       EQU 0x14
repetitions_260ms       EQU 0x1a
repetitions_mode_delay  EQU 0x4a    ; around 740ms

; -----------------------------------------------------------------------

; code memory
 org    0x0000
    clrf    STATUS  ; 00h Page 0, Bank 0
    nop             ; 01h
    nop             ; 02h
    goto    start   ; 03h begin program / Initializing

 org    0x0004  ; jump here on interrupt with GIE set (should not appear)
    return      ; return with GIE unset

 org    0x0005
idle
    bcf     INTCON, RAIF
    M_skipnext_rst_pressed
    sleep

check_rst
    call    delay_10ms                      ; software debounce
    call    delay_10ms                      ; software debounce
    M_skipnext_rst_pressed
    goto    idle

    call    setled_off
    M_movlf repetitions_mode_delay, reg_repetition_cnt

check_rst_loop
    call    delay_10ms
    M_skipnext_rst_pressed
    goto    doreset
    decfsz  reg_repetition_cnt, 1
    goto    check_rst_loop
    
next_mode
    btfsc   reg_current_mode, bit_language
    goto    next_mode_00
    incf    reg_current_mode, 1
    goto    mode_delay
next_mode_00
;    bcf     reg_current_mode, bit_videomode
    bcf     reg_current_mode, bit_language

mode_delay
    call    setled
    M_movlf repetitions_mode_delay, reg_repetition_cnt

mode_delay_loop
    call    delay_10ms
    M_skipnext_rst_pressed
    goto    apply_mode
    decfsz  reg_repetition_cnt, 1
    goto    mode_delay_loop
    goto    next_mode


apply_mode ; save mode, set video mode and check if a reset is wanted
    call    save_mode
    btfsc   reg_current_mode, bit_videomode
    bcf     PORTA, VIDMODE                  ; 50Hz
    btfss   reg_current_mode, bit_videomode
    bsf     PORTA, VIDMODE                  ; 60Hz
    call    setled
    M_beff  reg_current_mode, reg_previous_mode, idle ; nothing has been changed -> return to idle
    btfsc   PORTA, NRoMC                              ; auto-reset on mode change?
    goto    idle                                      ; no: go back to idle 
                                                      ; yes: perform a reset

doreset
    M_push_reset
    call    setled
    M_delay_x10ms   repetitions_260ms
    goto    set_initial_mode            ; small trick ;)

set_previous_mode
    M_movff reg_previous_mode, reg_current_mode
    call    save_mode
    call    setled
    goto    idle

; --------calls--------
setled
    ; same strategie as in set_initial_mode
    btfsc   reg_current_mode, bit_language ; skip if LNG is set to non-jap
  if use_alternative_color_scheme
    goto    setled_red
  else
    goto    setled_orange
  endif
    btfsc   reg_current_mode, bit_videomode ; skip if HZ is set to 60
    goto    setled_green
  if use_alternative_color_scheme
    goto    setled_orange
  endif

setled_red
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_red
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_green
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_green
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_orange
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_orange
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return

setled_off
    movfw   PORTC
    andlw   0x0f
    xorlw   code_led_off
    btfsc   PORTC, LED_TYPE ; if common anode:
    xorlw   code_led_invert ; invert output
    movwf   PORTC
    return


save_mode
    movfw   reg_current_mode
    banksel EEADR           ; save to EEPROM. note: banksels take two cycles each!
    movwf   EEDAT
    clrf    EEADR           ; address 0
    bsf     EECON1, WREN
    movlw   0x55
    movwf   EECON2
    movlw   0xaa
    movwf   EECON2
    bsf     EECON1, WR
wait_save_mode_end
    btfsc   EECON1, WR
    goto    wait_save_mode_end
    bcf     EECON1, WREN
    banksel PORTA           ; two cycles again
    return

delay_10ms
    clrf    TMR0                ; start timer (operation clears prescaler of T0)
    banksel TRISA
    movfw   OPTION_REG
    andlw   0xf0
    movwf   OPTION_REG
    banksel PORTA
    M_movlf delay_10ms_t0_overflows, reg_overflow_cnt
    bsf     INTCON, T0IE        ; enable timer 0 interrupt

delay_10ms_loop_pre
    bcf     INTCON, T0IF

delay_10ms_loop
    btfss   INTCON, T0IF
    goto    delay_10ms_loop
    decfsz  reg_overflow_cnt, 1
    goto    delay_10ms_loop_pre
    bcf     INTCON, T0IE        ; disable timer 0 interrupt
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
    M_movlf 0x07, CMCON             ; GPIO2..0 are digital I/O (not connected to comparator)
    M_movlf 0x08, INTCON            ; enable interrupts: RAIE
    banksel TRISA                   ; Bank 1
    call    3FFh                    ; Get the cal value
    movwf   OSCCAL                  ; Calibrate
    M_movlf 0x3D, TRISA             ; NC NC in in in in out in (RESET_OUT intentionally initialized as input)
    M_movlf 0x08, TRISC             ; NC NC out out in out out out
    M_movlf (1<<RST_BUTTON), IOCA   ; IOC at reset button
    M_movlf 0x31, WPUA              ; pullups at unused pins and reset button
    clrf    OPTION_REG              ; global pullup enable, prescaler T0 1:2
    banksel PORTA                   ; Bank 0


load_mode
    clrf    reg_first_boot_done
    clrf    reg_current_mode
    bcf     STATUS, C           ; clear carry
    banksel EEADR               ; fetch current mode from EEPROM
    clrf    EEADR               ; address 0
    bsf     EECON1, RD
    movfw   EEDAT
    banksel PORTA
    movwf   reg_current_mode    ; last mode saved

set_initial_mode
    ; strategie: check language flag first as Jap-mode is always 60Hz
    ;            -> check language  at bit 1 (1 = jap , 0 = us/eur)
    ;            -> check videomode at bit 0 (1 = 50Hz, 0 = 60Hz  )
    btfsc   reg_current_mode, bit_language
    goto    set_jap
    btfsc   reg_current_mode, bit_videomode
    goto    set_pal

set_ntsc
    M_set60
    M_setEN
    M_movlf code_ntsc, reg_current_mode ; in case a non-valid mode is stored
    goto    init_end

set_pal
    M_set50
    M_setEN
    M_movlf code_pal, reg_current_mode  ; in case a non-valid mode is stored
    goto    init_end

set_jap
    M_set60
    M_setJA
    M_movlf code_jap, reg_current_mode  ; in case a non-valid mode is stored
;    goto    init_end 

init_end
    call    save_mode
    call    setled
    M_release_reset
    clrf    reg_previous_mode
    M_movff reg_current_mode, reg_previous_mode ; last mode saved to compare
    btfsc   reg_first_boot_done, 0
    goto    idle
    bsf     reg_first_boot_done, 0

detect_reset_type
    clrf    reg_reset_type
    btfss   PORTA, RST_BUTTON             ; skip next for low-active reset
    bsf     reg_reset_type, RST_BUTTON
    goto    idle

; -----------------------------------------------------------------------
; eeprom data
DEEPROM	CODE
	de	code_ntsc

theend
    END
; ------------------------------------------------------------------------
