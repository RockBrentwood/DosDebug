;; --- debugger entries for DPMI protected-mode
;; --- exceptions (0, 1, 3, 6, 7, c, d, e)
;; --- stack frames DPMI exception handlers 16/32-bit
EXFR16 struc
	dw 8 dup (?)	;; pusha
wMsg	dw ?
	dw 2 dup (?)	;; far16 return to DPMI
wErrC	dw ?
rIP	dw ?
rCS	dw ?
rFL	dw ?
rSP	dw ?
rSS	dw ?
EXFR16 ends

EXFR32 struc
	dd 8 dup (?)	;; pushad
wMsg	dw ?
	dd 2 dup (?)	;; far32 return to DPMI
dwErrC	dd ?
rEIP	dd ?
rCS	dw ?
	dw ?
rEFL	dd ?
rESP	dd ?
rSS	dw ?
	dw ?
EXFR32 ends

excxx_16:
	pusha
	mov BP,SP
	push DS
	mov DS,CS:[dssel]
	mov AX,[BP].EXFR16.rIP
	mov BX,[BP].EXFR16.rCS
	mov CX,[BP].EXFR16.rFL
	mov DX,[BP].EXFR16.rSP
	mov SI,[BP].EXFR16.rSS
	mov DI,[BP].EXFR16.wMsg
	mov [BP].EXFR16.rCS, CS
	mov [BP].EXFR16.rSS, DS
	cmp [bInDbg],0				;; did the exception occur inside DEBUG?
	jz isdebuggee16
if EXCCSIP
	mov SI, BX
endif
	mov [BP].EXFR16.rIP,offset ue_intx
	mov BX, [top_sp]
	sub BX, 3*2
	mov [BX+0], DI
if EXCCSIP
	mov [BX+2], SI
	mov [BX+4], AX
endif
	mov [BP].EXFR16.rSP, BX
	and byte ptr [BP].EXFR16.rFL+1, not 1	;; reset TF
	pop AX
	jmp back2dpmi16
isdebuggee16:
	mov [BP].EXFR16.rIP, offset intrtn
	and byte ptr [BP].EXFR16.rFL+1, not 3	;; reset IF + TF
	mov [BP].EXFR16.rSP, offset regs.rSS
	mov [regs.rIP],AX
	mov [regs.rCS],BX
	mov [regs.rFL],CX
	mov [regs.rSP],DX
	mov [regs.rSS],SI
	mov [run_intw],DI
;;	pop AX
;;	mov [regs.rDS],AX
;;	mov DS,AX
	pop DS
back2dpmi16:
	popa
	add SP, 2
	retf

exc00:
	push EXC00MSG
	jmp exc_xx
exc01:
	push EXC01MSG
	jmp exc_xx
exc03:
	push EXC03MSG
	jmp exc_xx
if CATCHEXC06
exc06:
	push EXC06MSG
	jmp exc_xx
endif
if CATCHEXC07
exc07:
	push EXC07MSG
	jmp exc_xx
endif
if CATCHEXC0C
exc0c:
	push EXC0CMSG
	jmp exc_xx
endif
exc0d:
	push EXC0DMSG
	jmp exc_xx
exc0e:
	push EXC0EMSG
exc_xx:
	cmp CS:[dpmi32],0
	jz excxx_16

	.386

	pushad
	mov EBP,ESP
	push DS
	mov DS,CS:[dssel]
	mov EAX,[EBP].EXFR32.rEIP
	mov BX, [EBP].EXFR32.rCS
	mov ECX,[EBP].EXFR32.rEFL
	mov EDX,[EBP].EXFR32.rESP
	mov SI, [EBP].EXFR32.rSS
	mov DI, [EBP].EXFR32.wMsg
	mov [EBP].EXFR32.rCS, CS
	mov [EBP].EXFR32.rSS, DS
	cmp [bInDbg],0	;; did the exception occur inside DEBUG?
	jz isdebuggee32
if EXCCSIP
;; --- it's assumed that an exception in DEBUG is always in 16-bit code,
;; --- but this isn't necessarily true, since the debuggee may have hooked exceptions.
;; --- Since v2.0, this is less probable, because DebugX will always restore exception handlers 0d/0e on entry.
	mov SI, BX
endif
	mov [EBP].EXFR32.rEIP,offset ue_intx
	movzx EBX,[top_sp]
if EXCCSIP
 if EXCCSEIP
	sub BX, 2*2+4
 else
	sub BX, 3*2
 endif
else
	sub BX, 2
endif
	mov [BX+0], DI	;; msg
 if EXCCSIP
	mov [BX+2], SI	;; CS
  if EXCCSEIP
	mov [BX+4], EAX
  else
	mov [BX+4], AX
  endif
 endif
	mov [EBP].EXFR32.rESP, EBX
	and byte ptr [EBP].EXFR32.rEFL+1, not 1	;; reset TF
	pop AX
	jmp back2dpmi32
isdebuggee32:
	@dprintf "excxx: client exception"
	mov [EBP].EXFR32.rEIP, offset intrtn
	and byte ptr [EBP].EXFR32.rEFL+1, not 3	;; reset IF + TF
	mov [EBP].EXFR32.rESP, offset regs.rSS
	mov dword ptr [regs.rIP], EAX
	mov [regs.rCS],BX
;;	mov dword ptr [regs.rFL], ECX	;; preferable?
	mov [regs.rFL],CX
	mov dword ptr [regs.rSP], EDX
	mov [regs.rSS],SI
	mov [run_intw],DI
;;	pop AX
;;	mov [regs.rDS],AX
;;	mov DS,AX
	pop DS
back2dpmi32:
	popad
	add SP, 2
	retd
