;	Bios Blackjack
;  Compile with nasm to make a flat binary
;  $nasm bios_blackjack.asm -f bin -o blackjack.bin
;
;	Run with emulator 
;  $qemu-system-i386 -fda blackjack.bin
;
;
;	This first stage of this program sets up a stack, initializes
;	the segment registers with the proper values
;	It then loads the second stage (main_program) into memory and
; 	jumps to it.

;---------------------------------------------------------------------
;FIRST STAGE

BITS 16
org 0x7c00			;calculates offsets from 0x7c00

	mov ax, 0x07c0		; Set up 4K stack space after this bootloader
	add ax, 288		; (4096 + 512) / 16 bytes per paragraph
	mov ss, ax
	mov sp, 0x1000		;stack starts at 0x9e00 and grows down

	mov ax,0 		; Set data segment to where we're loaded
	mov ds, ax

	mov es, ax		;zero out es. int 0x13 loads to es:bx

	mov [BOOT_DRIVE], dl

	;Load main program into memory.
	mov ah, 0x02
	   
	;Number of sectors to read.
	mov al, 4

	;Boot drive number
	mov dl, [BOOT_DRIVE]

        ;Cylinder number.
	mov ch, 0

	; Head number.
	mov dh, 0
	   
	; Starting sector number. 2 because 1 was already loaded.
	mov cl, 2
	
	; Where to load to.
	mov bx, main_program
	int 0x13
		
	jmp main_program

	BOOT_DRIVE: db 0

	;padding bytes.    
	times ((0x200 - 2) - ($ - $$)) db 0x00
	dw 0xAA55

;----------------------------------------------------------------------
;SECOND STAGE

main_program:

	mov ah,0	;why do I need an extra instruction??

	;set RAND_OFFSET to number of seconds
	;A simple way of seeding random number list
	mov ah,2
	int 0x1a
	
	mov [RANDOM_OFFSET], dh

	;initialize the arrays with the card info
	call set_card_displays
	call set_card_values
	call set_card_suits
	call set_cards

	mov si, WELCOME
	call print_string

	call delay

	call print_newline
	call print_newline

	mov si, INVITE
	call print_string

	call get_y_n
	
	cmp al, 0
	je end_game

	call get_card
	
	call print_newline

	;add two cards to player's hand
	mov bx, PLAYER_HAND
	call add_card

	mov bx, PLAYER_HAND
	call add_card	

	;add one card to dealer's hand
	mov bx, DEALER_HAND
	call add_card

	call print_state1

	;gives player option of selecting more cards
	loop14:

		mov si, HIT_OR_STAY
		call print_string

		call get_y_n

		cmp al,0
		je dealer_draw

		call print_newline
		call print_newline

		mov bx, PLAYER_HAND
		call add_card

		call print_state1

		mov bx, PLAYER_HAND
		call calc_sum

		cmp al, 21
		jg busted

	jmp loop14

	;dealer picks cards if necessary
	dealer_draw:

		mov bx, DEALER_HAND
		call add_card

		call print_newline
		call print_newline

		call print_state2

		call delay

		mov bx, DEALER_HAND
		call calc_sum

		cmp al, 17
		jl dealer_draw

	cmp al, 21
	jg dealer_busted

	;both hands are not bust
	mov ah, 0
	push ax			;preserve sum of dealer's hand
	mov bx, PLAYER_HAND
	call calc_sum		;al now holds sum of player's hand

	pop cx			;cl now holds dealer's hand

	cmp al, cl
	jge case2

	;case 1: dealer has winning hand

		mov si, YOU_LOSE
		call print_string
		jmp end_game
	
	case2:		;either tie or player has better hand
	
	cmp al, cl
	je case3

		mov si, YOU_WIN
		call print_string
		jmp end_game

	case3:
		mov si, PUSH
		call print_string
		jmp end_game
	


	
	dealer_busted:
		mov si, DEALER_BUSTED
		call print_string
		jmp end_game
	
	busted:
		mov si, BUSTED
		call print_string



	end_game:
		mov si, CLOSING_MESSAGE
		call print_string


	cli
	jmp $


	;print out whole card array
	mov cx, 0
	loop9:

		mov bx, CARDS
		add bx, cx
		mov ax, 0
		mov al, [bx]

		;call print_card
		
		inc cx
		cmp cx, 52
	jl loop9
