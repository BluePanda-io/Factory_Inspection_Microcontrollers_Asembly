;Poulakas Giannis 8678
;Saratzidis Miltiadis 8237


.include "m16def.inc"

;The interrupt routine flag register's bits are explained below
;To activate a bit, we set its value to 0
;	bit 0 -> bit not used
;	bit 1 -> clear bit when silo 1 has less material than its lower limit indicates
;	bit 2 -> clear bit when motor 1 is overheated and Q1 opens
;	bit 3 -> clear bit when motor 2 is overheated and Q2 opens
;	bit 4 -> clear bit when the STOP button is pressed
;	bit 5 -> clear bit when silo 1 exceeds its maximum limit and overflows
;	bit 6 -> clear bit when silo 2 exceeds its maximum limit and overflows
;	bit 7 -> clear bit when we wait for the timer overflow and ISR execution to complete








;Defining some register names and giving some initial values
.equ LIM_A1       	= 130		; SAFETY LOWER LIMIT OF THE MAIN SILO -> PA0	
.equ LIM_B1       	= 100 		; LOWER LIMIT OF SILO 1               -> PA1		
.equ LIM_B2       	= 200     	; UPPER LIMIT OF SILO 1               -> PA2	
.equ LIM_B3       	= 120	   	; LOWER LIMIT OF SILO 2               -> PA3		
.equ LIM_B4       	= 220     	; UPPER LIMIT OF SILO 2			      -> PA4

	
.def tempr          = R16      	; THIS REGISTER IS USED FOR TEMPORARY ASSIGNMENTS
.def flg         	= R17      	; THIS REGISTER IS USED AS FLAG FOR THE INTERRUPT ROUTINE ACTIONS
.def LED_flag       = R18      	; THIS REGISTER IS USED TO HANDLE THE LED BLINKS
.def EROR_flag      = R19      	; THIS REGISTER IS USED TO INDICATE WHICH ERROR HAS OCCYRED
.def silo_1_full    = R20      	; THIS REGISTER IS USED TO INDICATE THAT SILO 1 IS FULL




;Starting the code segment
.cseg
;Defining the reset routine
.org 0
rjmp RESET
;Defining the timer overflow routine
.org $010
rjmp tm1_ovf



.org $100
RESET:
	;stack pointer
	ldi tempr,low(RAMEND)
	out SPL,tempr
	ldi tempr,high(RAMEND)
	out SPH,tempr
	;PORTA as input
	ldi tempr,0b00000000
	out DDRA,tempr
	;PORTB as output
	ldi tempr,0b11111111
	out DDRB,tempr
	;PORTC as output
	ldi tempr,0b11111111
	out DDRC,tempr
	;PORTD as input
	ldi tempr,0b00000000
	out DDRD,tempr
	;LEDs OFF
	ldi tempr,0b11111111
	out PORTB,tempr
	;The siren is powered off
	ldi tempr,0b11111110
	out PORTC,tempr
	
	
	;Setting up the A/D Converter
	ldi tempr,0b10000010
	out ADCSRA,tempr
	
	;flags Initialization
	ldi tempr,0b11111111
	mov flg,tempr
	mov LED_flag,tempr
	mov silo_1_full,tempr
	
	rjmp main
	
;The main program routine
main:
	;Waiting start button
	in tempr,PIND
	rcall delay20ms
	sbrc tempr,0
	rjmp main
	;A/D reading level silo 1
	ldi tempr,0b11100001  
	out ADMUX,tempr
	sbi ADCSRA,6
conv:
	;Waiting for conversion
	sbic ADCSRA,6
	rjmp conv
	;Checking silo 1 is empty. If yes check silo 2. Else, error
	cp ADCH,LIM_B1
	brlo silo_2
	cbi EROR_flag,0
	cbi EROR_flag,5
	rjmp error
silo_2:
	;A/D reading level silo 2
	ldi tempr,0b11100011
	out ADMUX,tempr
	sbi ADCSRA,6
conv_2:
	;Waiting for conversion
	sbic ADCSRA,6
	rjmp conv_2
	;Check silo 2 is empty. If yes check main silo. Else, error 
	cp ADCH,LIM_B3
	brlo main_silo
	cbi EROR_flag,0
	cbi EROR_flag,3
	rjmp error
