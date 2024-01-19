; alarm_clk.asm
; January 22 2020
; Katelin Fung
; 
; Elec 291/292 
; Lab 2 Alarm Clock
; 
; Video Demonstration: https://youtu.be/rYy_loGSO78
; 
; Features:
; Time: Hour, Minute, Second, 12 Hour AM/PM 
; Alarm: Hour, Minute, Toggle OFF/ON, Rings until stop button is pressed
; Chime: Hourly, Minute, Second, or No Chimem Rings for 1 second
; Stopwatch: (Up to 99 Hours) with Start, Stop, and Pause
; Timer: (Up to 99 Hours) with Start, Stop and Pause, Rings until stop button is pressed
; Flashing Colon every second


$NOLIST
$MODEFM8LB1
$LIST

CLK           EQU 24000000 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 432*2    ; The tone we want out is A major.  Interrupt rate must be twice as fast.
TIMER0_RELOAD EQU ((65536-(CLK/(TIMER0_RATE))))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/(TIMER2_RATE))))

BOOT_BUTTON   equ P3.7
SOUND_OUT     equ P2.1
SET_BUTTON    equ P0.0
INCREMENT_BUTTON equ P3.2
STOP_BUTTON equ P3.0
SOUND_BUTTON equ P2.4
RESET_BUTTON equ P2.2


; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed
BCD_counter:  ds 1 ; The BCD counter incremented in the ISR and displayed in the main loop
half_second_counter: ds 1 ;The half-second counter incremented in the ISR and displayed in the main loop
second_counter:  ds 1 ; The seconds counter incremented in the ISR and displayed in the main loop
minute_counter:  ds 1 ; The minute counter incremented in the ISR and displayed in the main loop
hour_counter:  ds 1 ; The hour counter incremented in the ISR and displayed in the main loop
mode_counter: ds 1 ; Counter to keep track of current mode
alarm_hour_counter: ds 1 ; Counter for alarm hour
alarm_minute_counter: ds 1 ; Counter for alarm minute
sound_mode_counter: ds 1 ; Counter for sound mode
stopwatch_counter_second: ds 1 ; Counter for stopwatch
stopwatch_counter_minute: ds 1 ; Counter for stopwatch
stopwatch_counter_hour: ds 1 ; Counter for stopwatch

timer_hour_counter: ds 1 ; Counter for stopwatch
timer_minute_counter: ds 1 ; Counter for stopwatch
timer_second_counter: ds 1 ; Counter for stopwatch



; mode_counter
; Mode 0: Time
; Mode 1: Set Time Hour
; Mode 2: Set Time Minute
; Mode 3: Set Time Second
; Mode 4: Set Alarm  Hour
; Mode 5: Set Alarm Minute
; Mode 6: Set Alarm ON/OFF
; Mode 7: Stopwatch 
; Mode 8: Set Timer  Hour
; Mode 9: Set Timer Minute
; Mode 10: Set Timer ON/OFF
; Mode 11: Timer Start/Stop

; sound_mode_counter
; Mode 0: No Chime
; Mode 1: Hourly Chime
; Mode 2: Minute Chime
; Mode 3: Second Chime




; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
half_second_flag: dbit 1 ; Set to one in the ISR every time 500 ms has passed
odd_half_second_flag: dbit 1 ; Set to one in the ISR every time 500 ms has passed
second_flag: dbit 1 ; Set to one in the ISR every time 1000 ms has passed
minute_flag: dbit 1 ; Set to one in the ISR every time 1 minute has passed
hour_flag: dbit 1 ; Set to one in the ISR every time 1 hour has passed
pm_flag: dbit 1 ; Set to one in the ISR every time time switches to pm
alarm_pm_flag: dbit 1 ; Set to one in the ISR every time alarm time switches to pm
alarm_on_flag: dbit 1 ; Set to one in the ISR every time alarm time switches to pm
alarm_time_flag: dbit 1 ; Set to one when alarm time
update_display_flag: dbit 1 ; set to one when increment button is clicked 
stopwatch_pause_flag: dbit 1 ; set to one when stopwatch is paused 
timer_pause_flag: dbit 1 ; set to one when timer is paused 
timer_time_flag: dbit 1 ; Set to one when timer time


cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P2.0
LCD_RW equ P1.7
LCD_E  equ P1.6
LCD_D4 equ P1.1
LCD_D5 equ P1.0
LCD_D6 equ P0.7
LCD_D7 equ P0.6
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the location of the counter
Initial_Message1:  db 'CX  T HH:MM:SSAM', 0
Initial_Message2:  db '	 ALM HH:MMAM ON', 0
AM_Message: db 'AM', 0
PM_Message: db 'PM', 0
Alarm_AM_Message: db 'AM', 0
Alarm_PM_Message: db 'PM', 0
Time_Message: db 'T', 0
Alarm_Message: db 'ALARM ', 0
Stopwatch_Message: db 'STOP  ', 0
Set_Hour_Message: db 'SET H', 0
Set_Minute_Message: db 'SET M', 0
Set_Second_Message: db 'SET S', 0
Set_Alarm_Hour_Message: db 'SET AH', 0
Set_Alarm_Minute_Message: db 'SET AM', 0
Set_Alarm_On_Message: db 'ON ', 0
Set_Alarm_Off_Message: db 'OFF', 0
Set_Alarm_On_Off_Message: db 'ON/OFF', 0
Alarm_Time_Message: db 'It is Time      ', 0
Timer_Message: db 'TIMER ', 0
Timer_Message_Hour: db 'SET H ', 0
Timer_Message_Minute: db 'SET M ', 0
Timer_Message_Second: db 'SET S ', 0

;-----------------------------------;
; Routine to initialize the timer 0 ;
;-----------------------------------;
Timer0_Init:
	orl CKCON0, #00000100B ; Timer 0 uses the system clock
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret



;---------------------------------;
; ISR for timer 0.                ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	; Timer 0 can not autoreload so we need to reload it in the ISR:
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	;setb TR0	
	;clr SOUND_OUT ; Toggle the pin connected to the speaker

	reti


;---------------------------------;
; Routine to initialize timer 2   ;
;---------------------------------;
Timer2_Init:
	orl CKCON0, #0b00010000 ; Timer 2 uses the system clock
	mov TMR2CN0, #0 ; Stop timer/counter.  Autoreload mode.
	mov TMR2H, #high(TIMER2_RELOAD)
	mov TMR2L, #low(TIMER2_RELOAD)
	; Set the reload value
	mov TMR2RLH, #high(TIMER2_RELOAD)
	mov TMR2RLL, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret



;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2H  ; Timer 2 doesn't clear TF2H automatically. Do it in ISR
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1



Inc_Done:

;---------------------------------;
;   Set a flag every half second, and increment a counter
;---------------------------------;
Check_Half_Second: 
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(500), Jump_to_Finished_Updating_Time_1 ; Should be 500 Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(500), Jump_to_Finished_Updating_Time_1 
	
	; Set half second flag
	setb half_second_flag ; Let the main program know half second had passed
	
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; Increment the Half-Second counter
	mov a, half_second_counter
	add a, #0x01
	mov half_second_counter, a
	da a
	mov half_second_counter, a
	
	; Complement the even half second flag
	cpl odd_half_second_flag
	
	; Check second next
	sjmp Check_Second

	; Finished updated time 
Jump_to_Finished_Updating_Time_1:
	ljmp Finished_Updating_Time

;---------------------------------;
;   Increment seconder counter every other half second              
;---------------------------------;

Check_Second: 
	; Check if second has passed
	jb odd_half_second_flag, jump_to_Jump_to_Finished_Updating_Time_2

	; Set  second flag
	setb second_flag ; Let the main program know a second has passed
	
	; Increment the Second counter
	mov a, second_counter
	add a, #0x01
	mov second_counter, a
	da a
	mov second_counter, a
	
	sjmp Update_Stopwatch_Second
	jump_to_Jump_to_Finished_Updating_Time_2:
	ljmp Jump_to_Finished_Updating_Time_2

;---------------------------------;
;    Increment Stopwatch unless the stopwatch is paused             
;---------------------------------;
Update_Stopwatch_Second:
	jb stopwatch_pause_flag, Finished_Updating__Stopwatch
	; Increment the hour counter
	mov a, stopwatch_counter_second
	add a, #0x01
	mov stopwatch_counter_second, a
	da a
	mov stopwatch_counter_second, a
	
	Check_Stopwatch_Minute: 
	; Check if second has passed
	mov a, stopwatch_counter_second
	cjne a, #0x60, Finished_Updating__Stopwatch
	; Set  minute flag

	; Increment the Minute counter
	mov a, stopwatch_counter_minute
	add a, #0x01
	mov stopwatch_counter_minute, a
	da a
	mov stopwatch_counter_minute, a
	
	; Reset the Second Counter
	mov stopwatch_counter_second, #0x00
	
	; Check hour next
	sjmp Check__Stopwatch_Hour


Check__Stopwatch_Hour: 
	; Check if second has passed
	cjne a, #0x60, Finished_Updating__Stopwatch	
	
	; Increment the hour counter
	mov a, stopwatch_counter_hour
	add a, #0x01
	mov stopwatch_counter_hour, a
	da a
	mov stopwatch_counter_hour, a
	
	; Reset the minute Counter
	mov stopwatch_counter_minute, #0x00

Finished_Updating__Stopwatch:
	
;---------------------------------;
;   Increment the timer unless it is paused              
;---------------------------------;

Update_Timer_Second:
	jb timer_pause_flag, Finished_Updating_Timer
	; Increment the hour counter
	mov a, timer_second_counter
	add a, #0x99 ; equivalent to subtracting 1
	mov timer_second_counter, a
	da a
	mov timer_second_counter, a
	
	; Update Timer