;-------------------------------------------------------------------
;some helper functions

;delay
;cx:dx holds number of miliseconds to delay
;seems like emulator creates delay longer than requested

	delay:
		mov ah, 0x86
		mov cx, 0x10
		mov dx, 0
		int 0x15
	ret


;print the state of the hand before dealer starts selecting cards
;Example    You Have:  AS 5H 5D
;	  Dealer Has:  4D XX

	print_state1:

		mov si, HAND_STATUS
		call print_string

		call print_players_hand

		call print_newline
	
		mov si, DEALER_STATUS
		call print_string

		call print_dealer_hand_initial
		call print_newline
	ret

;print the state of the hand before dealer starts selecting cards
;Example    You Have:  AS 5H 5D
;	  Dealer Has:  4D KS 3D

	print_state2:

		mov si, HAND_STATUS
		call print_string

		call print_players_hand

		call print_newline
	
		mov si, DEALER_STATUS
		call print_string

		call print_dealer_hand
		call print_newline
	ret


;print newline and return carriage

	print_newline:
	
		mov ah, 0x0e
		mov al, 0x0a
		int 0x10

		mov al, 0x0d
		int 0x10
	ret		

;print char
;pass char in al
;will modify ah as well
	print_char:

		mov ah, 0x0E
		int 0x10
	ret

;address of string in si
;must be null terminated
;modifies ax

	print_string:			
		mov ah, 0x0e		

		.repeat:
			lodsb		; Get character from string
			cmp al, 0
			je .done	; If char is zero, end of string
			int 0x10	; Otherwise, print it
			jmp .repeat

		.done:
	ret



;print a card. The card number is passed in al
;Note that ah will be destroyed by this function
;bx will be modified as well

	print_card:
		mov ah, 0

		;first print the display value

		mov bx, CARD_DISPLAY
		add bx, ax
		push ax
		mov al, [bx]
		call print_char
		pop ax

		;next print the card suit

		mov bx, CARD_SUITS
		add bx, ax
		push ax
		mov al, [bx]
		call print_char
		pop ax

	ret

;print player's hand
;modifies bx and ax

	print_players_hand:

		mov bx, PLAYER_HAND

		loop6:
			mov al, [bx]

			cmp al, 0xff
			je loop6_end
			push bx

			call print_card
		
			pop bx
			mov al, ' '
			call print_char
		
			add bx, 1

		jmp loop6

		loop6_end:
	ret

;print the dealer's initial hand. Second card is hidden.
;Example: 5D XX

	print_dealer_hand_initial:

		mov bx, DEALER_HAND
		call print_card

		mov al, ' '

		call print_char

		mov al, 'X'
		call print_char
		call print_char
	ret

;print the dealer's hand including second card.
;Example: 5D JS 2H

	print_dealer_hand:

		mov bx, DEALER_HAND

		loop2:
			mov al, [bx]

			cmp al, 0xff
			je loop2_end
			push bx

			call print_card
		
			pop bx
			mov al, ' '
			call print_char
		
			add bx, 1

		jmp loop2

		loop2_end:
	ret

;add a card to a hand
;the address of the hand should be passed in bx

	add_card:
		loop15:
			mov al, [bx]
			cmp al, 0xff
		je found_empty_spot

			inc bx
		jmp loop15

		found_empty_spot:

			push bx
			call get_card
			pop bx
			mov [bx], al
	ret



;calculates the sum of hand
;pass address of head of hand in bx
;returns the sum in al

	calc_sum:

		mov dl, 0		;dl holds sum
		mov ax, 0

		loop12:

			mov al, [bx]

			cmp al,0xff
			je loop12_end

			push bx

			mov bx, CARD_VALUES
			add bx, ax
			mov cl, [bx]		;the value of CARD[al]
			
			
			pop bx
			add dl, cl

			add bx,1
		jmp loop12

		loop12_end:
	mov al, dl
	ret
	