main_silo:
	;A/D reading level main silo
	ldi tempr,0b11100000
	out ADMUX,tempr
	sbi ADCSRA,6
conv_3:
	;Waiting for conversion
	sbic ADCSRA,6
	rjmp conv_3
	;Checking main silo empty. If yes, error -> siren powered on
	;If no, turn valve over silo1
	cp ADCH,LIM_A1
	brsh valve_Y1 
	cbi EROR_flag,0
	cbi EROR_flag,1
	rjmp error
valve_Y1:
	;Turning on LED -> indicates there is sufficient material in main silo
	cbi LED_flag,1
	out PORTB,LED_flag
	;waiting to turn the valve over silo 1
	in tempr,PIND
	rcall delay20ms
	sbrc tempr,1
	rjmp valve_Y1 
	;LED7 on -> procedure starts -> motor M2 works
	cbi LED_flag,7
	cbi LED_flag,4
	out PORTB,LED_flag
	;Giving counter initial values
	ldi tempr,0b10010101
	out TCNT1H,tempr
	ldi tempr,0b00101111
	out TCNT1L,tempr
	;7 seconds in normal mode
	ldi tempr,0b00000000
	out TCCR1A,tempr
	ldi tempr,0b00000101
	out TCCR1B,tempr
	cbi flg,7
		
timer_7sec_loop:
	;Waiting timer to overflow
	in tempr,TIFR
	sbrc tempr,2
	sbi flg,7
	;Reading the switches for error
	in tempr,PIND
	rcall delay20ms
	
	
	sbic tempr,5
	rjmp next
	cbi EROR_flag,0
	cbi EROR_flag,4
	rjmp error
next:
	;If STOP is pressed, then jump to STOP
	sbis tempr,7
	rjmp STOP
	
	
	sbis flg,7
	rjmp timer_7sec_loop	
	;The conveyor belt has reached its nominal speed
	
	
	;Motor 1 and silo 1 start working
	cbi LED_flag,2
	cbi LED_flag,5
	cbi LED_flag,6
	out PORTB,LED_flag
	;Setting up the counter - normal mode
	ldi tempr,0
	out TCCR1A,tempr
	ldi tempr,1
	out TCCR1B,tempr
	;Setting up the timer overflow interrupt
	ldi tempr,0b00000100
	out TIMSK,tempr
	
polling_routine:
	;Setting up the counter to count 1 millisecond
	ldi tempr,0b01011111
	out TCNT1L,tempr
	ldi tempr,0b11110000
	out TCNT1H,tempr
	
	cbi flg,7
waiting_point:
	;Waiting for the timer to overflow
	sbis flg,7
	rjmp waiting_point
	;Checking 
	;1) error 
	;2) main silo is empty
	sbis flg,1
	rjmp main_silo_empty
	;Checking motor 1 overheated
	sbis flg,2
	rjmp motor_1_overheat
	;Checking motor 2 overheated
	sbis flg,3
	rjmp motor_2_overheat
	;Checking the STOP button
	sbis flg,4
	rjmp STOP
	;Checking silo 1 - max
	sbis flg,5
	rjmp valve_Y2
	;Checking silo 2 - max
	sbis flg,6
	rjmp STOP
	;If nothing has happened the polling is continued
	rjmp polling_routine
	
; maim silo empty - error
main_silo_empty:
	ldi EROR_flag,0b11111100
	rjmp error
	
; motor 1 overheated - error
motor_1_overheat:
	ldi EROR_flag,0b10111110
	rjmp error
	
; motor 2 overheated - error
motor_2_overheat:
	ldi EROR_flag,0b11101110
	rjmp error
	
;If silo 1 - max -> wait till the valve is turned to Y2 position
valve_Y2:
	in tempr,PIND
	rcall delay20ms
	sbrc tempr,2
	rjmp valve_Y2
	sbi flg,5
	rjmp polling_routine

