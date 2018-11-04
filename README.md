# Bios_Blackjack
A bootloader that you can play blackjack against

Just a simple boot loader that allows the user to play a hand of blackjack. It uses the BIOS interrupts to print to the screen and obtain user input.

I wrote this as a way to understand the booting process and work with BIOS. It was a practical way to gain experience with segmented memory.

Compile with nasm to make a flat binary

  $nasm bios_blackjack.asm -f bin -o blackjack.bin
	
Run with emulator 

  $qemu-system-i386 -fda blackjack.bin

Just follow the prompts on the screen!