; Check if Timer is turned off - if so set flag

; Check if Timer is Up - if so set flag
	mov a, timer_second_counter
	cjne a, #0x00, timer_not_up
	mov a, timer_second_counter
	cjne a, #0x00, timer_not_up
	
	mov a, timer_minute_counter
	cjne a, #0x00, timer_not_up
	mov a, timer_minute_counter
	cjne a, #0x00, timer_not_up
	
	mov a, timer_hour_counter
	cjne a, #0x00, timer_not_up
	mov a, timer_hour_counter
	cjne a, #0x00, timer_not_up
	
	; turn off timer
	setb alarm_time_flag ; Set the alarm flag
	setb timer_pause_flag
; Otherwise Decrement timer
timer_not_up:
Check_Timer_Second: 
	; Check if minute has passed
	mov a, timer_second_counter
	cjne a, #0x99, Finished_Updating_Timer

	; Decrement the Minute counter
	mov a, timer_minute_counter
	add a, #0x99
	mov timer_minute_counter, a
	da a
	mov timer_minute_counter, a
	
	; Reset the Second Counter
	mov timer_second_counter, #0x59
	
	; Check hour next
	sjmp Check__Timer_Minute


Check__Timer_Minute: 
	; Check if hour has passed
	cjne a, #0x99, Finished_Updating_Timer	
	
	; Increment the hour counter
	mov a, timer_hour_counter
	add a, #0x99
	mov timer_hour_counter, a
	da a
	mov timer_hour_counter, a
	
	; Reset the minute Counter
	mov timer_minute_counter, #0x59

Finished_Updating_Timer:
	
	
	; Check minute next
	sjmp Check_Minute

	; Finished updated time 
Jump_to_Finished_Updating_Time_2:
	ljmp Finished_Updating_Time

;---------------------------------;
;   Increment minute counter every 60 seconds            
;---------------------------------;

Check_Minute: 
	; Check if second has passed
	mov a, second_counter
	cjne a, #0x60, Jump_to_Finished_Updating_Time_3
	; Set  minute flag
	setb minute_flag ; Let the main program know a minute has passed
	
	; Increment the Minute counter
	mov a, minute_counter
	add a, #0x01
	mov minute_counter, a
	da a
	mov minute_counter, a
	
	; Reset the Second Counter
	mov second_counter, #0x00
	
	; Check hour next
	sjmp Check_Hour

	; Finished updated time 
Jump_to_Finished_Updating_Time_3:
	ljmp Finished_Updating_Time


;---------------------------------;
;    Increment hour counter every 60 minutes             
;---------------------------------;
Check_Hour: 
	; Check if second has passed
	cjne a, #0x60, Jump_to_Finished_Updating_Time_4	
	; Set  hour flag
	setb hour_flag ; Let the main program know an hour has passed
	
	; Increment the hour counter
	mov a, hour_counter
	add a, #0x01
	mov hour_counter, a
	da a
	mov hour_counter, a
	
	; Reset the minute Counter
	mov minute_counter, #0x00
	
	; Check Check 12 O'Clock next
	sjmp Check_12_OClock

	; Finished updated time 
Jump_to_Finished_Updating_Time_4:
	ljmp Finished_Updating_Time


;---------------------------------;
;   Switch Time from 12 to 1               
;---------------------------------;
Check_12_OClock:
	; Check if time to switch from 12 to 1 flag
	cjne a, #0x13, Check_AM_PM
	;Reset the hour Counter
	mov hour_counter, #0x01
;---------------------------------;
;   Switch time from AM/PM              
;---------------------------------;	
Check_AM_PM:
	; Check if time to switch PM flag
	cjne a, #0x12, Finished_Updating_Time
	
	; Set  PM flag
	cpl pm_flag ;
	;setb am_pm_flag
	
Finished_Updating_Time:



;---------------------------------;
;   Change between modes              
;---------------------------------;

Check_Set_Button:
	; Check if set_time_button is pressed
	jb SET_BUTTON, Check_Increment_Button ; if the 'SET_BUTTON' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb SET_BUTTON, Check_Increment_Button ; if the 'SET_BUTTON' button is not pressed skip
	jnb SET_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	; Increment the mode counter
	mov a, mode_counter
	add a, #0x01
	mov mode_counter, a
	da a
	mov mode_counter, a	

	; If past number of modes, loop back to mode 0
	cjne a, #0x12, Check_Increment_Button
	mov mode_counter, #0x00

;---------------------------------;
;   Check if increment button is pressed              
;---------------------------------;

