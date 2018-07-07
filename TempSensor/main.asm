;
; main.asm
;
; Created: 15/06/2018 18:54:18
; Author : Graham
;

; include files
.include "tn45def.inc"

.DEF MAIN_TEMP_REGISTER = r22

; reset vector
.ORG 0x0000
	RJMP main ; jump to main on a reset

; timer 0 compare match vector
.ORG 0x0020
	RJMP ISR_TIMER0_CTC

; main program entry point
main:
;
; init the other modules?
RCALL PRT_init ; initialise the GPIO port
RCALL TMR_init ; intialise the system timer
RCALL LED_init ; initialise the LED module
RCALL ADC_init ; initialise the ADC peripheral
RCALL TWI_init ; initialise the TWI peripheral
;
LDI TWI_DATA_REGISTER, 0x12
RCALL TWI_transmit_data
;
SEI ; enable interrupts
;
; main super loop which performs tasks when intervals have expired
main_loop:
	CLI ; disable interrupts while checking timer count
	;
	CPI ADC_TIMER_COUNTER, MAX_ADC_TIMER_COUNT	; check for ADC timer count reached
	BRLT dont_perform_adc_sample	; branch to end if timer count not yet reached
		;
		CLR ADC_TIMER_COUNTER	; reset the adc timer count
		;
		RCALL ADC_startConversion; start an ADC conversion
		;
	dont_perform_adc_sample:
	;
	SEI	; enable interrupts after timer count has been checked
	;
	RCALL ADC_isConversionComplete ; get the status of the adc conversion
	;
	CPI ADC_TEMP_REGISTER, ADC_CONVERSION_COMPLETE	; compare if the adc temp register is adc conversion complete
	BRNE conversion_not_complete	; if conversion is not complete then skip updating the mode	
		; conversion is complete so check temperature
		RCALL LED_setTemperatureLeds
	conversion_not_complete:
	;
    RJMP main_loop	; return to start of main super loop

;;--------------------------------------------------------------------------------------------------------------------------
;;													Port Module Functions
;;--------------------------------------------------------------------------------------------------------------------------

.DEF PRT_TEMP_REGISTER = r18

.EQU PRT_RED_LED_BIT = 0x10
.EQU PRT_BLUE_LED_BIT = 0x02

.EQU PRT_TWI_CLOCK_BIT = 0x04
.EQU PRT_TWI_CLOCK_BIT_POSITION = 2
.EQU PRT_TWI_SDA_BIT = 0x01

; name: PRT_init
; desc: initialise the ports 
PRT_init:
	LDI PRT_TEMP_REGISTER, 0x37
	OUT DDRB, PRT_TEMP_REGISTER
	RET

; name: PRT_setBlueLed
; desc: sets the Blue LED on
PRT_setBlueLed:
	IN PRT_TEMP_REGISTER, PORTB
	SBR PRT_TEMP_REGISTER, PRT_BLUE_LED_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

; name: PRT_clearBlueLed
; desc: sets the Blue LED off
PRT_clearBlueLed:
	IN PRT_TEMP_REGISTER, PORTB
	CBR PRT_TEMP_REGISTER, PRT_BLUE_LED_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

; name: PRT_setRedLed
; desc: sets the Red LED on
PRT_setRedLed:
	IN PRT_TEMP_REGISTER, PORTB
	SBR PRT_TEMP_REGISTER, PRT_RED_LED_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

; name: PRT_clearRedLed
; desc: sets the Red LED off
PRT_clearRedLed:
	IN PRT_TEMP_REGISTER, PORTB
	CBR PRT_TEMP_REGISTER, PRT_RED_LED_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET
	
; name: PRT_setTwiClockLow
; desc: sets the twi clock line low 
PRT_setTwiClockLow:
	IN PRT_TEMP_REGISTER, PORTB
	CBR PRT_TEMP_REGISTER, PRT_TWI_CLOCK_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

; name: PRT_setTwiClockHigh
; desc: sets the twi clock line high 
PRT_setTwiClockHigh:
	IN PRT_TEMP_REGISTER, PORTB
	SBR PRT_TEMP_REGISTER, PRT_TWI_CLOCK_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