; error routine	
error:
	;Stopping the timer
	ldi tempr,0
	out TCCR1A,tempr
	out TCCR1B,tempr
	
	
	ldi flg,255
	;Turning all LEDs off
	ldi LED_flag,255
	out PORTB,LED_flag
	;Turning on the error LEDs
	out PORTB,EROR_flag
	;Turning the siren on
	out PORTC,LED_flag
ack:
	;Waiting for the acknowledgement button
	in tempr,PIND
	rcall delay20ms
	sbrc tempr,6
	rjmp ack
	;Turning the siren off
	ldi tempr,0b11111110
	out PORTC,tempr
	;Starting timer (1 sec in normal mode)
	ldi tempr,0
	out TCCR1A,tempr
	ldi tempr,0b00000011
	out TCCR1B,tempr
led_blink:
	;Setting desired timer values
	ldi tempr,0b11011011
	out TCNT1L,tempr
	ldi tempr,0b00001011
	out TCNT1H,tempr
	
	
	cbi flg,7
stop_wait:
	;Checking STOP button
	in tempr,PIND
	rcall delay20ms
	sbrs tempr,7
	rjmp stop_counter
	;Checking timer has overflown
	sbrc flg,7
	rjmp led_blink
	rjmp stop_wait

;Stopping the counter
stop_counter:
	ldi tempr,0
	out TCCR1A,tempr
	out TCCR1B,tempr
	rjmp STOP
	
; timer 1 overflow routine
tm1_ovf:
	;Saving the status register
	in tempr,SREG
	push tempr
	;Disabling interrupts
	cli
	
	cpi TCCR1B,1
	brne error_blink
	;Checking main silo is empty
	ldi tempr,0b11100000
	out ADMUX,tempr
	sbi ADCSRA,6
conv_isr:
	;Waiting for conversion
	sbic ADCSRA,6
	rjmp conv_isr
	;Comparing the A/D value with the lower limit of the main silo
	cp ADCH,LIM_A1
	brsh m1_overheat
	cbi flg,1
	rjmp end_of_isr
m1_overheat:
	;Checking motor 1 overheated
	;If not, proceed, else set the aproppriate flag and exit the ISR
	in tempr,PIND
	rcall delay20ms
	sbic tempr,4
	rjmp m2_overheat
	cbi flg,2
	rjmp end_of_isr
m2_overheat:
	;Checking motor 2 overheated
	;If not,  proceed, else set the aproppriate flag and exit the ISR
	sbic tempr,5
	rjmp stop_pressed
	cbi flg,3
	rjmp end_of_isr
stop_pressed:
	;Checking stop button
	;If not,  proceed, else  set the appropriate flag and exit the ISR
	sbic tempr,7
	rjmp check_silo_1
	cbi flg,4
	rjmp end_of_isr
check_silo_1:
	;Checking silo 1 flag is cleared
	cpi silo_1_full,255
	brlo silo_2_full
silo_1_full:
	;Checking silo 1 is full
	;If not,  proceed, else set the appropriate flag and exit the ISR
	ldi tempr,0b11100010
	out ADMUX,tempr
	sbi ADCSRA,6
conv_2_isr:
	;Waiting for conversion
	sbic ADCSRA,6
	rjmp conv_2_isr
	;Comparing the A/D value with the upper limit of silo 1
	cp ADCH,LIM_B2
	brlo silo_2_full
	cbi flg,5
	ldi silo_1_full,0
	rjmp end_of_isr
silo_2_full:
	;Checking silo 2 full
	;If not, proceed, else  set the appropriate flag and exit the ISR
	ldi tempr,0b11100100
	out ADMUX,tempr
	sbi ADCSRA,6
conv_3_isr:
	;Waiting for conversion
	sbic ADCSRA,6
	rjmp conv_3_isr
	;Comparing the A/D value with the upper limit of silo 2
	cp ADCH,LIM_B4
	brlo end_of_isr
	cbi flg,6
	rjmp end_of_isr

; LEDs blinking every second
error_blink:
	com LED_flag
	or LED_flag,EROR_flag
	out PORTB,LED_flag
	
	
end_of_isr:
	sbi flg,7
	pop tempr
	out SREG,tempr
	reti
	
	
STOP:
	ldi tempr,0b11111111
	out PORTB,tempr
	rjmp RESET
	