Check_Increment_Button:
	; Check if INCREMENT_BUTTON is pressed
	jb INCREMENT_BUTTON, jumpto_Finished_Setting_Time1 ; if the 'INCREMENT_BUTTON' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INCREMENT_BUTTON, jumpto_Finished_Setting_Time1 ; if the 'INCREMENT_BUTTON' button is not pressed skip
	jnb INCREMENT_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	setb update_display_flag ; set flag to update the display
	mov a, mode_counter

sjmp Check_Increment_Time_Hour
jumpto_Finished_Setting_Time1:
ljmp Finished_Setting_Time

; Check Mode and Increment Time/Alarm

;---------------------------------;
;   Increment the clock hour              
;---------------------------------;
	
Check_Increment_Time_Hour:
	mov a, mode_counter
	cjne a, #0x01, Check_Increment_Time_Minute
	; Increment the hour_counter
	mov a, minute_counter
	; Set  hour flag
	setb hour_flag ; Let the main program know an hour has passed
	
	; Increment the hour counter
	mov a, hour_counter
	add a, #0x01
	mov hour_counter, a
	da a
	mov hour_counter, a
	
	; Check Check 12 O'Clock next
	ljmp Check_12_OClock
;---------------------------------;
;   Increment the clock minute              
;---------------------------------;
	
Check_Increment_Time_Minute:
	mov a, mode_counter	
	cjne a, #0x02, Check_Increment_Time_Second
	; Increment the minute_counter
	
	; Set  minute flag
	setb minute_flag ; Let the main program know a minute has passed
	
	; Increment the Minute counter
	mov a, minute_counter
	add a, #0x01
	mov minute_counter, a
	da a
	mov minute_counter, a
	
	; Check if reached 60 minutes
	cjne a, #0x60, jmp_to_Finished_Setting_Time
	; Reset the minute Counter
	mov minute_counter, #0x00

jmp_to_Finished_Setting_Time:
ljmp Finished_Setting_Time

;---------------------------------;
;   Set the clock seconds to 0              
;---------------------------------;

Check_Increment_Time_Second:
	mov a, mode_counter
	cjne a, #0x03, Check_Increment_Alarm_Hour
	mov second_counter, #0x00

;---------------------------------;
;   Increment the alarm hour              
;---------------------------------;
Check_Increment_Alarm_Hour:
	mov a, mode_counter
	cjne a, #0x04, Check_Increment_Alarm_Minute
	
	; Increment the hour counter
	mov a, alarm_hour_counter
	add a, #0x01
	mov alarm_hour_counter, a
	da a
	mov alarm_hour_counter, a
	
	; Check if alarm time to switch from 12 to 1 flag
	cjne a, #0x13, Check_Alarm_AM_PM
	;Reset the hour Counter
	mov alarm_hour_counter, #0x01
	
Check_Alarm_AM_PM:
	; Check if time to switch PM flag
	cjne a, #0x12, Check_Increment_Alarm_Minute
	
	; Set  PM flag
	cpl alarm_pm_flag ;
	;setb am_pm_flag
;---------------------------------;
;   Increment the alarm minute               
;---------------------------------;
Check_Increment_Alarm_Minute:
	mov a, mode_counter
	cjne a, #0x05, Check_Alarm_On_Off

	; Increment the Minute counter
	mov a, alarm_minute_counter
	add a, #0x01
	mov alarm_minute_counter, a
	da a
	mov alarm_minute_counter, a
	
	; Check if reached 60 minutes
	cjne a, #0x60, Check_Alarm_On_Off
	; Reset the minute Counter
	mov alarm_minute_counter, #0x00

;---------------------------------;
;   Turn the alarm on and off             
;---------------------------------;

Check_Alarm_On_Off:
	mov a, mode_counter
	cjne a, #0x06, Check_Stopwatch_Mode
	cpl alarm_on_flag
	
;---------------------------------;
;   Turn the stopwatch on and off             
;---------------------------------;	
Check_Stopwatch_Mode:
	mov a, mode_counter
	cjne a, #0x07, Check_Increment_Timer_Hour
	cpl stopwatch_pause_flag ; toggle stopwatch on and off


;---------------------------------------------
; Set Timer: Increase Hour/Minute/Second
; when set button pressed
;---------------------------------------------

;---------------------------------;
;   Decrement the timer hour             
;---------------------------------;
Check_Increment_Timer_Hour:
	mov a, mode_counter
	cjne a, #0x08, Check_Increment_Timer_Minute
	
	; Increment the hour counter
	mov a, timer_hour_counter
	add a, #0x01
	mov timer_hour_counter, a
	da a
	mov timer_hour_counter, a
;---------------------------------;
;   Decrement the timer minute             
;---------------------------------;

Check_Increment_Timer_Minute:
	mov a, mode_counter
	cjne a, #0x09, Check_Increment_Timer_Second

	; Increment the Minute counter
	mov a, timer_minute_counter
	add a, #0x01
	mov timer_minute_counter, a
	da a
	mov timer_minute_counter, a
	
	; Check if reached 60 minutes
	cjne a, #0x60, Finished_Setting_Time
	; Reset the minute Counter
	mov timer_minute_counter, #0x00
