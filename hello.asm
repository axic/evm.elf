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
		db	0xeb			; short jump 21 bytes forward
		db	0x15			; EVM: ISZERO
		;; There are 21 bytes available here
		db	0x60, 69		; EVM: PUSH1 69
		db	0x56			; EVM: JUMP
		db	0
		dd	0
		dw	0x20
		dw	0x01
		dd	0
		dd	0
		db	0
		mov	ecx, msg		; Point ecx at string
		mov	dl, 13			; Set edx to string length
		int	0x80			; eax = write(ebx, ecx, edx)
		xor     al, 13			; "error code" 0 if exact amount was written
		xchg	eax, ebx		; 1 = exit system call number
		int	0x80			; exit(ebx)
		;; This is the absolute offset 69 the EVM jumps to
		db	0x5b                    ; EVM: JUMPDEST
msg:		db	'hello, world', 10