; name: PRT_setTwiSdaAsOutput
; desc: sets the twi sda line as an output 
PRT_setTwiSdaAsOutput:
	IN PRT_TEMP_REGISTER, DDRB
	CBR PRT_TEMP_REGISTER, PRT_TWI_SDA_BIT
	OUT DDRB, PRT_TEMP_REGISTER
	RET

; name: PRT_setTwiSdaAsInput
; desc: sets the twi sda line as an input 
PRT_setTwiSdaAsInput:
	IN PRT_TEMP_REGISTER, DDRB
	SBR PRT_TEMP_REGISTER, PRT_TWI_SDA_BIT
	OUT DDRB, PRT_TEMP_REGISTER
	RET

; name: PRT_setTwiSdaLow
; desc: sets the twi sda line low 
PRT_setTwiSdaLow:
	IN PRT_TEMP_REGISTER, PORTB
	CBR PRT_TEMP_REGISTER, PRT_TWI_SDA_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

; name: PRT_setTwiSdaHigh
; desc: sets the twi sda line high 
PRT_setTwiSdaHigh:
	IN PRT_TEMP_REGISTER, PORTB
	CBR PRT_TEMP_REGISTER, PRT_TWI_SDA_BIT
	OUT PORTB, PRT_TEMP_REGISTER
	RET

;;--------------------------------------------------------------------------------------------------------------------------
;;													LED Module Functions
;;--------------------------------------------------------------------------------------------------------------------------

.def LED_CURRENT_MODE = r20

; LED DISPLAY MODES
.EQU LED_LOW_TEMPERATURE = 0x01
.EQU LED_MEDIUM_TEMPERATURE = 0x02 
.EQU LED_HIGH_TEMPERATURE = 0x04

.EQU LED_LOW_TO_MEDIUM_THRESHOLD = 40		// 16.8°C approx
.EQU LED_MEDIUM_TO_HIGH_THRESHOLD = 47		// 19.8°C approx
.EQU LED_MEDIUM_TO_LOW_THRESHOLD = 38		// 16.0°C approx
.EQU LED_HIGH_TO_MEDIUM_THRESHOLD = 45		// 18.8°C approx

; name: LED_init
; desc: initialises the led status display variables
LED_init:
	RCALL LED_setLowMode
	RET

; name: LED_setTemperatureLeds
; desc: sets the LED's based on the adc conversion result	
LED_setTemperatureLeds:
	RCALL ADC_getConversionResult	; get the result of the conversion, this will be in ADC_TEMP_REGISTER
	;
	CPI LED_CURRENT_MODE, LED_LOW_TEMPERATURE	; check if the current led mode is low temperature
	BRNE check_medium_mode	; branch to check if mode is medium temperature 
		;
		CPI ADC_TEMP_REGISTER, LED_LOW_TO_MEDIUM_THRESHOLD ; check if temperature will move us to the medium mode 
		BRLT end_of_mode_checking	; if adc conversion result is less than threshold then skip this
			RCALL LED_setMediumMode	; else update the mode to Medium
		;
		RJMP end_of_mode_checking	; matching mode found so jump to the end
		;
	check_medium_mode:
	;
	CPI LED_CURRENT_MODE, LED_MEDIUM_TEMPERATURE	; check if the current led mode is medium temperature
	BRNE check_high_mode	; branch to check if mode is high temperature 
		;
		CPI ADC_TEMP_REGISTER, LED_MEDIUM_TO_LOW_THRESHOLD	; check if temperature will move us to the low mode 
		BRGE check_for_med_to_high		; if adc conversion result is greater than threshold then skip this and check for medium to high change
			RCALL LED_setLowMode		; else update the mode to low
			RJMP end_of_mode_checking	; then go to end of mode checking
		check_for_med_to_high:
		CPI ADC_TEMP_REGISTER, LED_MEDIUM_TO_HIGH_THRESHOLD	;  check if temperature will move us to the high mode 
		BRLT end_of_mode_checking		; if adc conversion result is less than threshold then skip this
			RCALL LED_setHighMode		; else update the mode to high
		;
		RJMP end_of_mode_checking	; matching mode found so jump to the end
		;
	check_high_mode:
	;
	CPI LED_CURRENT_MODE, LED_HIGH_TEMPERATURE	; check if the current led mode is high temperature
	BRNE end_of_mode_checking	; should not get to this branch TODO - add error maybe 
		;
		CPI ADC_TEMP_REGISTER, LED_HIGH_TO_MEDIUM_THRESHOLD	; check if temperature will move us to the medium mode 
		BRGE end_of_mode_checking		; if adc conversion result is greater than threshold then skip this
			RCALL LED_setMediumMode		; else update the mode to medium
		;
		RJMP end_of_mode_checking	; matching mode found so jump to the end
		;
	end_of_mode_checking:
	RET