;---------------------------------;
;   Decrement the timer second             
;---------------------------------;
Check_Increment_Timer_Second:
	mov a, mode_counter
	cjne a, #0x10, Check_Timer

	; Increment the second counter
	mov a, timer_second_counter
	add a, #0x01
	mov timer_second_counter, a
	da a
	mov timer_second_counter, a
	
	; Check if reached 60 minutes
	cjne a, #0x60, Finished_Setting_Time
	; Reset the minute Counter
	mov timer_second_counter, #0x00

;---------------------------------;
;   Display Timer and toggle start/stop             
;---------------------------------;
Check_Timer:
	mov a, mode_counter
	cjne a, #0x11, Finished_Setting_Time
	cpl timer_pause_flag ; toggle stopwatch on and off



Finished_Setting_Time:	


;---------------------------------;
;   Check if the reset button is clicked
;---------------------------------;
Check_reset_Button:


	; Check if RESET_BUTTON is pressed, if so reset stop watch value
	jb RESET_BUTTON, Check_Alarm ; if the 'INCREMENT_BUTTON' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb RESET_BUTTON, Check_Alarm ; if the 'INCREMENT_BUTTON' button is not pressed skip
	jnb RESET_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
;---------------------------------;
;   Reset the stopwatch if in stopwatch mode
;---------------------------------;
reset_stopwatch:
	mov a, mode_counter
	cjne a, #0x07, check_reset_timer
	mov stopwatch_counter_hour, #0x00
	mov stopwatch_counter_minute, #0x00
	mov stopwatch_counter_second, #0x00
	
;---------------------------------;
;   Reset the timer if in a timer mode
;---------------------------------;
	
check_reset_timer:
	mov a, mode_counter
	cjne a, #0x08, reset_timer
	cjne a, #0x09, reset_timer
	cjne a, #0x10, reset_timer
	cjne a, #0x11, reset_timer
	ljmp Check_Alarm
reset_timer:
	mov timer_hour_counter, #0x00
	mov timer_minute_counter, #0x00
	mov timer_second_counter, #0x00
	setb timer_pause_flag
	
;---------------------------------;
;   Check if the alarm should be triggered
;---------------------------------;

Check_Alarm:
	; Check if alarm is on, if not skip
	jnb alarm_on_flag, Finished_Checking_Alarm

	; Check if current time matches alarm time
	
	; Check Hour
	mov a, hour_counter
	mov r1, a
	mov a, alarm_hour_counter
	subb a, r1
	cjne a, #0x00, Finished_Checking_Alarm
	
	; Check Minute
	mov a, minute_counter
	mov r1, a
	mov a, alarm_minute_counter
	subb a, r1
	cjne a, #0x00, Finished_Checking_Alarm
	
	; Check Second
	mov a, second_counter
	cjne a, #0x00, Finished_Checking_Alarm
	
	; Check AM/PM
	
	; Check if both pm
	jnb alarm_pm_flag, Check_Alarm_AM
	jnb pm_flag, Finished_Checking_Alarm
	
	sjmp Sound_Alarm
	
	; Check if both am
Check_Alarm_AM:
	jb pm_flag, Finished_Checking_Alarm

Sound_Alarm:	
	setb alarm_time_flag ; Set the alarm flag

Finished_Checking_Alarm:
;---------------------------------;
;   Reset the Alarm
;---------------------------------;
Reset_Alarm:
	; Check if alarm_time_flag flag is set
	jnb alarm_time_flag, No_Reset_Alarm
	; Check if STOP_BUTTON is pressed
	jb STOP_BUTTON, No_Reset_Alarm ; if the 'STOP_BUTTON' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb STOP_BUTTON, No_Reset_Alarm ; if the 'STOP_BUTTON' button is not pressed skip
	jnb STOP_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	; Clear the alarm_time_flag
	clr alarm_time_flag
	
	setb update_display_flag ; to update flag
	
No_Reset_Alarm:


Check_Sound_Mode_Button:

;---------------------------------;
;   Control the chime mode (Off, Hourly, Minute, Second)
;---------------------------------;

	; Check if SOUND_BUTTON is pressed
	jb SOUND_BUTTON, Check_Sound_Mode ; if the 'SOUND_BUTTON' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb SOUND_BUTTON, Check_Sound_Mode ; if the 'SOUND_BUTTON' button is not pressed skip
	jnb SOUND_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	
	; Increment the sound_mode_counter
	mov a, sound_mode_counter
	add a, #0x01
	mov sound_mode_counter, a
	da a
	mov sound_mode_counter, a	

	; If past number of modes, loop back to mode 0
	cjne a, #0x04, Check_Sound_Mode
	mov sound_mode_counter, #0x00
	
