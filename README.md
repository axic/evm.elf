# evm.elf

**What if one could write code which works on-chain and off-chain without changes?**

This snippet works both on Linux and Ethereum EVM:
```
7f454c46010000000000000000004305020003001a0043051a00430504000000eb15604556000000000020000100000000000000000000b947004305b20dcd80340d93cd805b6c68656c6c6f2c20776f726c640a3d52600c6013f3
```

On Linux (x86) it prints:
```shell
$ ./evm.elf
hello, world
```

On EVM it returns `hello, world`, too.

<small>Try it out on [jslinux](https://bellard.org/jslinux/vm.html?url=alpine-x86.cfg&mem=192) in the browser by uploading the file (use `xxd -ps -r 7f454c...` to make it a binary). Remember not to trust random binaries from a website on your machine.</small>

### What?!

So, how on earth did I end up doing this? Optimizing binary output size has a long history. For shortest "Hello World" [this thread](https://codegolf.stackexchange.com/questions/55422/hello-world) is a good way to get thrown into the rabbit hole. Or another specific one [for ELF files](https://codegolf.stackexchange.com/questions/5696/shortest-elf-for-hello-world-n), the format used on most POSIX systems, such as Linux (but not macOS). A well known resource on optimizing ELF files, with a lot of good explainers, is [The Teensy Files](http://www.muppetlabs.com/~breadbox/software/tiny/) by breadbox.

### How?

I started off with [this version](http://www.muppetlabs.com/~breadbox/software/tiny/hello.asm.txt):
```nasm
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
```

<small>(Quick explainer: `db` refers to verbatim bytes, `dw` to verbatim words (16-bits), and `dd` to verbatim double words (32-bits))</small>

We are super lucky with the ELF header as it starts with `0x7F`. This happens to be the opcode for `PUSH32`, meaning the first 33 bytes of an ELF file can be ignored from the EVM perspective. 

```
PUSH32 0x454c46010000000000000000004305020003001a0043051a00430504000000b9
BALANCE
STOP
...
```

Nice, but how do we avoid the `STOP` instruction and cram in some code there? The simplest approach is inserting an x86 jump instruction to skip over our EVM code.

Upon careful inspection of the ELF header description in the source code, it turns out there is a single instruction byte following the header in the `PUSH32` data. The `0xB9` byte at the end corresponds to the `mov ecx, msg` instruction ([`MOV`](https://www.felixcloutier.com/x86/mov)). Let's replace it with a [`JMP`](https://www.felixcloutier.com/x86/jmp)! Not so fast, the shortest encoding requires two bytes:

| Opcode | Description |
|--------|-------------|
| 0xEB offset  | Jump short, RIP = RIP + 8-bit displacement sign extended to 64-bits |

What if we chose the `offset` such that it corresponds to a tame EVM instruction? Remember that so far we are pushing a single item to the EVM stack, and so we need an instruction which isn't terminating and consumes at most a single stack item. There are many such instructions ([quick ref](https://www.evm.codes/)):
| Opcode | Instruction |
|--------|-------------|
| 0x15 | iszero |
| 0x19 | not |
| 0x30 | address |
| ...  | <small>*all the other context reading instructions*</small> |
| 0x35 | calldataload |
| 0x3B | extcodesize |
| ...  | <small>*many others*</small> |
| 0x50 | pop |
| 0x5B | jumpdest |
| 0x80 | dup1 |

So many options:
- `jumpdest` is partically a no-op if run into,
- `pop` would clean up the stack,
- `calldataload` just returns 0's on out of bounds (and our push value is substantial),
- `extcodesize` would return non-zero value if an account exists there,
- but `iszero` in our case always ensures we have a zero on the stack, which is useful.

Let us just go with `iszero`:
```nasm
_start:         inc     ebx                     ; 1 = stdout file descriptor
                add     eax, strict dword 4     ; 4 = write system call number
                db      0xeb                    ; short jump 21 bytes forward
                db      0x15                    ; EVM: ISZERO
                ;; There are 21 bytes available here
                dd      0
                dd      0
                dd      0
                dd      0
                dd      0
                dd      0
                db      0
                mov     ecx, msg                ; Point ecx at string
                mov     dl, 13                  ; Set edx to string length
                int     0x80                    ; eax = write(ebx, ecx, edx)
                and     eax, 0x10020            ; al = 0 if no error occurred
                xchg    eax, ebx                ; 1 = exit system call number
                int     0x80                    ; exit(ebx)
msg:            db      'hello, world', 10
```

x86 will skip ahead and the EVM will have the value 0 (after `iszero`) on the stack. Now we have 21 bytes to play with. Will that be enough to fit our EVM code?

Not so fast of course, there's one caveat here. It turns out the `and eax, 0x10020` line is important, because its payload represents two fields in the header. *Did I forgot to mention that the ELF code I started out with is already hyper-optimized and reuses certain parts of the header as code?* Use [this inspector tool](https://elfy.io/) to play around ELF files.

With this in mind, our 21 bytes looks like this:
```nasm
                ;; There are 21 bytes available here
                dd      0
                dd      0
                dw      0x20
                dw      0x01
                dd      0
                dd      0
                db      0
```

At this point the code remains fully operational on x86 and works in EVM with a clean termination:
```
PUSH32 0x454c46010000000000000000004305020003001a0043051a00430504000000eb
ISZERO
STOP
```

What do we even want to do in EVM? Probably something like this:
```javascript
6C..  push13 "hello, world"
3D    returndatasize
52    mstore
600c  push1 12
6014  push1 20
F3    return
```

It clearly won't fit into the 8 or 9 bytes around the required header fields. There are two paths we can take:
- use a different jump offset to have more free space,
- or jump to the end of the file and ignore some of the 21 bytes.

I decided for the latter for a secondary reason: to reuse the `hello, world` text already present there. Now our code looks like this:
```nasm
_start:         inc     ebx                     ; 1 = stdout file descriptor
                add     eax, strict dword 4     ; 4 = write system call number
                db      0xeb                    ; short jump 21 bytes forward
                db      0x15                    ; EVM: ISZERO
                ;; There are 21 bytes available here
                db      0x60, 69                ; EVM: PUSH1 69
                db      0x56                    ; EVM: JUMP
                db      0
                dd      0
                dw      0x20
                dw      0x01
                dd      0
                dd      0
                db      0
                mov     ecx, msg                ; Point ecx at string
                mov     dl, 13                  ; Set edx to string length
                int     0x80                    ; eax = write(ebx, ecx, edx)
                xor     al, 13                  ; "error code" 0 if exact amount was written
                xchg    eax, ebx                ; 1 = exit system call number
                int     0x80                    ; exit(ebx)
                ;; This is the absolute offset 69 the EVM jumps to
                db      0x5b                    ; EVM: JUMPDEST
msg:            db      'hello, world', 10
```

Notice that we simplified the cryptic `and eax, 0x10020` statement as it isn't needed anymore for header-matching.

The next step is to insert our EVM code around the text there:
```nasm
                ;; This is the absolute offset 69 the EVM jumps to
                db      0x5b                    ; EVM: JUMPDEST
                db      0x6c                    ; EVM: PUSH13
msg:            db      'hello, world', 10
                db      0x3d                    ; EVM: RETURNDATASIZE
                db      0x52                    ; EVM: MSTORE
                db      0x60, 12                ; EVM: PUSH1 12 (avoid the new line character)
                db      0x60, 19                ; EVM: PUSH1 19 (offset to string)
                db      0xf3                    ; EVM: RETURN
```

Also remember that we already have the value 0 on the stack from the header, and so we could replace the `returndatasize` instruction with `swap1`. It would cost slightly more gas, but no stray items would be left on the stack.

The final proof of concept is the following:
```nasm
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
;;      nasm -f bin -o hello hello.asm && chmod +x hello
;; To use as EVM:
;;      xxd -ps -c 1000 hello > hello.evm

BITS 32

                org     0x05430000

                db      0x7F, "ELF"
                dd      1
                dd      0
                dd      $$
                dw      2
                dw      3
                dd      _start
                dw      _start - $$
_start:         inc     ebx                     ; 1 = stdout file descriptor
                add     eax, strict dword 4     ; 4 = write system call number
                db      0xeb                    ; short jump 21 bytes forward
                db      0x15                    ; EVM: ISZERO
                ;; There are 21 bytes available here
                db      0x60, 69                ; EVM: PUSH1 69
                db      0x56                    ; EVM: JUMP
                db      0
                dd      0
                dw      0x20
                dw      0x01
                dd      0
                dd      0
                db      0
                mov     ecx, msg                ; Point ecx at string
                mov     dl, 13                  ; Set edx to string length
                int     0x80                    ; eax = write(ebx, ecx, edx)
                xor     al, 13                  ; "error code" 0 if exact amount was written
                xchg    eax, ebx                ; 1 = exit system call number
                int     0x80                    ; exit(ebx)
                ;; This is the absolute offset 69 the EVM jumps to
                db      0x5b                    ; EVM: JUMPDEST
                db      0x6c                    ; EVM: PUSH13
msg:            db      'hello, world', 10
                db      0x3d                    ; EVM: RETURNDATASIZE
                db      0x52                    ; EVM: MSTORE
                db      0x60, 12                ; EVM: PUSH1 12 (avoid the new line character)
                db      0x60, 19                ; EVM: PUSH1 19 (offset to string)
                db      0xf3                    ; EVM: RETURN
```

When assembled this is 91 bytes total. The input we started with was 62 bytes. Not too bad for a simple approach.

There is a nice benefit of keeping those zeroes in the middle of the code, they actually correspond to other ELF headers, which in this case are "more compliant" then the code we started with.

### What next?

There's so much room for improvement here. Too many zero bytes, not enough overlapping (reused) bytes, etc. One could add [ABI-compatible output](https://docs.soliditylang.org/en/v0.8.15/abi-spec.html) (the length needs to be prepended). Turn this into a [quine](https://en.wikipedia.org/wiki/Quine_(computing)). Use `nasm` labels for all the offsets/lengths. Rewrite from nasm to [etk](https://github.com/quilt/etk), [yul](https://docs.soliditylang.org/en/v0.8.15/yul.html), or [huff](https://huff.sh/). Make use of the `0x20` header byte as it corresponds to `keccak256`. The possibilities are endless.

**Anon, what will you do next?**

P.S.
The labels are a simple change, but make it harder to understand the EVM part:
```diff
-               db      0xeb                    ; short jump 21 bytes forward
-               db      0x15                    ; EVM: ISZERO
+               jmp     elf_main                ; EVM: ISZERO
```

### Appendix: EVM disassembly

```
   0:   push32 0x454c46010000000000000000004305020003001a0043051a00430504000000eb
  21:   iszero
  22:   push1 0x45
  24:   jump
  25:   stop
  26:   stop
  27:   stop
  28:   stop
  29:   stop
  2a:   keccak256
  2b:   stop
  2c:   add
  2d:   stop
  2e:   stop
  2f:   stop
  30:   stop
  31:   stop
  32:   stop
  33:   stop
  34:   stop
  35:   stop
  36:   stop
  37:   invalid_b9
  38:   selfbalance
  39:   stop
  3a:   number
  3b:   sdiv
  3c:   invalid_b2
  3d:   invalid_0d
  3e:   invalid_cd
  3f:   dup1
  40:   callvalue
  41:   invalid_0d
  42:   swap4
  43:   invalid_cd
  44:   dup1
  45:   jumpdest
  46:   push13 0x68656c6c6f2c20776f726c640a
  54:   returndatasize
  55:   mstore
  56:   push1 0x0c
  58:   push1 0x13
  5a:   return
```