; name: LED_setLowMode
; desc: sets the LED state to low mode
LED_setLowMode:
	RCALL PRT_setBlueLed	; set led pattern and change mode for now
	RCALL PRT_clearRedLed
	;
	LDI LED_CURRENT_MODE, LED_LOW_TEMPERATURE	; set the mode to low
	RET

; name: LED_setMediumMode
; desc: sets the LED state to medium mode
LED_setMediumMode:
	RCALL PRT_clearBlueLed	; set led pattern and change mode
	RCALL PRT_clearRedLed
	;
	LDI LED_CURRENT_MODE, LED_MEDIUM_TEMPERATURE	; set the mode to medium
	RET

; name: LED_setHighMode
; desc: sets the LED state to high mode
LED_setHighMode:
	RCALL PRT_clearBlueLed	; set led pattern and change mode
	RCALL PRT_setRedLed
	;
	LDI LED_CURRENT_MODE, LED_HIGH_TEMPERATURE	; set the mode to high
	RET

;;--------------------------------------------------------------------------------------------------------------------------
;;													Timer Module Functions
;;--------------------------------------------------------------------------------------------------------------------------

.DEF TMR_TEMP_REGISTER = r23

.EQU CLEAR_TIMER_COMPARE_VALUE = 98	; CTC value for 10Hz 

; name: TMR_init
; desc: initialises the timer for a 10mS tick
TMR_init:
	; Set Clear timer on compare match mode
	IN TMR_TEMP_REGISTER, TCCR0A
	SBR TMR_TEMP_REGISTER, 2
	OUT TCCR0A, TMR_TEMP_REGISTER
	;
	; clock div 1024
	LDI TMR_TEMP_REGISTER, 0x05
	OUT TCCR0B, TMR_TEMP_REGISTER
	;
	; set compare match value
	LDI TMR_TEMP_REGISTER, CLEAR_TIMER_COMPARE_VALUE
	OUT OCR0A, TMR_TEMP_REGISTER
	;
	; interrupt enable
	LDI TMR_TEMP_REGISTER, 0x10
	OUT TIMSK, TMR_TEMP_REGISTER
	;
	; clear adc timer count
	CLR ADC_TIMER_COUNTER
	RET

; name: ISR_TIMER0_CTC
; desc: 10mS timer interrupt
ISR_TIMER0_CTC:
	INC ADC_TIMER_COUNTER
	RETI

;;--------------------------------------------------------------------------------------------------------------------------
;;													ADC Module Functions
;;--------------------------------------------------------------------------------------------------------------------------

.def ADC_TIMER_COUNTER = r19
.def ADC_TEMP_REGISTER = r21

; constant values
.EQU MAX_ADC_TIMER_COUNT = 5

.EQU ADC_INTERNAL_1_1V_REFERENCE = 0x80
.EQU ADC_LEFT_ADJUST_RESULT = 0x20
.EQU ADC_ADC3_MUX = 0x03

.EQU ADC_ENABLE_ADC	= 0x80
.EQU ADC_START_CONVERSION = 0x40
.EQU ADC_CONVERSION_COMPLETE = 0x10
.EQU ADC_INTERRUPT_ENABLE = 0x08
.EQU ADC_CLOCK_DIV_128 = 0x07

.EQU ADC_DISABLE_ADC3_DIGITAL_INPUT = 0x08

