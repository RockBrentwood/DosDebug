;; --- debugger entries for real-mode
;; --- a) program termination
;; --- b) exceptions (0, 1, 3, 6, 7, c, d, e)
;; --- c) sysreq pressed

;; --- v2.0: code changed so [run_int] is set only if entry is from
;; --- debuggee. If debugger is reentered because of an exception inside
;; --- the debugger, this must not be modified anymore.
if INT22
;; --- debugger's int 22h (program termination) handler.
;; --- there's no need to preserve registers.
intr22:
	cli
	mov CS:[run_int], INT22MSG	;; remember interrupt type
	mov CS:[lastcmd], offset dmycmd
	jmp intrtn_progtrm
endif

;; --- Interrupt 0 (divide error) handler.
intr00:
	mov CS:[run_int], EXC00MSG	;; remember interrupt type
	jmp intrtnr			;; jump to register saving routine

;; --- Interrupt 1 (single-step interrupt) handler.
intr01:
	mov CS:[run_int], EXC01MSG
	jmp intrtnr

if CATCHINT06
intr06:
	mov CS:[run_int], EXC06MSG
	jmp intrtnr
endif

if CATCHINT07
intr07:
	cmp CS:[bInDbg],0
	jz @F
	mov AX, EXC07MSG
	jmp ue_intxx
@@:
	mov CS:[run_int], EXC07MSG
	jmp intrtnr
endif

if CATCHINT0C
NotOurInt0C:
	jmp CS:[oldi0C]

intr0C:
 if MCLOPT
	cmp CS:[bMPicB], 20h
	jae @F
 endif
	push AX
	mov AL, 0bh		;; get ISR mask from PIC
	out 20h, AL
	in AL, 20h
	test AL, 10h	;; IRQ4 (int 0ch) occured?
	pop AX
	jnz NotOurInt0C
@@:
	cmp CS:[bInDbg],0
	jz @F
	mov AX, EXC0CMSG
	jmp ue_intxx
@@:
	mov CS:[run_int], EXC0CMSG
	jmp intrtnr
endif

if CATCHINT0D
NotOurInt0D:
	jmp CS:[oldi0D]

intr0D:
 if MCLOPT
	cmp CS:[bMPicB], 20h
	jae @F
 endif
	push AX
	mov AL, 0bh		;; get ISR mask from PIC
	out 20h, AL
	in AL, 20h
	test AL, 20h	;; IRQ5 (int 0dh) occured?
	pop AX
	jnz NotOurInt0D
@@:
	cmp CS:[bInDbg],0
	jz @F
	mov AX, EXC0DMSG
	jmp ue_intxx
@@:
	mov CS:[run_int], EXC0DMSG
	jmp intrtnr
endif

if CATCHSYSREQ
@@:
	jmp CS:[oldisrq]
intrsrq:
	test CS:[bInDbg], 1
	jnz @B
 if SYSRQINT eq 15h
	cmp AX, 8501h	;; sysreq released?
	jnz @B
 else
	pushf
	push CS
	call @B
	push DS
	push AX
	xor AX, AX
	mov DS, AX
	pop AX
	test byte ptr DS:[418h], 4	;; bit should be set while sysreq is pressed
	pop DS
	jnz @F
	iret
@@:
 endif
 if _PM
	inc CS:[bNoHook2F]	;; disable hooking
 endif
	mov CS:[run_int], SYSRQMSG	;; remember interrupt type
	jmp intrtnr
endif

;; --- Interrupt 3 (breakpoint interrupt) handler.
intr03:
	mov CS:[run_int], EXC03MSG	;; remember interrupt type

intrtnr proc
	cli					;; just in case
	pop CS:[regs.rIP]	;; recover things from stack
	pop CS:[regs.rCS]
	pop CS:[regs.rFL]
intrtn_progtrm::		;; <--- int 22h
	mov CS:[regs.rSS],SS	;; save stack position
	sizeprf
	mov CS:[regs.rSP],SP
	mov SP,CS			;; "push CS", "pop SS" without modifying [SP-2]
	mov SS,SP
	mov SP,offset regs.rSS
;; --- fall thru to intrtn
intrtnr endp
