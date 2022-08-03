;; hello.asm: Copyright (C) 2001 Brian Raiter <breadbox@muppetlabs.com>
;; Licensed under the terms of the GNU General Public License, either
;; version 2 or (at your option) any later version.
;;
;; To build:
;;	nasm -f bin -o hello hello.asm && chmod +x hello

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

;; This is how the file looks when it is read as an (incomplete) ELF
;; header, beginning at offset 0:
;;
;; e_ident:	db	0x7F, "ELF"			; required
;;		db	1				; 1 = ELFCLASS32
;;		db	0				; (garbage)
;;		db	0				; (garbage)
;;		db	0				; (garbage)
;;		db	0x00, 0x00, 0x00, 0x00		; (unused)
;;		db	0x00, 0x00, 0x43, 0x05
;; e_type:	dw	2				; 2 = ET_EXE
;; e_machine:	dw	3				; 3 = EM_386
;; e_version:	dd	0x0543001A			; (garbage)
;; e_entry:	dd	0x0543001A			; program starts here
;; e_phoff:	dd	4				; phdrs located here
;; e_shoff:	dd	0x430031B9			; (garbage)
;; e_flags:	dd	0xCD0DB205			; (unused)
;; e_ehsize:	dw	0x2580				; (garbage)
;; e_phentsize:	dw	0x20				; phdr entry size
;; e_phnum:	dw	1				; one phdr in the table
;; e_shentsize:	dw	0xCD93				; (garbage)
;; e_shnum:	dw	0x6880				; (garbage)
;; e_shstrndx:	dw	0x6C65				; (garbage)
;;
;; This is how the file looks when it is read as a program header
;; table, beginning at offset 4:
;;
;; p_type:	dd	1				; 1 = PT_LOAD
;; p_offset:	dd	0				; read from top of file
;; p_vaddr:	dd	0x05430000			; load at this address
;; p_paddr:	dd	0x00030002			; (unused)
;; p_filesz:	dd	0x0543001A			; too big, but ok
;; p_memsz:	dd	0x0543001A			; equal to file size
;; p_flags:	dd	4				; 4 = PF_R
;; p_align:	dd	0x430031B9			; (garbage)
;;
;; Note that the top two bytes of the file's origin (0x43 0x05)
;; correspond to the instructions "inc ebx" and the first byte of "add
;; eax, IMM".
;;
;; The fields marked as unused are either specifically documented as
;; not being used, or not being used with 386-based implementations.
;; Some of the fields marked as containing garbage are not used when
;; loading and executing programs. Other fields containing garbage are
;; accepted because Linux currently doesn't examine then.
