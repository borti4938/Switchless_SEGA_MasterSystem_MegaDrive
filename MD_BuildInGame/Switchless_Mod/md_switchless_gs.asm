#include <p16f630.inc>

;
; -----------------------------------------------------------------------
;
;	Sega Mega Drive switchless mod
;
;   Copyright (C) 2016 by Peter Bartmann
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
;          BIG Sel1 (out) |2  A5 A0 13| Reset Button (in)
;          BIG Sel0 (out) |3  A4 A1 12| Reset Line  (out)
;              /RoMC (in) |4  A3 A2 11|  Language   (out)
;       (green) LED (out) |5  C5 C0 10| /Language   (out)
;         (red) LED (out) |6  C4 C1  9|  Videomode  (out)
;           LED_TYPE (in) |7  C3 C2  8| /Videomode  (out)
;                         `-----------'
;
; Special purposes for pins and other common notes:
;
;   Pin 3 and Pin 2
;     A two bit counter which increases with each reset except after a reset if the
;     mode has been previously changed.
;     MSB is pin 2 and LSB is pin 3. These two pins can be used for the MD build-in-
;     game pcb.
;
;   Pin 4 (/RoMC = reset on mode change, neg. logic)
;      low = RoMC on   - PIC resets console if mode has been changed
;     high = RoMC off  - in this case only the bit at pin 9 (Videomode) is changed
;                        (the bit at pin 8 is unchanged until a reset to not change the
;                         memory bank in the MegaCD MultiBIOS)
;
;   Pin 9 (Videomode)    Pin 8 (/Videomode)
;      low = 50Hz           low = 60Hz
;     high = 60Hz          high = 50Hz
;                          -> Opposite of Pin 9
;
;   Pin 11 (Language)    Pin 10 (/Language)
;      low = Japanese       low = English
;     high = English       high = Japanese
;                          -> Opposite of Pin 11
;
;   Pin 13 (Reset Button)
;     The code should be able to detect the reset type by it's own without
;     any other components.
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

use_alternative_color_scheme set 0 ; 0 = normal, 1 = alternative

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
        bcf PORTC, VIDMODE
        bsf PORTC, NVIDMODE
        endm

M_set60 macro
        bsf PORTC, VIDMODE
        bcf PORTC, NVIDMODE
        endm

M_setEN macro
        bsf PORTA, LANGUAGE
        bcf PORTC, NLANGUAGE
        endm

M_setJA macro
        bcf PORTA, LANGUAGE
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
RST_OUT     EQU 1
LANGUAGE    EQU 2
NRoMC       EQU 3
BIG_Sel0    EQU 4
BIG_Sel1    EQU 5

;port c
NLANGUAGE   EQU 0
VIDMODE     EQU 1
NVIDMODE    EQU 2
LED_TYPE    EQU 3
LED_RED     EQU 4
LED_GREEN   EQU 5

; registers
reg_overflow_cnt    EQU 0x20
reg_repetition_cnt  EQU 0x21
reg_current_mode    EQU 0x30
reg_previous_mode   EQU 0x31
reg_mode_buffer     EQU 0x32
reg_mode_loop_cnt   EQU 0x33
reg_reset_type      EQU 0x40
reg_first_boot_done EQU 0x41

; codes and bits
code_ntsc           EQU 0x00
code_pal            EQU 0x01
code_jap            EQU 0x02

bit_language        EQU 1
bit_videomode       EQU 0

mode_loop_cnt   EQU 0x0c  ; should be a multiple of 3
                          ; here: cycle four times through the mode change loop
                          ;       before changing the ingame counter

code_led_off    EQU 0x00
code_led_green  EQU (1<<LED_GREEN)
code_led_red    EQU (1<<LED_RED)
code_led_orange EQU code_led_green ^ code_led_red

code_led_invert EQU code_led_green ^ code_led_red

delay_10ms_t0_overflows   EQU 0x14    ; prescaler T0 set to 1:2 @ 4MHz
repetitions_100ms         EQU 0x0a
repetitions_200ms         EQU 0x14
repetitions_260ms         EQU 0x1a
repetitions_big_chg_delay EQU 0x34    ; around 520ms
repetitions_mode_delay    EQU 0x4a    ; around 740ms

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

    M_movff reg_current_mode, reg_mode_buffer
    M_movlf mode_loop_cnt, reg_mode_loop_cnt

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

    decfsz  reg_mode_loop_cnt, 1
    goto    next_mode

    M_movff reg_mode_buffer, reg_current_mode ; just to be sure in case the mode loop
                                              ; doesn't end with the entered mode
    call  setled_off

next_big_loop ; change build-in-game loop
    M_delay_x10ms   repetitions_big_chg_delay
    M_skipnext_rst_pressed
    goto  next_big_loop_end ; exit this loop if the reset button has been released

    movlw   0x10
    addwf   reg_current_mode, 1   ; increase counter
    bcf     reg_current_mode, 6   ; keep the 2bit counter 2bits long
    call    show_big_code
    goto    next_big_loop

next_big_loop_end
    call  save_mode
    call  setled    ; change back to the initial LED color
    goto  idle


apply_mode ; save mode, set video mode and check if a reset is wanted
    call    save_mode
    btfsc   reg_current_mode, bit_videomode
    bcf     PORTC, VIDMODE                  ; 50Hz
    btfss   reg_current_mode, bit_videomode
    bsf     PORTC, VIDMODE                  ; 60Hz
    call    setled
    ; check if current mode and previous mode are the same
    movfw   reg_current_mode
    xorwf   reg_previous_mode, 0
    andlw   0x03
    btfsc   STATUS, Z
    goto    idle                    ; nothing has been changed -> return to idle
    btfsc   PORTA, NRoMC            ; auto-reset on mode change?
    goto    idle                    ; no: go back to idle
                                    ; yes: perform a reset


doreset
    M_push_reset
    call    setled
    M_delay_x10ms   repetitions_260ms
    goto    set_initial_mode           ; small trick ;)


set_previous_mode
    M_movff reg_previous_mode, reg_current_mode
    call    save_mode
    call    setled
    goto    idle

; --------calls--------
setled
    ; same strategie as in set_initial_mode
    btfsc   reg_current_mode, bit_language
  if use_alternative_color_scheme
    goto    setled_red
  else
    goto    setled_orange
  endif
    btfsc   reg_current_mode, bit_videomode
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

show_big_code
    btfss   reg_current_mode, 5
    call    setled_green
    btfsc   reg_current_mode, 5
    call    setled_red
    M_delay_x10ms   repetitions_260ms
    call    setled_off
    M_delay_x10ms   repetitions_260ms
    btfss   reg_current_mode, 4
    call    setled_green
    btfsc   reg_current_mode, 4
    call    setled_red
    M_delay_x10ms   repetitions_260ms
    call    setled_off
    return


save_mode
    movfw   reg_current_mode
    andlw   0x33
    banksel EEADR             ; save to EEPROM
    movwf   EEDAT
    clrf    EEADR             ; address 0
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
    banksel PORTA
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
    M_movlf 0x0b, TRISA             ; out out in out in in
    M_movlf 0x08, TRISC             ; out out in out out out
    M_movlf (1<<RST_BUTTON), IOCA   ; IOC at reset button
    M_movlf (1<<RST_BUTTON), WPUA   ; pullups at reset button
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
    andlw   0x33
    movwf   reg_current_mode    ; last mode saved

set_BIG_Sel
    movfw   reg_current_mode
    andlw   0x30
    btfsc   PORTA, LANGUAGE
    iorlw   0x01
    movwf   PORTA ; selects the build in game

set_initial_mode
    ; strategie: check language flag first as Jap-mode is always 60Hz
    ;            -> check language  at bit 1 (1 = jap , 0 = us/eur)
    ;            -> check videomode at bit 0 (1 = 50Hz, 0 = 60Hz  )
    btfsc   reg_current_mode, bit_language
    goto    set_jap
    bcf     reg_current_mode, bit_language
    btfsc   reg_current_mode, bit_videomode
    goto    set_pal

set_ntsc
    M_set60
    M_setEN
    bcf     reg_current_mode, bit_videomode
    goto    init_end

set_pal
    M_set50
    M_setEN
    bsf     reg_current_mode, bit_videomode
    goto    init_end

set_jap
    M_set60
    M_setJA
    bsf     reg_current_mode, bit_language
    bcf     reg_current_mode, bit_videomode
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
