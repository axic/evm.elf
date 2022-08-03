;; evm.elf is an experiment to make the same bytecode executable as ELF and EVM.
;; Source code and explanation to be found at https://github.com/axic/evm.elf
;; (C) Alex Beregszaszi
;;
;; Based on:
;; hello.asm: Copyright (C) 2001 Brian Raiter <breadbox@muppetlabs.com>
;; Licensed under the terms of the GNU General Public License, either
;; version 2 or (at your option) any later version.
;;
;; To build:
;;	nasm -f bin -o hello hello.asm && chmod +x hello
;; To use as EVM:
;;	xxd -ps -c 1000 hello > hello.evm

BITS 32

		org	0x05430000

		db	0x7F, "ELF"
		dd	1
		dd	0
		dd	$$
		dw	2
		dw	3
		dd	_start
		dw	_start - $$
_start:		inc	ebx			; 1 = stdout file descriptor
		add	eax, strict dword 4	; 4 = write system call number
		mov	ecx, msg		; Point ecx at string
		mov	dl, 13			; Set edx to string length
		int	0x80			; eax = write(ebx, ecx, edx)
		and	eax, 0x10020		; al = 0 if no error occurred
		xchg	eax, ebx		; 1 = exit system call number
		int	0x80			; exit(ebx)
msg:		db	'hello, world', 10