;gets y/n input from user
;returns al = 1 if y
;returns ah = 0 if n

	get_y_n:
		loop11:
	
			mov ah, 0
			int 0x16

			cmp al, 'y'
			je return_yes

			cmp al, 'n'
			je return_no

		jmp loop11
		
		return_yes:

			call print_char

			mov al, 1
			ret
		return_no:

			call print_char			

			mov al, 0
			ret
	ret

;get the next random number for selecting a card
;modifies ax, bx, cx, dx

	get_next_rand:
		mov bx, LAST_CARD
		mov dl, [bx]

		loop10:

			mov bx, RANDOM_OFFSET
			mov cx, 0
			mov cl, [bx]

			;increment RANDOM_OFFSET
			push cx
			inc cx
			mov [bx], cl
			pop cx

			;need some comparison to ensure don't go beyond
			;512 

			;get the random number at RANDOM_OFFSET
			mov bx, RANDOM_NUM
			add bx, cx
			mov ax, 0
			mov al, [bx]

			cmp al, dl
		jg loop10
	ret


;get a card
;modifies ax, bx, cx, dx
;return in al

	get_card:

		call get_next_rand
	
		;get_next_random returns offset in al
		mov bx, CARDS
		add bx, ax

		mov al, [bx]

		push ax		;push card held at CARDS[al] onto stack	
		push bx		;push address of CARDS[al] onto stack

		mov cx, 0
		mov cl, [LAST_CARD]

		mov bx, CARDS
		add bx, cx	;get address of CARDS[LAST_CARD]
		mov ax, bx	;hold address in ax

		mov dx,0
		mov dl, [bx]

		pop bx
		mov [bx], dl

		pop dx		;dx now holds card number to return
		mov bx, ax
		mov [bx], dl

		mov ah, [LAST_CARD]	;decrement LAST_CARD 
		dec ah
		mov [LAST_CARD], ah

		mov al, dl 	;return card number in al
	ret



;-------------------------------------------------------------------
;Set up the card arrays

	;set CARDS 0 to 51
	;uses dx, bx

	set_cards:
		mov dl, 0		;value to stick in array
		mov dh, 0  		;counter
		mov bx, CARDS

		loop_top2:
			mov [bx], dl
			add bx, 1
			inc dl
			inc dh
			cmp dh, 52
		jl loop_top2
	ret


	;set the values of CARD_VALUES
	;uses dx, al, bx

	set_card_values:
		mov dl, 2		;value
		mov dh, 0		;inner loop counter
		mov al, 0		;outer loop counter

		mov bx, CARD_VALUES

		loop_top1:
		
			inner_loop_top1:
			
				mov [bx], dl
				inc dh
				add bx,1
				cmp dh,4
			jl inner_loop_top1

			mov dh,0
			inc dl
			inc al

			cmp al,8
		jl loop_top1
		
		mov dh, 0
		loop_top3:		;set 10 - King to 10
			
			mov [bx], byte 10
			add bx, 1
			inc dh
			cmp dh, 16
		jl loop_top3

		mov dh, 0
			
		loop_top4:
			
			mov [bx], byte 11
			add bx,1
			inc dh
			cmp dh, 4
		jl loop_top4
	
	ret


;set the suits in CARD_SUITES
;uses dx and bx

	set_card_suits:

		mov bx, CARD_SUITS
		mov dh, 0
	
		set_suit_top:
			mov dl, 'H'
			mov [bx], dl
			add bx, 1
	
			mov dl, 'D'
			mov [bx], dl
			add bx, 1

			mov dl, 'S'
			mov [bx], dl
			add bx, 1

			mov dl, 'C'
			mov [bx], dl
			add bx, 1

			inc dh
			cmp dh, 13
		jl set_suit_top
	ret

