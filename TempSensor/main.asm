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

; constant values
.EQU MAX_ADC_TIMER_COUNT = 20
.EQU CLEAR_TIMER_COMPARE_VALUE = 98	; CTC value for 10Hz 

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
	;
	; set the initial led values
	RCALL PRT_clearGreenLed
	RCALL PRT_setRedLed

	SEI ; enable interrupts

; main super loop which performs tasks when intervals have expired
main_loop:
	CLI
	CPI ADC_TIMER_COUNTER, MAX_ADC_TIMER_COUNT
	BRLT dont_perform_adc_sample
		RCALL PRT_setGreenLed
		RCALL PRT_clearRedLed
dont_perform_adc_sample:
	SEI
    RJMP main_loop

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