; name: ADC_init
; desc: initialises the ADC peripheral
ADC_init:
	; set the internal 1.1V reference, left adjusted result and ADC3 channel 
	LDI ADC_TEMP_REGISTER, ADC_INTERNAL_1_1V_REFERENCE
	SBR ADC_TEMP_REGISTER, ADC_LEFT_ADJUST_RESULT
	SBR ADC_TEMP_REGISTER, ADC_ADC3_MUX
	OUT ADMUX, ADC_TEMP_REGISTER
	;
	LDI ADC_TEMP_REGISTER, ADC_ENABLE_ADC
	SBR ADC_TEMP_REGISTER, ADC_CLOCK_DIV_128
	OUT ADCSRA, ADC_TEMP_REGISTER
	;
	LDI ADC_TEMP_REGISTER, ADC_DISABLE_ADC3_DIGITAL_INPUT
	OUT DIDR0, ADC_TEMP_REGISTER
	;
	RET

; name: ADC_startConversion
; desc: starts an ADC conversion
ADC_startConversion:
	IN ADC_TEMP_REGISTER, ADCSRA
	SBR ADC_TEMP_REGISTER, ADC_START_CONVERSION
	OUT ADCSRA, ADC_TEMP_REGISTER
	RET	

; name: ADC_isConversionComplete
; desc: sets the value in ADC_TEMP_REGISTER if the ADC conversion is complete
ADC_isConversionComplete:
	IN ADC_TEMP_REGISTER, ADCSRA
	ANDI ADC_TEMP_REGISTER, ADC_CONVERSION_COMPLETE
	RET

; name: ADC_getConversionResult
; desc: sets the value in ADC_TEMP_REGISTER to the ADC conversion result
ADC_getConversionResult:
	IN ADC_TEMP_REGISTER, ADCSRA
	OUT ADCSRA, ADC_TEMP_REGISTER	; clear the interrupt flag
	;
	IN ADC_TEMP_REGISTER, ADCH	; get the adc conversion result
	RET

	
;;--------------------------------------------------------------------------------------------------------------------------
;;													TWI Module Functions
;;--------------------------------------------------------------------------------------------------------------------------

.DEF TWI_TEMP_REGISTER = r24
.DEF TWI_DATA_REGISTER = r25

.EQU RELEASED_DATA = 0xFF
.EQU USICR_TWO_WIRE_MODE = 0x20
.EQU USICR_CLOCK_STROBE_MODE = 0x0A

.EQU USISR_START_CONDITION_FLAG = 0x80
.EQU USISR_COUNTER_OVERFLOW_FLAG = 0x40
.EQU USISR_STOP_CONDITION_FLAG = 0x20
.EQU USISR_DATA_COLLISION_FLAG = 0x10

; name: TWI_init
; desc: initialises the TWI peripheral
TWI_init:
	LDI TWI_TEMP_REGISTER, RELEASED_DATA
	OUT USIDR, TWI_TEMP_REGISTER			; set the initial data in the USIDR 
	;
	LDI TWI_TEMP_REGISTER, USICR_TWO_WIRE_MODE
	SBR TWI_TEMP_REGISTER, USICR_CLOCK_STROBE_MODE
	OUT USICR, TWI_TEMP_REGISTER			; set the USI for two wire mode 
	;
	LDI TWI_TEMP_REGISTER, USISR_START_CONDITION_FLAG
	SBR TWI_TEMP_REGISTER, USISR_COUNTER_OVERFLOW_FLAG
	SBR TWI_TEMP_REGISTER, USISR_STOP_CONDITION_FLAG
	SBR TWI_TEMP_REGISTER, USISR_DATA_COLLISION_FLAG
	OUT USISR, TWI_TEMP_REGISTER			; clear the condition flags
	;
	RET

; name: TWI_transmit_data
; desc: transmits data to the twi peripheral
TWI_transmit_data:
	RCALL PRT_setTwiClockHigh
	;
	wait_for_clock_line_to_go_high:
		;
		SBIS PORTB, PRT_TWI_CLOCK_BIT_POSITION
		RJMP wait_for_clock_line_to_go_high
	;
	RCALL TWI_shortDelay
	;

	RET

; name: TWI_shortDelay
; desc: short delay function 
TWI_shortDelay:
	
	RET

; name: TWI_longDelay
; desc: long delay function 
TWI_longDelay:
	
	RET