;set value to display for each card: 1-9 (ascii), T, J, Q, K, A
;uses dx, al, bx

	set_card_displays:
		mov dl, 2		;value
		add dl, 48		;set to ascii value
		mov dh, 0		;inner loop counter
		mov al, 0		;outer loop counter

		mov bx, CARD_DISPLAY

		loop_top7:
		
			inner_loop_top2:
			
				mov [bx], dl
				inc dh
				add bx,1
				cmp dh,4
			jl inner_loop_top2

			mov dh,0
			inc dl
			inc al

			cmp al,8
		jl loop_top7
		
		mov dh, 0
		mov dl, 'T'
		loop_top8:		;set T
			
			mov [bx], dl
			add bx, 1
			inc dh
			cmp dh, 4
		jl loop_top8

		mov dh, 0		;set Jack
		mov dl, 'J'
		loop_top9:
			
			mov [bx], dl
			add bx,1
			inc dh
			cmp dh, 4
		jl loop_top9

		mov dh, 0		;set Queen
		mov dl, 'Q'
		loop_top10:
			
			mov [bx], dl
			add bx,1
			inc dh
			cmp dh, 4
		jl loop_top10

		mov dh, 0		;set King
		mov dl, 'K'
		loop_top11:
			
			mov [bx], dl
			add bx,1
			inc dh
			cmp dh, 4
		jl loop_top11

		mov dh, 0		;set Ace
		mov dl, 'A'
		loop_top12:
			
			mov [bx], dl
			add bx,1
			inc dh
			cmp dh, 4
		jl loop_top12
	
	ret


	

;-------------------------------------------------------------------
;Define the card arrays

	;holds 0 to 51. Each represents a card. For example if CARD[12]
	; == 14 then CARD_VALUE[14] would give the value, CARD_SUIT[14]
	;would give the suit and CARD_DISPLAY[14] would give the display
	CARDS:
	times 52 db 0
		
	;holds values of cards: 2 to 11
	CARD_VALUES:
	times 52 db 0

	;holds suits of cards H,D,S,C
	CARD_SUITS:
	times 52 db 0	

	;holds ascii value of cards 2,3,...,J,Q,K,A
	CARD_DISPLAY:
	times 52 db 0

