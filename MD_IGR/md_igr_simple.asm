#include  <p12f629.inc>

; -----------------------------------------------------------------------
;   A simple IGR code for the Mega Drive designed to run on a PIC12F629
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
;   This program is designed to run on a PIC 12F629 microcontroller.
;
;   pin configuration:
;
;                                 ,----__----.
;                             +5V |1        8| GND
;                   Ext.Mode [in] |2  G5 G0 7| [in/out] Reset Button
;     Ctrl.Port Pin 6 (B+A)  [in] |3  G4 G1 6| [in/out] CPU /HALT
;     Ctrl.Port Pin 9 (C+St) [in] |4  G3 G2 5| [in] n.c. 
;                                 `----------'
;
;  Special Features:
;
;    Ext.Mode (Pin 2)
;      - pin set to low: extended mode is switched off.
;          The microcontroller simply resets the the console for a few
;          milliseconds if the buttons St+A+B+C are held for 1.5seconds at the
;          controller pad.
;      - pin set to high: extended mode is switched on.
;          The microcontroller outputs a reset if the buttons St+A+B+C are held
;          for 1.5s at the controller pad. The reset is then held as long as the
;          button combination is held.
;          This mode can be used if you have a switchless mod installed in your
;          Mega Drive to switch between the modes there.
;          Further, the CPU is paused during that time such that the game does
;          not run if you have pin 3 of the microcontroller connected.
;
;    CPU /HALT (pin 6)
;      Used to pause the game during. The game is only paused in the extended
;      mode (see description above) after St+A+B+C is pressed for 1.5 seconds.
;      CPU /HALT is also triggered if a push on the reset button is triggered.
;      This allows the user, if a switchless mod is installed, to change the
;      mode without the game is running.
;      Connect this pin to:
;        - MD1 CPU (DIL package) pin 17
;        - MD2 CPU (PLCC package) pin 19
;      if this feature is wanted. If this feature is not wanted, leave this pin
;      unconnected.
;
;    Reset Button (pin 7)
;      This pin has to be connected to the reset button. The code will sense how
;      the button is connected, i.e., either as an low-active or high-active
;      reset.
;   
;
;
; Configuration bits: adapt to your setup and needs
    __CONFIG _INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_ON & _MCLRE_OFF & _BODEN_ON & _CP_OFF & _CPD_OFF

Calibrate_OSCCAL  set 1 ; 0 = no calibration, 1 = with calibration

; -----------------------------------------------------------------------
; macros and definitions

M_movlf macro   literal, toReg  ; move literal to filereg
        movlw   literal
        movwf   toReg
        endm

M_delay_x10ms   macro   literal ; delay about literal x 10ms
                movlw   literal
                movwf   reg_repetition_cnt
                call    delay_x10ms
                endm

M_T1reset   macro   ; reset and start timer1
            clrf    TMR1L
            clrf    TMR1H
            clrf    PIR1
            bsf     T1CON, TMR1ON
            endm

M_push_reset    macro             ; macro pauses CPU, too
                banksel TRISIO
                movlw   0x3c
                movwf   TRISIO    ; in in in in out out
                banksel GPIO
                movfw   reg_reset_type
                movwf   GPIO
                endm

M_release_reset macro             ; macro runs CPU, too
                movfw   reg_reset_type
                xorlw   (1<<RST_BUTTON) ^ (1<<CPU_NHALT)
                movwf   GPIO
                banksel TRISIO
                movlw   0x3f
                movwf   TRISIO    ; in in in in in in
                banksel GPIO
                endm

M_pause_CPU macro
            banksel TRISIO
            bcf     TRISIO, CPU_NHALT
            banksel GPIO
            bcf     GPIO, CPU_NHALT
            endm

M_run_CPU macro
          bsf     GPIO, CPU_NHALT
          banksel TRISIO
          bsf     TRISIO, CPU_NHALT
          banksel GPIO
          endm

M_skipnext_rst_pressed  macro
                        movfw   GPIO
                        xorwf   reg_reset_type, 0
                        andlw   (1<<RST_BUTTON)
                        btfss   STATUS, Z
                        endm

M_skipnext_rst_notpressed   macro
                            movfw   GPIO
                            xorwf   reg_reset_type, 0
                            andlw   (1<<RST_BUTTON)
                            btfsc   STATUS, Z
                            endm

; -----------------------------------------------------------------------
; bits and registers and more

RST_BUTTON  EQU 0
CPU_NHALT   EQU 1
CTRL_P9     EQU 3
CTRL_P6     EQU 4
EXTMODE     EQU 5

reg_reset_type      EQU 0x20
reg_overflow_cnt    EQU 0x21
reg_repetition_cnt  EQU 0x22

delay_10ms_t0_overflows EQU 0x14    ; prescaler T0 set to 1:2 @ 4MHz

; -----------------------------------------------------------------------

; code memory
 org    0x0000
    clrf    STATUS      ; 00h Page 0, Bank 0
    nop                 ; 01h
    nop                 ; 02h
    goto    start       ; 03h Initialiizing / begin program

ISR org    0x0004  ; jump here on interrupt with GIE set (should not appear)
    return      ; return with GIE unset

idle  org    0x0005
    bcf   T1CON, TMR1ON
    M_skipnext_rst_notpressed
    goto  check_rst_button
    btfss GPIO, CTRL_P9
    goto  check_ctrl
    bcf   INTCON, GPIF
    sleep

    btfss GPIO, CTRL_P9 ; interupt caused by controller?
    goto  check_ctrl    ; yes -> goto controller loop

check_rst_button        ; no -> check reset button
    call  delay_10ms    ; debounce
    call  delay_10ms    ; debounce
    M_skipnext_rst_pressed
    goto  idle
    M_pause_CPU

check_rst_button_loop
    M_skipnext_rst_notpressed
    goto  check_rst_button_loop
    M_run_CPU
    goto  idle
    
check_ctrl ; this point is entered if Pin 9 of the controller port goes low
    btfsc GPIO, CTRL_P6 ; P6 also low?
    goto  idle          ; no -> back to idle
    ; P6 also low -> prepare the 1.5s (indeed, the time is around 1.573ms)
    M_movlf 0x03, reg_overflow_cnt
    M_T1reset           ; start timer 1

check_ctrl_loop
    btfsc   GPIO, CTRL_P6       ; P6 still low?
    goto    idle                ; no -> back to idle
    btfsc   GPIO, CTRL_P9       ; P9 still low?
    goto    idle                ; no -> back to idle
    btfss   PIR1, TMR1IF        ; timer 1 overflow?
    goto    check_ctrl_loop
    clrf    PIR1                ; clear overflow bit
    decfsz  reg_overflow_cnt, 1 ; Are all loops done?
    goto    check_ctrl_loop     ; If no, repeat this loop
    bcf     T1CON, TMR1ON
    
do_reset ; St+A+B+C were held for 1.5s
    M_push_reset        ; this macro pauses the CPU, too
    M_delay_x10ms 0x08
    btfss GPIO, EXTMODE ; extended mode enabled?
    goto  reset_end     ; no -> simply reset
    
ext_mode_loop
    btfsc   GPIO, CTRL_P6 ; P6 still low?
    goto    reset_end     ; no -> end_loop
    btfss   GPIO, CTRL_P9 ; P9 still low?
    goto    ext_mode_loop ; yes -> stay in this loop
    
reset_end
    M_release_reset     ; this macro starts the CPU, too
    M_delay_x10ms 0x3c  ; time (600ms) for the user to release the button comb.
    goto idle
          
delay_10ms
    clrf    TMR0                ; start timer (operation clears prescaler of T0 to 1:2)
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
    
; initialisation    
start
    clrf    GPIO
    M_movlf 0x07, CMCON     ; GPIO2..0 are digital I/O (not connected to comparator)
    M_movlf 1<<GPIE, INTCON ; react on GPIE (to detect possibly pressed button combination)
    banksel TRISIO
  if Calibrate_OSCCAL
    call    3FFh            ; Get the osccal value
  else
    movlf   0xfc
  endif
    movwf   OSCCAL          ; Calibrate
    M_movlf 0x3F, TRISIO    ; in in in in in in
    M_movlf 0x09, IOC       ; IOC at GPIO3 (CTRL_P9) and GPIO0 (RST_BUTTON)
    M_movlf 0x06, WPU       ; pull-ups at GPIO2 (n.c.) and GPIO1 (CPU /HALT)
    clrf    OPTION_REG      ; global pull-ups enabled, prescaler T0 1:2
    banksel GPIO
    M_movlf 0x30, T1CON     ; set prescaler T1 1:8

detect_reset_type
    clrf    reg_reset_type
    btfss   GPIO, RST_BUTTON             ; skip next for low-active reset
    bsf     reg_reset_type, RST_BUTTON
    goto    idle

theend
    END
; ------------------------------------------------------------------------