;---------------------------------;
;   Turn on the speaker when the alarm or timer is triggered
;---------------------------------;
Check_Sound_Mode:
	; Alarm Sound
	jnb alarm_time_flag, Sound_Mode_1

	setb TR0
	cpl SOUND_OUT ; Turn on sound pin
	
	sjmp Finished_Sound_Mode

;---------------------------------;
;   No Chime
;---------------------------------;
Sound_Mode_1:
	mov a, sound_mode_counter
	cjne a, #0x00, Sound_Mode_2
	sjmp Finished_Sound_Mode
	
;---------------------------------;
;   Hourly Chime: Turn on sound for 1 second on the full hour
;---------------------------------;
Sound_Mode_2:
	mov a, sound_mode_counter
	cjne a, #0x01, Sound_Mode_3

	mov a, minute_counter
	; If the minutes are 0 then it is a whole hour
	cjne a, #0x00, Sound_Mode_3
	
	mov a, second_counter
	; If the seconds are 0 then it is a whole minute
	cjne a, #0x00, Sound_Mode_3
	
	setb TR0
	cpl SOUND_OUT ; Turn on sound pin
	
	sjmp Finished_Sound_Mode
	
;---------------------------------;
;   Minute Chime: Turn on sound for 1 second on the full minute
;---------------------------------;
Sound_Mode_3:
	mov a, sound_mode_counter
	cjne a, #0x02, Sound_Mode_4

	mov a, second_counter
	; If the seconds are 0 then it is a whole minute
	cjne a, #0x00, Sound_Mode_4
	
	setb TR0
	cpl SOUND_OUT ; Turn on sound pin
	
	sjmp Finished_Sound_Mode
	
;---------------------------------;
;   Second Chime: Turn on sound for 1/2 seconds every second
;---------------------------------;
Sound_Mode_4:
	mov a, sound_mode_counter
	cjne a, #0x03, Sound_Mode_Turn_off
	
	jb odd_half_second_flag, Sound_Mode_Turn_off
	
	setb TR0
	cpl SOUND_OUT ; Turn on sound pin
	
	sjmp Finished_Sound_Mode

;---------------------------------;
;   Otherwise, turn off sound
;---------------------------------;
Sound_Mode_Turn_off:	
; Otherwise, turn off sound
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	setb SOUND_OUT

Finished_Sound_Mode:
	


Timer2_ISR_done:
	pop psw
	pop acc
	reti


;---------------------------------;
; Hardware initialization         ;
;---------------------------------;
Initialize_All:
    ; DISABLE WDT: provide Watchdog disable keys
	mov	WDTCN,#0xDE ; First key
	mov	WDTCN,#0xAD ; Second key

	; Setup the stack start to the begining of memory only accesible with pointers
    mov SP, #7FH
    
    ; Enable crossbar and weak pull-ups
	mov	XBR0,#0x00
	mov	XBR1,#0x00
	mov	XBR2,#0x40

	mov	P2MDOUT,#0x02 ; make sound output pin (P2.1) push-pull
	
	; Switch clock to 24 MHz
	mov	CLKSEL, #0x00 ; 
	mov	CLKSEL, #0x00 ; Second write to CLKSEL is required according to the user manual (page 77)
	
	; Wait for 24 MHz clock to stabilze by checking bit DIVRDY in CLKSEL
waitclockstable:
	mov a, CLKSEL
	jnb acc.7, waitclockstable 

	; Initialize the two timers used in this program
    lcall Timer0_Init
    lcall Timer2_Init

    lcall LCD_4BIT ; Initialize LCD
    
    setb EA   ; Enable Global interrupts

	ret