;--------------------------------------------------------------------
;512 random numbers between 0 and 51
	RANDOM_NUM:
		db 9, 3, 44, 45, 51, 37, 15, 8, 17, 11, 22, 40, 51, 49, 42, 8, 8, 32, 42, 22, 39, 10, 43, 0, 24, 4, 3, 15, 3, 17, 38, 12, 48, 7, 33, 47, 44, 48, 4, 37, 8, 2, 26, 35, 51, 44, 43, 7, 0, 10, 6, 40, 20, 49, 40, 20, 29, 20, 35, 32, 37, 50, 44, 33, 5, 2, 4, 25, 50, 8, 10, 6, 39, 36, 18, 38, 28, 9, 22, 29, 47, 28, 45, 15, 1, 9, 11, 30, 29, 47, 38, 42, 21, 6, 23, 26, 8, 4, 51, 7, 40, 9, 41, 27, 22, 35, 14, 26, 45, 12, 31, 16, 16, 24, 32, 17, 34, 19, 23, 39, 42, 37, 30, 11, 43, 29, 37, 28, 33, 36, 11, 22, 22, 28, 49, 20, 12, 39, 46, 33, 51, 26, 49, 15, 26, 5, 8, 8, 25, 7, 48, 15, 44, 26, 27, 12, 3, 12, 40, 13, 25, 51, 35, 23, 27, 8, 43, 39, 48, 37, 20, 23, 39, 46, 39, 14, 51, 23, 50, 24, 31, 46, 40, 51, 48, 43, 11, 28, 31, 51, 41, 32, 50, 0, 3, 26, 8, 22, 41, 4, 36, 38, 4, 23, 32, 19, 13, 31, 42, 12, 32, 49, 34, 48, 49, 31, 39, 8, 35, 46, 8, 24, 27, 34, 0, 6, 8, 8, 29, 26, 41, 13, 12, 45, 12, 44, 12, 26, 51, 2, 38, 31, 28, 48, 27, 25, 27, 42, 33, 10, 37, 17, 10, 12, 0, 10, 18, 36, 47, 23, 38, 36, 36, 50, 29, 25, 18, 17, 51, 18, 19, 13, 49, 23, 9, 1, 48, 13, 43, 6, 51, 28, 23, 38, 16, 51, 24, 35, 12, 19, 6, 50, 3, 19, 49, 8, 44, 15, 25, 19, 9, 21, 8, 35, 44, 17, 36, 17, 6, 3, 23, 6, 8, 22, 44, 24, 22, 44, 35, 34, 12, 18, 8, 43, 37, 5, 28, 5, 49, 29, 0, 34, 26, 8, 17, 47, 1, 29, 12, 8, 33, 11, 42, 41, 33, 10, 41, 31, 2, 25, 41, 42, 43, 50, 34, 4, 31, 10, 37, 28, 15, 37, 11, 42, 21, 4, 37, 22, 34, 25, 6, 43, 36, 24, 32, 45, 34, 21, 25, 13, 22, 42, 3, 41, 40, 13, 45, 20, 51, 6, 24, 15, 19, 11, 5, 40, 16, 18, 39, 26, 19, 21, 17, 3, 46, 25, 48, 4, 22, 49, 45, 45, 40, 49, 34, 4, 38, 4, 0, 38, 10, 25, 1, 6, 12, 34, 22, 4, 28, 9, 30, 47, 7, 23, 26, 1, 48, 50, 33, 19, 48, 27, 12, 12, 0, 22, 44, 38, 26, 45, 24, 13, 46, 1, 47, 6, 35, 17, 11, 39, 3, 17, 34, 10, 41, 8, 39, 13, 7, 48, 8, 31, 23, 48, 19, 51, 19, 11, 38, 21, 4, 38, 10, 50, 40, 5, 5, 51, 51, 44, 39, 2, 37, 49, 12, 2, 34, 27, 16, 41, 23, 24, 48, 23, 21, 15, 22, 16, 26, 8, 37, 31	

	
	RANDOM_OFFSET: db 6

	LAST_CARD: db 51
;--------------------------------------------------------------------

;use 0xff as the placeholder for an empty spot in hand
;0 refers to 2H

	;Player's hand
	PLAYER_HAND: times 13 db 0xff

	PLAYER_TOTAL: dw 1000

;--------------------------------------------------------------------

	;Dealer's hand
	DEALER_HAND: times 13 db 0xff

;--------------------------------------------------------------------

;Define the strings for prompts

	WELCOME: db 'Welcome to BIOS BlackJack: ', 0

	INVITE: db 'Do you wish to play a round? (y/n) ', 0

	HAND_STATUS: db '    You have:  ', 0

	DEALER_STATUS: db '  Dealer has:  ', 0

	HIT_OR_STAY: db 'Another card? (y/n) ', 0

	BUSTED: db 'Over 21! You are busted! ', 0x0a, 0x0a, 0x0d, 0

	DEALER_BUSTED: db 'Dealer Busted! You win!', 0x0a, 0x0a, 0x0d, 0

	YOU_WIN: db 'You win!', 0x0a, 0x0a, 0x0d, 0
		
	YOU_LOSE: db 'You lose!', 0x0a, 0x0a, 0x0d, 0

	PUSH: db 'Push!', 0x0a, 0x0a, 0x0d, 0

	CLOSING_MESSAGE: db 'Thanks for playing!', 0
	
;--------------------------------------------------------------------

	; Pad image to multiple of 512 bytes.
	times ((0xa00) - ($ - $$)) db 0x00


;TO DO

;RANDOM OFFSET need to be bigger than 8 bit
;Running total/change bet
;build in circle back to start for random number list
;Work on functions to reset after playing a hand
;Ace as 1 or 11





