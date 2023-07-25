
;; --- debugger entries for ring0 long-mode
;; --- a) exceptions (0, 1, 3, 6, 7, C, D, E)
;; --- b) sysreq pressed

;; --- v2.0: code changed so [run_int] is set only if entry is from
;; --- debuggee. If debugger is reentered because of an exception inside
;; --- the debugger, this var must not be modified anymore.

SKIPINTGPF equ 1	;; ignore GPFs caused by INT xx

	.386

FAULT64 struct
_errc   dd ?,?
_eip	dd ?,?
_cs		dd ?,?
_efl	dd ?,?
_esp	dd ?,?
_ss		dd ?,?
FAULT64 ends

EXCFR struct
wMsg    dw ?
wOfsOld dw ?
	FAULT64 <>
EXCFR ends

if CHKIOPL

CIIFR struct
dwESI	dd ?
wAX		dw ?
wDS		dw ?
wRet	dw ?
		EXCFR <>
CIIFR ends

;; --- check if at CS:(E)IP is an IOPL-sensitive instruction that
;; --- caused a GPF.
;; --- in: ESP = CIIFR
;; --- out: C if yes

checkioplinstr proc
	push DS
	push AX
	push ESI
	mov ESI, [ESP].CIIFR._eip
	mov DS, word ptr [ESP].CIIFR._cs
	cld
	lodsb DS:[ESI]
	cmp AL, 0FAh	;; CLI?
	jz isiopl
	cmp AL, 0FBh	;; STI?
	jz isiopl