;---------------------------------;
; Main program.                   ;
;---------------------------------;
main:
	lcall Initialize_All
	
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
	Set_Cursor(1, 1)
    ;Send_Constant_String(#Initial_Message1)
    Set_Cursor(2, 1)
    ;Send_Constant_String(#Initial_Message2)
    
    ; Set flags
    setb half_second_flag
    setb second_flag
    setb minute_flag
    setb hour_flag
    setb pm_flag
    setb alarm_pm_flag
    setb alarm_on_flag
    setb alarm_time_flag
    cpl alarm_time_flag
    setb stopwatch_pause_flag                                                                                                               
    setb timer_pause_flag

    cpl TR0 ; to have the beep at the first half of every second
    
    ; Clear Counters
	mov BCD_counter, #0x00
	mov half_second_counter, #0x00
	mov second_counter, #0x58
	mov minute_counter, #0x58
	mov hour_counter, #0x11
	mov mode_counter, #0x00
	mov alarm_hour_counter, #0x11
	mov alarm_minute_counter, #0x59
	mov sound_mode_counter, #0x00
	mov stopwatch_counter_second, #0x00
	mov stopwatch_counter_minute, #0x00
	mov stopwatch_counter_hour, #0x00
	mov timer_hour_counter, #0x00
	mov timer_minute_counter, #0x00
	mov timer_second_counter, #0x00
	
	; After initialization the program stays in this 'forever' loop
loop:
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	
	jnb BOOT_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	; A valid press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop timer 2 and reset the milli-seconds counter, to resync everything.
	clr TR2                 ; Stop timer 2
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; Reset Initial Message and Clear Flags and Counters
	ljmp main
	
	
	
	

	setb TR2                ; Start timer 2
	sjmp set_display             ; Display the new value
loop_a:
	;jnb half_second_flag, loop
	jb update_display_flag, set_display
	jb half_second_flag, set_display
	
	sjmp loop

set_display:
			
    Set_Cursor(1, 7)     ; the place in the LCD where we want the hour counter value
	Display_BCD(hour_counter) ; This macro is also in 'LCD_4bit.inc'
	
	Set_Cursor(1, 10)     ; the place in the LCD where we want the minute counter value
	Display_BCD(minute_counter) ; This macro is also in 'LCD_4bit.inc'
	
	Set_Cursor(1, 13)     ; the place in the LCD where we want the second counter value
	Display_BCD(second_counter) ; This macro is also in 'LCD_4bit.inc'

	Set_Cursor(2, 7)     ; the place in the LCD where we want the hour alarm counter value
	Display_BCD(alarm_hour_counter) ; This macro is also in 'LCD_4bit.inc'

	Set_Cursor(2, 10)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(alarm_minute_counter) ; This macro is also in 'LCD_4bit.inc'

	
		
	Send_Constant_String(#AM_Message)

	
	Set_Cursor(2, 16)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(stopwatch_pause_flag) ; This macro is also in 'LCD_4bit.inc'

	
	; Update Alarm AM/PM on the display
	
alarm_display_pm:
	Set_Cursor(2,12)
	jnb alarm_pm_flag, alarm_display_am
	Send_Constant_String(#Alarm_PM_Message)
	sjmp display_pm
		
alarm_display_am:
	Send_Constant_String(#Alarm_AM_Message)
	
	
	; Update AM/PM on the display
	
display_pm:
	Set_Cursor(1,15)
	jnb pm_flag, display_am
	Send_Constant_String(#PM_Message)
	sjmp display_alarm_on
		
display_am:
	Send_Constant_String(#AM_Message)

	
; Update alarm On/Off on the display
	
display_alarm_on:
	Set_Cursor(2,14)
	jnb alarm_on_flag, display_alarm_off
	Send_Constant_String(#Set_Alarm_On_Message)
	sjmp display_mode

display_alarm_off:
	Send_Constant_String(#Set_Alarm_Off_Message)


display_mode:	
mov a, mode_counter
	; Set Time/Alarm Message
	cjne a, #0x00, set_mode1_message
	Set_Cursor(1, 4)
	Display_char(#' ')
	Set_Cursor(1,5)
	Send_Constant_String(#Time_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Alarm_Message)
	Set_Cursor(1, 1)
	Display_char(#'C')
	Set_Cursor(1, 2)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(sound_mode_counter) ; This macro is also in 'LCD_4bit.inc'
	ljmp display_alarm

set_mode1_message:
	cjne a, #0x01, set_mode2_message
	Set_Cursor(1,1)
	Send_Constant_String(#Set_Hour_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Alarm_Message)
	ljmp display_alarm

set_mode2_message:
	cjne a, #0x02, set_mode3_message
	Set_Cursor(1,1)
	Send_Constant_String(#Set_Minute_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Alarm_Message)
	ljmp display_alarm

set_mode3_message:
	cjne a, #0x03, set_mode4_message
	Set_Cursor(1,1)
	Send_Constant_String(#Set_Second_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Alarm_Message)
	ljmp display_alarm

	
; Set alarm Message
set_mode4_message:
	cjne a, #0x04, set_mode5_message
	Set_Cursor(1,5)
	Send_Constant_String(#Time_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Set_Alarm_Hour_Message)
	Set_Cursor(1, 1)
	Display_char(#'C')
	Set_Cursor(1, 2)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(sound_mode_counter) ; This macro is also in 'LCD_4bit.inc'
	ljmp display_alarm	

set_mode5_message:
	cjne a, #0x05, set_mode6_message
	Set_Cursor(1,5)
	Send_Constant_String(#Time_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Set_Alarm_Minute_Message)
	Set_Cursor(1, 1)
	Display_char(#'C')
	Set_Cursor(1, 2)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(sound_mode_counter) ; This macro is also in 'LCD_4bit.inc'
	ljmp display_alarm	
	
set_mode6_message:
	cjne a, #0x06, set_mode7_message
	Set_Cursor(1,5)
	Send_Constant_String(#Time_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Set_Alarm_On_Off_Message)
	Set_Cursor(1, 1)
	Display_char(#'C')
	Set_Cursor(1, 2)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(sound_mode_counter) ; This macro is also in 'LCD_4bit.inc'
	ljmp display_alarm	
	
set_mode7_message:
	cjne a, #0x07, jmpto8
	sjmp display7
	
	jmpto8:
	ljmp set_mode8_message

	display7:

	Set_Cursor(1,5)
	Set_Cursor(1, 1)
	Display_char(#'C')
	Set_Cursor(1, 2)     ; the place in the LCD where we want the minute alarm counter value
	Display_BCD(sound_mode_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(1,5)
	Send_Constant_String(#Time_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Stopwatch_Message)
	Set_Cursor(1, 1)
	Display_char(#'C')
	Set_Cursor(2, 7)     ; the place in the LCD where we want the hour counter value
	Display_BCD(stopwatch_counter_hour) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 10)     ; the place in the LCD where we want the hour counter value
	Display_BCD(stopwatch_counter_minute) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 12)
	Display_char(#':')
	Set_Cursor(2, 13)     ; the place in the LCD where we want the hour counter value
	Display_BCD(stopwatch_counter_second) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 15)
	Display_char(#' ')
	;Set_Cursor(2, 16)
	;Display_char(#' ')
	
	;Display stopwatch pause or on
	Set_Cursor(2,16)
	jnb stopwatch_pause_flag, j1
	Display_char(#'P') ; Paused
	sjmp j2
	
	j1:
	Display_char(#'O') ; On
	
	j2:

set_mode8_message:

	cjne a, #0x08, jmpto9
	sjmp display8
	
	jmpto9:
	ljmp set_mode9_message

	display8:
	
	Set_Cursor(1, 1)
	Send_Constant_String(#Timer_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Timer_Message_Hour)
	Set_Cursor(2, 7)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_hour_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 10)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_minute_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 12)
	Display_char(#':')
	Set_Cursor(2, 13)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_second_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 15)
	Display_char(#' ')

set_mode9_message:

	
	cjne a, #0x09, jmpto10
	sjmp display9
	
	jmpto10:
	ljmp set_mode10_message

	display9:
	
	
	Set_Cursor(1, 1)
	Send_Constant_String(#Timer_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Timer_Message_Minute)
	Set_Cursor(2, 7)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_hour_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 10)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_minute_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 12)
	Display_char(#':')
	Set_Cursor(2, 13)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_second_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 15)
	Display_char(#' ')

set_mode10_message:


	cjne a, #0x10, jmpto11
	sjmp display10
	
	jmpto11:
	ljmp set_mode11_message

display10:

	Set_Cursor(1, 1)
	Send_Constant_String(#Timer_Message)
	Set_Cursor(2,1)
	Send_Constant_String(#Timer_Message_Second)
	Set_Cursor(2, 7)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_hour_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 10)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_minute_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 12)
	Display_char(#':')
	Set_Cursor(2, 13)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_second_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 15)
	Display_char(#' ')
	Set_Cursor(2, 16)
	Display_char(#' ')


set_mode11_message:

	cjne a, #0x11, jmpto12
	sjmp display11
	
	jmpto12:
	ljmp set_mode12_message

display11:

	Set_Cursor(1, 1)
	Send_Constant_String(#Time_Message)
	Set_Cursor(1, 5)
	Display_char(#' ')
	Set_Cursor(2,1)
	Send_Constant_String(#Timer_Message)
	Set_Cursor(2, 7)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_hour_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 10)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_minute_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 12)
	Display_char(#':')
	Set_Cursor(2, 13)     ; the place in the LCD where we want the hour counter value
	Display_BCD(timer_second_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2, 15)
	Display_char(#' ')

set_mode12_message:

display_alarm:
	; If it is time for the alarm to sound and it has not been turned off, display a message
	jnb alarm_time_flag, set_alarm_colon
	Set_Cursor(2,1)
	Send_Constant_String(#Alarm_Time_Message)
	sjmp flash_colons_on
	
set_alarm_colon:
	jb  alarm_time_flag, flash_colons_on
	Set_Cursor(2, 9)
	Display_char(#':')	

	
	
flash_colons_on:
	jb odd_half_second_flag, flash_colons_off
	Set_Cursor(1, 9)
	Display_char(#':')
	Set_Cursor(1, 12)
	Display_char(#':')
	;Set_Cursor(2, 12)
	;Display_char(#':')
	sjmp Finished_flashing_colons
flash_colons_off:
	Set_Cursor(1, 9)
	Display_char(#' ')
	Set_Cursor(1, 12)
	Display_char(#' ')
	;Set_Cursor(2, 9)
	;Display_char(#' ')
	;Set_Cursor(2, 12)
	;Display_char(#' ')
	
	; If the alarm is not sounding, display alarm colons
Finished_flashing_colons:
		
	
clear_flags:
	; clear flags
	clr half_second_flag
	clr second_flag
    clr minute_flag
    clr hour_flag
    clr update_display_flag

    
	
	
    ljmp loop
END
