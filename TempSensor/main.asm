;
; TempSensor.asm
;
; Created: 15/06/2018 18:54:18
; Author : Graham
;

; include files
.include "tn45def.inc"

; definitions for registers
.def ADC_TIMER_COUNTER = r19
.def LED_CURRENT_MODE = r20

; constant values
.EQU MAX_ADC_TIMER_COUNT = 20
.EQU CLEAR_TIMER_COMPARE_VALUE = 98	; CTC value for 10Hz 

; LED DISPLAY MODES
.EQU LED_LOW_TEMPERATURE = 0x01
.EQU LED_MEDIUM_TEMPERATURE = 0x02 
.EQU LED_HIGH_TEMPERATURE = 0x04

; reset vector
.org 0x0000
	RJMP main ; jump to main on a reset

; timer 0 compare match vector
.org 0x0020
	RJMP ISR_TIMER0_CTC

; main program entry point
main:
	; init the other modules?
	RCALL PRT_init
	RCALL TMR_init
	RCALL LED_init
	;
	; set the initial led values
	RCALL PRT_clearGreenLed
	RCALL PRT_setRedLed

	SEI ; enable interrupts

; main super loop which performs tasks when intervals have expired
main_loop:
	CLI ; disable interrupts while checking timer count
	;
	CPI ADC_TIMER_COUNTER, MAX_ADC_TIMER_COUNT	; check for ADC timer count reached
	BRLT dont_perform_adc_sample	; branch to end if timer count not yet reached
		;
		CLR ADC_TIMER_COUNTER	; reset the adc timer count
		;
		CPI LED_CURRENT_MODE, LED_LOW_TEMPERATURE	; check if the current led mode is low temperature
		BRNE check_medium_mode	; branch to check if mode is medium temperature 
			;
			RCALL PRT_setGreenLed	; set led pattern and change mode for now
			RCALL PRT_clearRedLed
			;
			LDI LED_CURRENT_MODE, LED_MEDIUM_TEMPERATURE
			;
			RJMP end_of_mode_checking	; matching mode found so jump to the end
			;
		check_medium_mode:
		;
		CPI LED_CURRENT_MODE, LED_MEDIUM_TEMPERATURE	; check if the current led mode is medium temperature
		BRNE check_high_mode	; branch to check if mode is high temperature 
			;
			RCALL PRT_clearGreenLed	; set led pattern and change mode for now
			RCALL PRT_setRedLed
			;
			LDI LED_CURRENT_MODE, LED_HIGH_TEMPERATURE
			;
			RJMP end_of_mode_checking	; matching mode found so jump to the end
			;
		check_high_mode:
		;
		CPI LED_CURRENT_MODE, LED_HIGH_TEMPERATURE	; check if the current led mode is high temperature
		BRNE end_of_mode_checking	; should not get to this branch TODO - add error maybe 
			;
			RCALL PRT_setGreenLed	; set led pattern and change mode for now
			RCALL PRT_setRedLed
			;
			LDI LED_CURRENT_MODE, LED_LOW_TEMPERATURE
			;
			RJMP end_of_mode_checking	; matching mode found so jump to the end
			;
		end_of_mode_checking:
	;
	dont_perform_adc_sample:
	SEI	; enable interrupts after timer count has been checked
    RJMP main_loop	; return to start of main super loop

; name: PRT_init
; desc: initialise the ports 
PRT_init:
	LDI r18, 0x1F
	OUT DDRB, r18
	RET

; name: PRT_setGreenLed
; desc: sets the green LED on
PRT_setGreenLed:
	IN r18, PORTB
	SBR r18, 0x10
	OUT PORTB, r18
	RET

; name: PRT_clearGreenLed
; desc: sets the green LED off
PRT_clearGreenLed:
	IN r18, PORTB
	CBR r18, 0x10
	OUT PORTB, r18
	RET

; name: PRT_setRedLed
; desc: sets the Red LED on
PRT_setRedLed:
	IN r18, PORTB
	SBR r18, 0x02
	OUT PORTB, r18
	RET

; name: PRT_clearRedLed
; desc: sets the Red LED off
PRT_clearRedLed:
	IN r18, PORTB
	CBR r18, 0x02
	OUT PORTB, r18
	RET

; name: LED_init
; desc: initialises the led status display variables
LED_init:
	LDI LED_CURRENT_MODE, LED_LOW_TEMPERATURE
	RET

; name: TMR_init
; desc: initialises the timer for a 10mS tick
TMR_init:
	; Set Clear timer on compare match mode
	IN r18, TCCR0A
	SBR r18, 2
	OUT TCCR0A, r18
	;
	; clock div 1024
	LDI r18, 0x05
	OUT TCCR0B, r18
	;
	; set compare match value
	LDI r18, CLEAR_TIMER_COMPARE_VALUE
	OUT OCR0A, r18
	;
	; interrupt enable
	LDI r18, 0x10
	OUT TIMSK, r18
	;
	; clear adc timer count
	CLR ADC_TIMER_COUNTER
	RET

; name: ISR_TIMER0_CTC
; desc: 10mS timer interrupt
ISR_TIMER0_CTC:
	INC ADC_TIMER_COUNTER
	RETI