if SKIPINTGPF
	cmp AL, 0CDh	;; INT XX? (causes GPF if gate's DPL=0)
	jz isiopl
endif
	jmp ci1
@@:
	lodsb DS:[ESI]
ci1:
	cmp AL, 0F3h	;; REP?
	jz @B
	cmp AL, 066h	;; size prefix?
	jz @B

;; --- E4/E5/E6/E7? IN AL/AX,XX - OUT XX,AL/AX
;; --- EC/ED/EE/EF? IN AL/AX,DX - OUT DX,AL/AX
;; --- 6C/6D/6E/6F? INSB/INSW   - OUTSB/OUTSW

	and AL, 0FCh
	cmp AL, 0E4h
	jz isiopl
	cmp AL, 0ECh
	jz isiopl
	cmp AL, 6Ch
	jz isiopl
	pop ESI
	pop AX
	pop DS
	clc
	ret
isiopl:
	pop ESI
	pop AX
	pop DS
	stc
	ret
checkioplinstr endp

endif

;; --- store value of cr2 in exc msg
rendercr2:
	cld
	push ES
	push DI
	push EAX
	mov ES, CS:[pspdbg]
	mov DI, offset exc0Ecr2
	mov EAX, cr2
	call hexdword
	pop EAX
	pop DI
	pop ES
	ret

;; --- exceptions must be handled by 64-bit code.

	.x64

@DefEnt64 macro intno
	pushw offset oldi&intno
if &intno&h ge 8
	pushw EXC&intno&MSG or (intno&h shl 8) or 8000h
	jmp [jmpv162]
else
	pushw EXC&intno&MSG or (intno shl 8)
	jmp [jmpv161]
endif
endm

_TEXT64 segment

intr00:				;; divide error
	@DefEnt64 00
intr01:				;; single-step interrupt
	@DefEnt64 01
intr03:				;; breakpoint interrupt
	@DefEnt64 03
if CATCHINT06
intr06:
	@DefEnt64 06
endif
if CATCHINT07
intr07:
	@DefEnt64 07
endif
if CATCHINT0C
intr0C:
	@DefEnt64 0C
endif
if CATCHINT0D
intr0D:
	@DefEnt64 0D
endif
intr0E:
	@DefEnt64 0E

_TEXT64 ends

	.386


if CATCHSYSREQ

 if SYSRQINT eq 15h
	.err <'SYSRQINT equ 15h' not implemented for RING0>
 endif

@@:
	jmp CS:[oldisrq]
intrsrq:
	test CS:[bInDbg], 1
	jnz @B
;; --- no way to call the real-mode IRQ handler from here. we check the sysreq
;; --- bit and, if set, read the kbd port direct, also sending EOI to the PIC.
;; --- Not really nice, but it works.
	push DS
	mov DS, CS:[wFlat]
	test byte ptr DS:[418h], 4	;; sysreq pressed?
	pop DS
	jz @B
	push AX
	in AL, 60h
	cmp AL, 54h+80h		;; sysreq released?
	pop AX
	jnz @B
	push DS
	mov DS, CS:[wFlat]
	and byte ptr DS:[418h], not 4
	pop DS
	push AX
	mov AL, 20h
	out 20h, AL
	pop AX
	push SYSRQMSG or (1 shl 8)
	jmp intr01ex
endif

;; --- exceptions with error code

intrtnp2:
if MCLOPT
	cmp CS:[bMPicB], 20h
	jae intrtnp
endif

	push AX
if 1
;; --- before checking the PIC, we check the status of EXCFR._cs
;; --- Since IRQs don't push error codes, this would be the
;; --- saved flags then. if IF and bit 1 aren't 1 (202h), it can't be
;; --- an IRQ.
	mov AX, word ptr [ESP+2].EXCFR._cs
	and AX, 202h
	cmp AX, 202h
	clc
	jnz @F
endif
	push CX
	mov AL, 0Bh		;; get ISR mask from PIC
	mov CL, byte ptr [ESP+4].EXCFR.wMsg+1
	out 20h, AL
	and CX, 7
	in AL, 20h
	bt AX, CX
	pop CX
@@:
	pop AX
	jnc intrtnp
	and byte ptr [ESP].EXCFR.wMsg+1, 7Fh	;; no error code on stack
nostop:
	push BX
	mov BX,[ESP+2].EXCFR.wOfsOld
	push DS
	mov DS, CS:[pspdbg]
	push dword ptr [BX]
	pop  dword ptr [jmpv64]
	pop DS
	pop BX
	test byte ptr [ESP].EXCFR.wMsg+1, 80h	;; error code real or faked?
	lea ESP, [ESP+2+2]						;; skip msg + oldvec addr
	jnz @F
	add ESP, 8
@@:
	jmp CS:[jmpv64]

;; --- exceptions without error code
intrtnp1:
	pushd 0		;; add a fake "error code" to the stack frame
	push dword ptr [ESP+4] ;; ensure that msg + wOfsOld are on top of stack

;; --- Common interrupt routine.

intrtnp proc

	cmp CS:[bInDbg],0
	jz int_dbgee
	pop AX		;; get msg
  if EXCCSIP
	add ESP, 2+8	;; skip wOfsOld + error code
	pop ECX
	add ESP, 4	;; skip high32 of rip
	pop DX
  endif
;;	mov SS, CS:[pspdbg]
;;	mov SP, CS:[top_sp]
	mov SS, CS:[wFlat]
	mov ESP, CS:[top_sp]
  if EXCCSIP
   if EXCCSEIP
	push ECX	;; EIP
   else
	push CX		;; IP
   endif
	push DX		;; CS
  endif
	mov AH, 0
	push AX		;; msg
	cmp AL, EXC0EMSG
	jnz ue_intx
	call rendercr2
	jmp ue_intx

int_dbgee:
;; --- check vector traps (set/reset by VT/VC)
	push AX
	mov AL, byte ptr [ESP+2].EXCFR.wMsg+1
	and AX, 1Fh
	bt CS:[wTrappedExc], AX	;; exception trapped?
	pop AX
	jnc nostop

if CHKIOPL
;; --- check if GPF caused by running CLI/STI/IN/OUT in IOPL=0
	cmp byte ptr [ESP].EXCFR.wMsg, EXC0DMSG
	jnz @F
	test byte ptr [ESP].EXCFR._efl+1, 30h	;; IOPL==0?
	jnz @F
	push AX
	lar AX, word ptr [ESP+2].EXCFR._cs
	test AH, 60h	;; ring 0?
	pop AX
	jz @F
	call checkioplinstr
	jc nostop	;; if yes, don't stop in debugger
@@:
endif

	push DS
	mov DS, CS:[pspdbg]
	pop [regs.rDS]
	pop [run_intw]

	add ESP, 2		;; skip wOfsOld

;; --- the rest of the stack contents should be preserved (for skip cmd)

	pop [regs.dwErrCode]
	add ESP, 4
	pop dword ptr [regs.rIP]
	add ESP, 4
	pop [regs.rCS]
	add ESP, 4+2
	pop dword ptr [regs.rFL]
	add ESP, 4
	pop dword ptr [regs.rSP]			;; pop SS:ESP
	add ESP, 4
	pop [regs.rSS]
	add ESP, 4+2

	mov [regs.r0Esp], ESP
	mov [regs.r0SS], SS
	mov SS, [pspdbg]
	mov ESP, offset regs.rSS
	mov DS, [regs.rDS]

	.8086

;; --- fall thru to intrtn

intrtnp endp

