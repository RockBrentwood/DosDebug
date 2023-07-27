;; --- debugger entries for ring0 protected-mode
;; --- a) exceptions (0, 1, 3, 6, 7, c, d, e)
;; --- b) sysreq pressed

;; --- v2.0: code changed so [run_int] is set only if entry is from
;; --- debuggee. If debugger is reentered because of an exception inside
;; --- the debugger, this var must not be modified anymore.
SKIPINTGPF equ 1	;; ignore GPFs caused by int xx

	.386

FAULT32 struct
_errc	dd ?
_eip	dd ?
_cs	dd ?
_efl	dd ?
FAULT32 ends

EXCFR struct
_ret	dw ?
wMsg	dw ?
	FAULT32 <>
EXCFR ends

if CHKIOPL

CIIFR struct
dwESI	dd ?
wAX	dw ?
wDS	dw ?
wRet	dw ?
	EXCFR <>
CIIFR ends

;; --- check if at CS:(E)IP is an IOPL-sensitive instruction that caused a GPF.
;; ---	in:	ESP = CIIFR
;; ---	out:	C if yes
checkioplinstr proc
	push DS
	push AX
	push ESI
	lds ESI, fword ptr [ESP].CIIFR._eip
	cld
	lodsb DS:[ESI]
	cmp AL, 0fah	;; cli?
	jz isiopl
	cmp AL, 0fbh	;; sti?
	jz isiopl
if SKIPINTGPF
	cmp AL, 0cdh	;; int XX? (causes GPF if gate's DPL=0)
	jz isiopl
endif
	jmp ci1
@@:
	lodsb DS:[ESI]
ci1:
	cmp AL, 0f3h	;; rep?
	jz @B
	cmp AL, 066h	;; size prefix?
	jz @B

;; --- e4/e5/e6/e7? in AL/AX,XX	- out XX,AL/AX
;; --- ec/ed/ee/ef? in AL/AX,DX	- out DX,AL/AX
;; --- 6c/6d/6e/6f? insb/insw	- outsb/outsw
	and AL, 0fch
	cmp AL, 0e4h
	jz isiopl
	cmp AL, 0ech
	jz isiopl
	cmp AL, 6ch
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

intr00:	;; divide error
	push EXC00MSG or (0 shl 8)
	call intrtnp1
	jmp CS:[oldi00]

intr01:	;; single-step interrupt
	push EXC01MSG or (1 shl 8)
intr01ex:
	call intrtnp1
	jmp CS:[oldi01]

intr03:	;; breakpoint interrupt
	push EXC03MSG or (3 shl 8)
	call intrtnp1
	jmp CS:[oldi03]

if CATCHINT06
intr06:
	push EXC06MSG or (6 shl 8)
	call intrtnp1
	jmp CS:[oldi06]
endif

if CATCHINT07
intr07:
	push EXC07MSG or (7 shl 8)
	call intrtnp1
	jmp CS:[oldi07]
endif

if CATCHINT0C
intr0C:
	push EXC0CMSG or (12 shl 8) or 8000h
	call intrtnp2
	jmp CS:[oldi0C]
endif

if CATCHINT0D
intr0D:
	push EXC0DMSG or (13 shl 8) or 8000h
	call intrtnp2
	jmp CS:[oldi0D]
endif

intr0E:
	push EXC0EMSG or (14 shl 8) or 8000h
	call intrtnp2
	jmp CS:[oldi0E]

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
if 0
	test byte ptr [ESP].EXCFR.wMsg+1, 08	;; int 08-0f?
	jz intrtnp
endif
if MCLOPT
	cmp CS:[bMPicB], 20h
	jae intrtnp
endif

	push AX
if 1
;; --- before checking the PIC, we check the status of EXCFR._cs
;; --- Since IRQs don't push error codes, this would be the saved flags
;; --- then. if IF and bit 1 aren't 1 (202h), it can't be an IRQ.
	mov AX, word ptr [ESP+2].EXCFR._cs
	and AX, 202h
	cmp AX, 202h
	clc
	jnz @F
endif
	push CX
	mov AL, 0bh		;; get ISR mask from PIC
	mov CL, byte ptr [ESP+4].EXCFR.wMsg+1
	out 20h, AL
	and CX, 7
	in AL, 20h
	bt AX, CX
	pop CX
@@:
	pop AX
	jnc intrtnp
	ret 2

;; --- exceptions without error code
intrtnp1:
	push dword ptr [ESP]	;; add a fake "error code" to the stack frame

;; --- Common interrupt routine.
intrtnp proc
	test byte ptr [ESP].EXCFR._efl+2, 2	;; VM set?
	jz novm86
nostop:
	test byte ptr [ESP].EXCFR.wMsg+1, 80h	;; error code real or faked?
	jnz @F
	ret 2+4				;; skip msg + faked error code
@@:
	ret 2
novm86:
	cmp CS:[bInDbg],0
	jz int_dbgee
	pop AX		;; skip _ret
	pop AX		;; get msg
	pop ECX		;; skip error code
  if EXCCSIP
	pop ECX		;; EIP
	pop EDX		;; CS
  endif
	mov SS, CS:[pspdbg]
	mov SP, CS:[top_sp]
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
	and AX, 1fh
	bt CS:[wTrappedExc], AX	;; exception trapped?
	pop AX
	jnc nostop

if CHKIOPL
;; --- check if GPF caused by running cli/sti/in/out in IOPL=0
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
	add ESP, 2		;; skip return addr
	pop [run_intw]

;; --- the rest of the stack contents should be preserved (for skip cmd)
	pop [regs.dwErrCode]
	pop dword ptr [regs.rIP]
	pop [regs.rCS]
	add ESP, 2
	pop dword ptr [regs.rFL]
	mov word ptr [regs.dwErrCode+2],AX	;; used to store AX temporarily
	lar AX, [regs.rCS]
	test AH, 60h						;; ring 0 exception?
	mov AX,word ptr [regs.dwErrCode+2]
	jz @F
	pop dword ptr [regs.rSP]			;; pop ring3 SS:ESP
	pop [regs.rSS]
	add ESP, 2
	mov [regs.r0Esp], ESP
	mov [regs.r0SS], SS
	jmp intrtn_r0
@@:
	mov dword ptr [regs.rSP], ESP		;; save ring0 stack in regs
	mov [regs.r0Esp], ESP				;; also store here (for getr0stk())
	mov [regs.rSS], SS
	mov [regs.r0SS], SS
intrtn_r0:
	mov SS, [pspdbg]
	mov ESP, offset regs.rSS
	.8086
	mov DS, [regs.rDS]

;; --- fall thru to intrtn
intrtnp endp
