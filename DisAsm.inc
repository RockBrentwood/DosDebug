;; Here is the start of the disassembly part of the program.

;; --- flags variables preflags/preused
PRESEG	equ 1	;; segment prefix
PREREP	equ 2	;; rep prefixes
PREREPZ	equ 4	;; f3, not f2
PRELOCK	equ 8	;; lock prefix
PRE32D	equ 10h	;; flag for operand size (66h)
PRE32A	equ 20h	;; flag for address size (67h)
PREWAIT	equ 40h	;; prefix wait (not really a prefix)
GOTREGM	equ 80h	;; set if we have the reg/mem part

;; --- equates for disflags:
DIS_F_REPT	equ 1	;; repeat after pop SS, etc.
DIS_F_SHOW	equ 2	;; show memory contents
DIS_I_SHOW	equ 4	;; there are memory contents to show
DIS_I_UNUSED	equ 8	;; (internal) print " (unused)"
DIS_I_SHOWSIZ	equ 10h	;; (internal) always show the operand size
DIS_I_KNOWSIZ	equ 20h	;; (internal) we know the operand size of instr.
DIS_I_MEMACC	equ 80h	;; (internal) we're just accessing a mem ref (dumpreg)

;; --- define "general purpose register"
DefineRv macro regist
REG_&regist& equ ($ - RvName)/2
	db "&regist&"
endm

;; --- register table
;; ---	00-07:	8-bit registers
;; ---	08-15:	16-bit registers
;; ---	16-23:	32-bit registers
REG_NO_GPR	equ 24

;; --- define "segment register"
DefineRs macro regist
REG_&regist& equ REG_NO_GPR + ($ - RsName)/2
	db "&regist&"
endm

_DATA segment
dis_n		dw 0	;; number of bytes in instruction so far
		dw 0	;; must follow dis_n (will always remain 0)
idxins		dw 0	;; index of the instruction (unsqueezed)
addrr		dw 0	;; address in mod r/m byte (16bit only)
sizeloc		dw 0	;; address of size words in output line

;; --- preflags and preused must be consecutive
preflags	db 0	;; flags for prefixes found so far
preused		db 0	;; flags for prefixes used so far

instru		db 0	;; the main instruction byte
rmsize		db 0	;; <0 or 0 or >0 means mod r/m is 8 or 16 or 32
segmnt		db 0	;; segment determined by prefix (or otherwise)
disflags	db 0	;; flags for the disassembler
disflags2	db 0	;; another copy of DIS_I_KNOWSIZ
_DATA ends

CONST segment
;; --- Table of obsolete-instruction values.
;; --- Instructions are feni, fdisi, fsetpm, mov to/from TRx
obsinst	dw SFPGROUP3, SFPGROUP3+1, SFPGROUP3+4
	dw SPARSE_BASE+24h, SPARSE_BASE+26h

;; --- Table for 16-bit mod r/m addressing. 8 = BX, 4 = BP, 2 = SI, 1 = DI.
rmtab	db 8+2, 8+1, 4+2, 4+1, 2, 1, 4, 8

;; --- Tables of register names.
;; --- RvName/RwName/RsName must be consecutive.
;; --- also used by the line assembler
RvName label word
	DefineRv AL
	DefineRv CL
	DefineRv DL
	DefineRv BL
	DefineRv AH
	DefineRv CH
	DefineRv DH
	DefineRv BH
RwName label word
	DefineRv AX
	DefineRv CX
	DefineRv DX
	DefineRv BX
	DefineRv SP
	DefineRv BP
	DefineRv SI
	DefineRv DI
NUM_Rws equ ($ - RwName)/2
RsName label word
	DefineRs ES
	DefineRs CS
	DefineRs SS
	DefineRs DS
	DefineRs FS
	DefineRs GS
NUM_Rss equ ($ - RsName)/2
	DefineRs ST
	DefineRs MM
	DefineRs CR
	DefineRs DR
	DefineRs TR
NUM_Regs equ ($ - RvName)/2

;; --- address of debuggee's segment registers
;; --- used to display memory contents (DIS_F_SHOW)
segrgaddr	dw regs.rES, regs.rCS, regs.rSS, regs.rDS
if RING0	;; for DebugR, we also display FS/GS contents
		dw regs.rFS, regs.rGS
endif

;; --- Tables for handling of named prefixes.
prefixlist	db 26h, 2eh, 36h, 3eh, 64h, 65h	;; segment prefixes (in order)
		db 9bh, 0f0h, 0f2h, 0f3h	;; wait, lock, repne, repe
N_PREFIX	equ $ - prefixlist
prefixmnem	dw MN_WAIT, MN_LOCK, MN_REPNE, MN_REPE
CONST ends

disasm1:				;; <--- standard entry
	mov AL, 0

disasm proc				;; <--- entry with AL=disflags (DIS_F_REPT & DIS_F_SHOW)
	mov [disflags], AL

CONST segment	;; must be located inside disasm since local labels are used here
	align 2

;; Jump table for _I?, _E?, _M?, _X?, _O?, _R?, _r?, and _A?.
;; See orders of AsmJump1 and BitTab.
DisJump1 label word
	dw DOpIx, DOpEx, DOpMx, DOpXx
	dw DOpAn, DOpRx, DOprx, DOpAx

;; The jump table for displaying operands.
;; See the orders of AsmJump1 and BitTab.
DisOpTab label word
	dw DOpQ, DOpMF, DOpMD, DOpMLD		;; 00-03
	dw DOpMxx, DOpMf, DOpAf, DOpJb		;; 04-07
	dw DOpJv, DOpST1, DOpSTi, DOpCRx	;; 08-11
	dw DOpDRx, DOpTRx, DOpRs, DOpDs		;; 12-15
	dw DOpDb, DOpMMx, DOpN			;; 16-18
;; --- string items _1 .. _SS
	db '1', 0				;; 19
	db '3', 0				;; 20
	db 'DX'					;; 21
	db 'CL'					;; 22
	db 'ST'					;; 23
	db 'CS', 'DS', 'ES', 'FS', 'GS', 'SS'	;; 24-29

;; --- Jump table for a certain place.
;; --- the size of this table matches OPTYPES_BASE
dis_jmp2 label word
	dw disbad	;; illegal instruction
	dw da_twobyte	;; two byte instruction (0f xx)
	dw da_insgrp	;; instruction group
	dw da_fpuins	;; coprocessor instruction
	dw da_fpugrp	;; coprocessor instruction group
	dw da_insprf	;; instruction prefix (including 66h/67h)
OPTYPES_BASE equ $ - dis_jmp2
CONST ends

if FLATSS
	.386
;;	mov [savesp2], ESP
	mov [run_sp], ESP
else
;;	mov [savesp2], SP
	mov [run_sp], SP
endif
	xor AX, AX
	mov [dis_n], AX
	mov word ptr [preflags], AX	;; clear preflags and preused
if ?PM
	mov BX, [u_addr+4]
	call getseldefsize
	mov [bCSAttr], AL
 if 0
;; --- ?PM v2.1: don't preset opsize/adrsize prefixes if D bit is set;
;; --- those prefixes toggle just once.
	jz @F
	or [preflags], PRE32D or PRE32A
;;	or [preused], PRE32D or PRE32A
@@:
 endif
endif
	mov [segmnt], 3			;; initially use DS segment
	mov [rmsize], 80h		;; don't display any memory
	mov word ptr [ai.dismach], 0	;; no special machine needed, so far
	call disgetbyte			;; get a byte of the instruction
	cmp AL, 9bh			;; wait instruction (must be the first prefix)
	jne da2				;; if not

;; The wait instruction is actually a separate instruction as far as the x86 is concerned,
;; but we treat it as a prefix since there are some mnemonics that incorporate it.
;; But it has to be treated specially since you can't do, e.g., seg CS wait ... but must do wait seg CS ... instead.
;; We'll catch it later if the wait instruction is not going to be part of a shared mnemonic.
	or [preflags], PREWAIT

;; If we've found a prefix, we return here for the actual instruction (or another prefix).
da1:
	call disgetbyte
da2:
	mov [instru], AL	;; save away the instruction
	mov AH, 0

;; --- Now we have the sequence number of the instruction in AX.
;; --- Look it up.
da3:
	mov BX, AX
	mov [idxins], AX	;; save the compressed index
	cmp AX, SPARSE_BASE
	jb @F			;; if it's not from the squeezed part of the table
	mov BL, [sqztab+BX-SPARSE_BASE]
	mov BH, 0
	add BX, SPARSE_BASE	;; BX = compressed index
@@:
	mov CL, [optypes+BX]	;; CX = opcode type
	mov CH, 0
	shl BX, 1
	mov BX, [opinfo+BX]	;; BX = other info (mnemonic if a true instruction)
	mov SI, CX
	mov AX, BX
	mov CL, 12
	shr AX, CL
	cmp AL, [ai.dismach]
	jb @F			;; if a higher machine is already required
	mov [ai.dismach], AL	;; set machine type
@@:
	and BH, 0fh		;; =and BX, 0fffh - remove the machine field
	cmp SI, OPTYPES_BASE
	jae da13pre		;; if this is an actual instruction
	call [dis_jmp2+SI]	;; otherwise, do more specific processing
	jmp da3			;; back for more

;; --- dis_jmp2[1]: Two-byte instruction 0f xx: index 1e0-2df.

da_twobyte:
	call disgetbyte
	mov [instru], AL
	mov AH, 0
	add AX, SPARSE_BASE
	ret

;; --- dis_jmp2[2]: Instruction group.
;; --- BX contains "instruction base": 100h, 110h, ...
da_insgrp:
	call getregmem_r	;; get the middle 3 bits of the R/M byte
	cbw
	add AX, BX		;; offset
	ret

;; --- dis_jmp2[3]: Coprocessor instruction.
;; --- BX contains "instruction base": 148h, 158h, ...
da_fpuins:
	or [disflags], DIS_I_SHOWSIZ
	or [ai.dmflags], DM_COPR
	call getregmem
	cmp AL, 0c0h
	jb da_insgrp	;; range 00-bfh is same as an instruction group
	mov CL, 3
	shr AL, CL	;; c0-ff --> 18-1f
	sub AL, 18h-8	;; 18-1f --> 08-0f
	cbw
	add AX, BX	;; offset
	ret

;; --- dis_jmp2[4]: Coprocessor instruction group.
;; --- BX contains "instruction base": 1c8h, 1d0h, 1d8h
da_fpugrp:
	mov AL, [ai.regmem]
	and AL, 7
	cbw
	add AX, BX
	ret

;; --- dis_jmp2[5]: Instruction prefix.
;; --- At this point, BL = prefix bits; BH = segment
da_insprf:
if 0	;; v2.1: removed - opsize/adrsize prefixes "toggle" just once
	mov AL, BL
	and BL, not (PRE32D or PRE32A)	;; these flags are XORed!
endif
	test BL, [preflags]
	jnz disbad0		;; if there are duplicates
	or [preflags], BL
if 0	;; v2.1: removed - opsize/adrsize prefixes "toggle" just once
	mov BL, AL
	and AL, PRE32D or PRE32A
	xor [preflags], AL
endif
	test BL, PRESEG
	jz @F			;; if not a segment
	mov [segmnt], BH	;; save the segment
@@:
	pop AX			;; discard return address
	jmp da1

disbad0:
	jmp disbad		;; we don't allow duplicate prefixes


da13pre:

if ?PM	;; v2.1: update opsize/adrsize prefixes if D bit set AFTER prefixes have been read
	test [bCSAttr], 40h
	jz @F
	xor [preflags], PRE32D or PRE32A
@@:
endif

;; OK.
;; Here we go.
;; This is an actual instruction.
;; BX=offset of mnemonic in mnlist
;; SI=offset of operand list in oplists
;; First print the op mnemonic.
da13::
	push SI
	lea SI, [mnlist+BX]		;; offset of mnemonic
	cmp SI, offset mnlist+MN_BSWAP
	jne @F				;; if not BSWAP
	call dischk32d
	jz disbad0			;; if no operand-size prefix
@@:
	call showop			;; print out the op code (at line_out+28)
	mov [sizeloc], 0		;; clear out this flag
	pop SI				;; recover list of operands
	add SI, offset oplists - OPTYPES_BASE
	cmp byte ptr [SI], 0
	je da21				;; if we're done

;; Loop over operands.
;; SI -> operand type.
;; Fortunately the operands appear in the instruction in the same order as they appear in the disassembly output.
da14:
	mov [disflags2], 0		;; clear out size-related flags
	lodsb				;; get the operand type
	cmp AL, OpLo
	jb da18				;; if it's not size dependent
	mov [disflags2], DIS_I_KNOWSIZ	;; indicate variable size
	cmp AL, OpB
	jae da16			;; if the size is fixed (8, 16, 32, 64)
	cmp AL, OpV
	jae da15			;; if word or dword
	mov AH, -1
	test [instru], 1
	jz da17				;; if byte
da15:
	or [preused], PRE32D		;; mark this flag as used
	mov AH, [preflags]
	and AH, PRE32D			;; this will be 10h for dword, 00h for word
	jmp da17			;; done

da16:
	mov AH, AL		;; OpB, OpW, OpD or OpQ (we know which)
	and AH, 0f0h		;; this converts AH to <0 for byte, =0 for word,
	sub AH, OpW		;; and >0 for dword (byte=f0, word=0, dword=10, qword=20)

;; --- Now we know the size (in AH); branch off to do the operand itself.
da17:
	mov BL, AL
	and BX, 0eh		;; 8 entries (IMM, RM, M, R_MOD, M_OFFS, R, R_ADD, AX)
	call [DisJump1+BX]	;; print out the operand
	jmp da20		;; done with operand

;; --- Sizeless operands.
da18:
	cbw
	cmp AL, _Str
	xchg AX, BX		;; mov BX, AX
	mov AX, [DisOpTab+BX-2]
	jb @F			;; if it's not a string
	stosw
	cmp AH, 0
	jnz da20		;; if it's two characters
	dec DI
	jmp da20		;; done with operand
@@:
	call AX			;; otherwise, do something else

;; --- operand done, check if there's another one
da20:
	cmp byte ptr [SI], 0
	jz da21			;; if we're done
	mov AL, ','
	stosb
	jmp da14		;; another operand

;; --- all operands done.
;; --- now check and loop for unused prefixes:
;; --- opsize (66h), addrsize (67h), wait, segment, rep[n][z], lock
da21:
	mov AL, [preused]
	not AL
	and AL, [preflags]
	jnz @F			;; if some flags remain unused
	jmp da_done		;; if all flags were used
@@:
	mov CX, N_WTAB
	mov BX, offset wtab1
	mov DX, 2*N_WTAB-2
	mov AH, PREWAIT
	test AL, AH
	jnz @F			;; if there's a wait prefix hanging

;; --- todo: the string instructions may have both 66h&67h prefixes
	mov CX, N_LTABO
	mov BX, offset ltabo1
	mov DX, 2*N_LTABO-2
	mov AH, PRE32D
	test AL, AH
	jnz @F			;; if it's not a 66h prefix that's hanging

	mov CX, N_LTABA
	mov BX, offset ltaba1
	mov DX, 2*N_LTABA-2
	mov AH, PRE32A
	test AL, AH
	jnz @F			;; if it's not a 67h prefix that's hanging
	jmp da_chkseg
@@:
	or [preused], AH	;; mark this prefix as used
	push DI
	mov DI, BX
	mov BL, AH
	mov AX, [idxins]
	repne scasw
	jne da23_1		;; if not found in the list
	add DI, DX		;; replace the mnemonic with the 32-bit name
	mov SI, [DI]
	add SI, offset mnlist
	call showop		;; copy op mnemonic
da23_0:
	pop DI
	jmp da21
da23_1:
if ?PM
	test BL, PRE32A or PRE32D	;; is a 66/67 prefix unhandled?
	jz disbad2
	test [bCSAttr], 40h		;; 32bit code segment?
	jnz da23_0				;; then ignore those.
endif
disbad2:
	jmp disbad

da_chkseg:
	test AL, PRESEG
	jz da_chkrep		;; if not because of a segment prefix
	mov AX, [idxins]
	cmp AH, 0
	jnz disbad2		;; if index > 256
	push DI
	mov CX, P_LEN
	mov DI, offset prfxtab
	repne scasb
	pop DI
	jne disbad2		;; if it's not on the list
	mov CX, 3
	call moveover
	push DI
	mov DI, offset line_out+MNEMONOFS
	call showseg		;; show segment register
	mov AL, ':'
	stosb
	pop DI
	or [preused], PRESEG		;; mark it as used
	jmp da21

da_chkrep:
	test AL, PREREP
	jz da_chklock		;; if not a rep prefix
	and AL, PREREP+PREREPZ
	or [preused], AL
	mov AX, [idxins]
	cmp AH, 0
	jnz disbad2		;; if not in the first 256 bytes
	and AL, not 1		;; clear bit0 (movsw -> movsb)
	push DI
	mov DI, offset replist
	mov CX, N_REPNC		;; scan those for rep first
	repne scasb
	mov SI, offset mnlist+MN_REP
	je da27			;; if one of the rep instructions
	mov CL, N_REPALL - N_REPNC
	repne scasb
	jne disbad2		;; if not one of the repe/repne instructions
	mov SI, offset mnlist+MN_REPE
	test [preused], PREREPZ
	jnz da27		;; if repe
	mov SI, offset mnlist+MN_REPNE
	jmp da27		;; it's repne

disbad3:
	jmp disbad

da_chklock:
	test AL, PRELOCK
	jz disbad3		;; if not a lock prefix, either
	push DI
	mov AX, [idxins]
	mov DI, offset locktab
	mov CX, N_LOCK
	repne scasw
	jne disbad3		;; if not in the approved list
	test [preused], PRESEG
	jz disbad3		;; if memory was not accessed
	mov SI, offset mnlist+MN_LOCK
	or [preused], PRELOCK

;; --- Slip in another mnemonic: rep/repe/repne/lock.
;; --- SI = offset of mnemonic, what should be
;; --- DI is on the stack.
da27:
	pop DI
	mov CX, 8
	push SI
	call moveover
	pop SI
	push DI
	call showop
	pop DI
	jmp da21

;; --- Done with instruction.
;; --- Erase the size indicator, if appropriate.
da_done:
	mov CX, [sizeloc]
	cmp CX, 0
	jz da28b		;; if there was no size given
	mov AL, [disflags]
	test AL, DIS_I_SHOWSIZ
	jnz da28b		;; if we need to show the size
	test AL, DIS_I_KNOWSIZ
	jz da28b		;; if the size is not known already
	xchg CX, DI
	mov SI, DI		;; save old DI
	mov AL, ' '
@@:
	scasb			;; skip size name
	jne @B			;; if not done yet
				;; (The above is the same as repne scasb, but has no effect on CX.)
	add DI, 4		;; skip 'PTR '
	xchg SI, DI
	sub CX, SI
	rep movsb		;; move the line

;; --- Now we're really done.
;; --- Print out the bytes on the left.
da28b:
	push DI		;; print start of disassembly line
	mov DI, offset line_out
	mov AX, [u_addr+4]	;; print address
	call hexword
	mov AL, ':'
	stosb
	sizeprfX		;; mov EAX, [u_addr+0]
	mov AX, [u_addr+0]
if ?PM
	mov SI, hexword
	test [bCSAttr], CS32ATTR
	jz @F
	mov SI, hexdword
@@:
	call SI
else
	call hexword
endif
	mov AL, ' '
	stosb
	mov BX, [dis_n]
@@:
	mov SI, offset line_out+MNEMONOFS - 1
	sub SI, DI
	shr SI, 1
	cmp BX, SI
	jle da29		;; if it's a short instruction which fits in one line
	sub BX, SI
	push BX
	mov BX, SI
	push DI
	call disshowbytes
	call putsline
	pop CX
	pop BX
	mov DI, offset line_out
	sub CX, DI
	mov AL, ' '
	rep stosb
	jmp @B
da29:
	call disshowbytes
	mov AL, ' '		;; pad to op code
	mov CX, offset line_out+MNEMONOFS
	sub CX, DI
	jc @F
	rep stosb
@@:
	pop DI
	test [disflags], DIS_I_UNUSED
	jz da32			;; if we don't print ' (unused)'
	mov SI, offset unused
	cmp byte ptr [DI-1], ' '
	jne @F			;; if there's already a space here
	inc SI
@@:
	call copystring	;; SI->DI

;; --- Print info. on minimal processor needed.
da32:
	push DI
	mov DI, offset obsinst
	mov CX, [idxins]
	call showmach	;; show the machine type, if needed
	pop DI
	jcxz da32f		;; if no message

;; --- Print a message on the far right.
	mov AX, offset line_out+79
	sub AX, CX
	push CX
	call tab_to		;; tab out to the location
	pop CX
	rep movsb		;; copy the string
	jmp da32z		;; done

;; --- Dump referenced memory location.
da32f:
	mov AL, [disflags]
	xor AL, DIS_F_SHOW + DIS_I_SHOW
	test AL, DIS_F_SHOW + DIS_I_SHOW
	jnz da32z		;; if there is no memory location to show
ife RING0			;; for DebugR, FS/GS memory contents aren't skipped
	cmp [segmnt], 3
	ja da32z		;; if FS or GS
endif
	mov AX, offset line_out+79-8	;; room for SS:oooo=bb|wwww|dddddddd
	mov CX, 2
	cmp [rmsize], 0
	jl da32h		;; if byte
	jz @F			;; if word
	add CX, 4		;; 4 more chars
@@:
	add CX, 2		;; 2 more chars
da32h:
	sub AX, CX
	push CX
	call tab_to
	call showseg		;; show segment register
	mov AL, ':'
	stosb
	mov AX, [addrr]
	call hexword		;; show offset
	mov AL, '='
	stosb
	mov AL, [segmnt]	;; segment number
	cbw
	shl AX, 1
	xchg AX, BX		;; mov BX, AX
	mov BX, [segrgaddr+BX]	;; get address of value
if ?PM
;; --- v2.0: we don't want that just msg "General Protection Fault"
;; --- appears, without a hint what the underlying problem is.
;; --- so display what's rendered up to now...
	call puts
	or [disflags], DIS_I_MEMACC	;; tell exc handler to print a crlf first
	mov DI, offset line_out
endif
	pop CX
	shr CL, 1
;; --- v2.0: just read the bytes that the instruction would
	push DS
	mov DS, [BX]
	mov BX, CS:[addrr]
	add BX, CX
@@:
	dec BX
	mov AL, [BX]
	call hexbyte	;; display byte
	dec CL
	jnz @B
	pop DS
if ?PM
	and [disflags], not DIS_I_MEMACC
endif

da32z:
	call trimputs		;; print (rest of) disassembled line
	mov AL, [disflags]
	test AL, DIS_F_REPT
	jz da34			;; if we're not allowed to repeat ourselves
	test AL, DIS_I_UNUSED
	jnz @F			;; if we printed ' (unused)'
	mov AX, [idxins]
	cmp AX, 17h
	je @F			;; if it was 'pop SS'
	cmp AX, 8eh
	je @F			;; if it was 'mov SS, --'
	cmp AX, 0fbh
	jne da34		;; if it was not 'sti'
@@:
	jmp disasm1
da34:
	ret

;; --- MOD R/M (_E?)
DOpEx:
	call getregmem
	cmp AL, 0c0h
	jb dop05
	jmp dop_r1			;; if pure register reference
dop05:					;; <--- used by _M?, _Q, _MLD
	call showsize		;; print out size in AH
dop06:					;; <--- used by _O?, _Mx, _MF, _MD
	or [preused], PRESEG	;; needed even if there's no segment override
						;; because handling of lock prefix relies on it
	test [preflags], PRESEG
	jz @F				;; if no segment override
	call showseg		;; print segment name
	mov AL, ':'
	stosb
@@:
	mov AL, [ai.regmem]
	and AL, 0c7h
	or [preused], PRE32A
	test [preflags], PRE32A
	jz @F
	jmp dop18		;; if 32-bit addressing
@@:
	or [disflags], DIS_I_SHOW	;; we'd like to show this address
	mov [addrr], 0		;; zero out the address initially
	cmp AL, 6
	xchg AX, BX		;; mov BX, AX
	mov AL, '['
	stosb
	je dop16		;; if [xxxx]
	and BX, 7
	mov BL, [rmtab+BX]
	test BL, 8
	jnz dop09		;; if BX
	test BL, 4
	jz dop11		;; if not BP
	mov AX, 'PB'		;; "BP"
	mov CX, [regs.rBP]
	test [preflags], PRESEG
	jnz dop10		;; if segment override
	dec [segmnt]		;; default is now SS
	jmp dop10
dop09:
	mov AX, 'XB'		;; "BX"
	mov CX, [regs.rBX]

dop10:
	mov [addrr], CX		;; print it out, etc.
	stosw
	test BL, 2+1
	jz dop13		;; if done
	mov AL, '+'
	stosb
dop11:
	mov AX, 'IS'		;; "SI"
	mov CX, [regs.rSI]
	test BL, 1
	jz @F			;; if SI
	mov AL, 'D'		;; "DI"
	mov CX, [regs.rDI]
@@:
	add [addrr], CX		;; base+index ([BX+SI, ....)
	stosw
dop13:
	test [ai.regmem], 0c0h
	jz dop17		;; if no displacement
	test [ai.regmem], 80h
	jnz dop15		;; if word displacement
	call disgetbyte
	cbw
	add [addrr], AX		;; [base][+index]+byte
	cmp AL, 0
	mov AH, '+'
	jge @F			;; if >= 0
	mov AH, '-'
	neg AL
@@:
	mov [DI], AH
	inc DI
	call hexbyte		;; print the byte displacement
	jmp dop17		;; done
dop15:
	mov AL, '+'
	stosb
dop16:				;; <--- pure 16bit offset
	call disgetword
	add [addrr], AX
	call hexword		;; print word displacement
dop17:
	mov AL, ']'
	stosb
	ret

;; --- 32-bit MOD REG R/M addressing.
dop18:
	cmp AL, 5
	jne @F			;; if not just a disp32 address
	mov AL, '['
	stosb
	call disp32		;; get & display 32bit offset
	jmp dop27

@@:
	push AX
	and AL, 7
	cmp AL, 4
	jne @F			;; if no SIB
	call disgetbyte	;; get and save it
	mov [ai.sibbyte], AL
@@:
	pop AX
	test AL, 80h
	jnz dop22		;; if disp32
	test AL, 40h
	jz dop23		;; if no disp8
	call disgetbyte
	cmp AL, 0
	jge @F			;; if >= 0
	neg AL
	mov byte ptr [DI], '-'
	inc DI
@@:
	call hexbyte
	jmp dop23		;; done

;; --- the disassembler displays offsets first;
;; --- example: mov AX, 00001000[EBX][EDI]
dop22:
	call disp32		;; get and display 32bit offset

dop23:
	mov AL, [ai.regmem]
	and AL, 7
	cmp AL, 4
	jne showsqreg32		;; if no SIB
	mov AL, [ai.sibbyte]
if 1	;; bugfix: make 'u' correctly handle [ESP], [ESP+x]
	cmp AL, 24h
	jnz @F
	mov AL, 4
	jmp showsqreg32
@@:
endif
	and AL, 7
	cmp AL, 5
	jne @F			;; if not [EBP]
	test [ai.regmem], 0c0h
	jnz @F			;; if MOD != 0
	call disp32		;; get and show 32-bit displacement instead of [EBP]
	jmp dop25

@@:
	call showsqreg32	;; render "[E&reg]"; AL=reg
dop25:
	mov AL, [ai.sibbyte]
	shr AL, 1
	shr AL, 1
	shr AL, 1
	and AL, 7
	cmp AL, 4
	je disbad1		;; if illegal

	call showsqreg32	;; render "[E&reg]; AL=reg
	dec DI			;; remove "]"

	mov AH, [ai.sibbyte]
	test AH, 0c0h
	jz dop27		;; if SS = 0
	mov AL, '*'
	stosb
	mov AL, '2'
	test AH, 80h
	jz @F			;; if *2
	mov AL, '4'
	test AH, 40h
	jz @F			;; if *4
	mov AL, '8'
@@:
	stosb
dop27:
	mov AL, ']'
	stosb
	ret

;; --- Memory-only reference (_M?)
DOpMx:
	call getregmem
	cmp AL, 0c0h
	jae disbad1		;; if it's a register reference
	jmp dop05

disbad1:
	jmp disbad		;; this is not supposed to happen

;; --- Register reference from MOD R/M part (_X?)
DOpXx:
	call getregmem
	cmp AL, 0c0h
	jb disbad1		;; if it's a memory reference
	jmp dop_r1

;; --- Memory offset reference (_O?)
DOpAn:
	call showsize	;; print the size and save various things
	mov AL, 5
	test [preflags], PRE32A
	jnz @F			;; if 32-bit addressing
	inc AX
@@:
	mov [ai.regmem], AL
	jmp dop06		;; don't show size

;; --- Pure register reference (_R?)
DOpRx:
	call getregmem_r
dop_r1:				;; <--- used by _E?, _X?, _r?, _A?
	and AL, 7		;; entry point for regs from MOD R/M, and others
	mov CL, [disflags2]
	or [disflags], CL	;; if it was variable size operand, the size
				;; should now be marked as known.
	cmp AH, 0
	jl dop_reg		;; if byte register
	jz dop_wordreg		;; if word register
	cmp AH, 20h		;; qword register (mmx)?
	jz dop_regmmx
	mov byte ptr [DI], 'E'
	inc DI
dop_wordreg:
	add AL, 8		;; use the 16-bit names (RwName)
dop_reg:
	cbw
	shl AX, 1
	xchg AX, BX		;; mov BX, AX
	mov AX, [RvName+BX]	;; get the register name
	stosw
	ret
dop_regmmx:
	push AX
	mov AX, "MM"
	stosw
	pop AX
	add AL, '0'
	stosb
	ret

;; --- Register number embedded in the instruction (_r?)
DOprx:
	mov AL, [instru]
	jmp dop_r1

;; --- AL or AX or EAX (_A?)
DOpAx:
	mov AL, 0
	jmp dop_r1

;; --- qword mem (_Q).
;; --- this operand type is used by:
;; --- + cmpxchg8b
;; --- + fild, fistp
DOpQ:
;;	mov AX, 'Q'		;; print 'Q' +'WORD'
	mov AH, 20h		;; size qword
	jmp dop40

;; --- float (=real4) mem (_MF).
DOpMF:
	mov AX, 'LF'
	stosw
	mov AL, 'O'
	stosb
	mov AX, 'TA'
	jmp dop38c

;; --- double (=real8) mem (_MD).
DOpMD:
	mov AX, 'OD'
	stosw
	mov AX, 'BU'
	stosw
	mov AX, 'EL'
dop38c:
	stosw
	call showptr
	jmp dop42a

;; --- tbyte (=real10) mem (_MLD).
DOpMLD:
	mov AX, 0ff00h+'T'	;; print 't' + 'byte'
	stosb
dop40:
	call getregmem
	cmp AL, 0c0h
	jae disbad5		;; if it's a register reference
	and [disflags], not DIS_F_SHOW	;; don't show this
	jmp dop05

;; --- far memory (_Mf).
;; --- this is either a far16 (dword) or far32 (fword) pointer
DOpMf:
	call dischk32d
	jz @F			;; if not dword far
	call showdwd
	sub DI, 4		;; erase "ptr "
@@:
	mov AX, 'AF'		;; store "far "
	stosw
	mov AX, ' R'
	stosw

;; --- mem (_Mx).
DOpMxx:
	and [disflags], not DIS_F_SHOW	;; don't show this
dop42a:
	call getregmem
	cmp AL, 0c0h
	jae disbad5		;; if it's a register reference
	jmp dop06		;; don't show size

disbad5:
	jmp disbad

;; --- Check for ST(1) (_ST1).
DOpST1:
	pop AX		;; discard return address
	mov AL, [ai.regmem]
	and AL, 7
	cmp AL, 1
	je @F		;; if it's ST(1)
	jmp da14	;; another operand (but no comma)
@@:
	jmp da21	;; end of list

;; --- store segment register name (_Rs).
DOpRs:
	call getregmem_r
	cmp AL, 6
	jae disbad		;; if not a segment register
	cmp AL, 2
	je @F			;; if SS
	and [disflags], not DIS_F_REPT	;; clear flag: don't repeat
@@:
	cmp AL, 4
	jb @F			;; if not FS or GS
	mov [ai.dismach], 3	;; (no new 486-686 instructions involve seg regs)
@@:
	add AL, 8+8		;; segreg names are behind 8-bit/16-bit regnames
	jmp dop_reg		;; go print it out

;; --- Sign-extended immediate byte (_Ds). "push xx"
DOpDs:
	call showsizeop
	call disgetbyte
	cmp AL, 0
	xchg AX, BX		;; mov BL, AL
	mov AL, '+'
	jge @F			;; if >= 0
	neg BL
	mov AL, '-'
@@:
	stosb
	xchg AX, BX		;; mov AL, BL
	jmp dop59a		;; call hexbyte and return

;; --- Immediate byte (_Db).
DOpDb:
	call disgetbyte
dop59a:
	jmp hexbyte		;; call hexbyte and return

;; --- Set flag to always show size (_N).
DOpN:
	or [disflags], DIS_I_SHOWSIZ
	pop AX			;; discard return address
	jmp da14		;; next operand
disasm endp

disbad proc
if FLATSS
	.386
	mov ESP, [run_sp]	;; pop junk off stack
else
	mov SP, [run_sp]		;; pop junk off stack
endif
	mov AX, offset da13
	push AX
	mov [dis_n], 0
	mov word ptr [preflags], 0		;; clear preflags and preused
	mov [rmsize], 80h				;; don't display any memory
	mov word ptr [ai.dismach], 0		;; forget about the machine type
	and [disflags], not DIS_I_SHOW	;; and flags
	call disgetbyte
	mov DI, offset prefixlist
	mov CX, N_PREFIX
	repne scasb
	je @F			;; if it's a named prefix
	dec [dis_n]
	mov BX, MN_DB	;; offset of 'db' mnemonic
	mov SI, OPLIST_26+OPTYPES_BASE	;; this says _Db
	ret
@@:
	or [disflags], DIS_I_UNUSED	;; print special flag
	mov BX, N_PREFIX-1
	sub BX, CX
	shl BX, 1
	cmp BX, 6*2
	jb @F			;; if seg directive
	mov BX, [prefixmnem+BX-6*2]
	mov SI, OPTYPES_BASE	;; no operand
	ret
@@:
	lea SI, [BX+OPLIST_40+OPTYPES_BASE]	;; this is _ES
	mov BX, MN_SEG
	ret
disbad endp

;; --- relative jumps
DOpJx proc

;; --- 8-bit relative jump (_Jb)
DOpJb::
	call disgetbyte
	cbw
	jmp DOpJw

;; --- 16/32-bit relative jump (_Jv)
DOpJv::
	call disgetword
	call dischk32d
	jz DOpJw	;; if not 32-bit distance
	push AX
if ?PM
	test [bCSAttr], CS32ATTR	;; for 32bit code segments
	jnz @F			;; no need to display "DWORD "
endif
	call showdwd		;; "DWORD PTR "
	sub DI, 4		;; erase "PTR "
@@:
	pop DX
	call disgetword
	mov BX, [u_addr+0]
	add BX, [dis_n]
	add DX, BX
	adc AX, [u_addr+2]
	call hexword
	xchg AX, DX
	jmp hexword		;; call hexword and return

DOpJw:				;; 16-bit distance
if ?PM
	test [bCSAttr], CS32ATTR
	jnz @F
endif
	add AX, [u_addr]
	add AX, [dis_n]
	jmp hexword		;; call hexword and return
if ?PM
@@:
	.386
	cwde	;; =movsx EAX, AX
	add EAX, dword ptr [u_addr]
	add EAX, dword ptr [dis_n]
	jmp hexdword
	.8086
endif
DOpJx endp

;; --- Here are the routines for printing out the operands themselves.

;; --- CRx (_CRx), DRx (_DRx), TRx (_TRx), MMx (_MMx)
DOpCRx proc
	call getregmem_r
	mov BX, "RC"		;; "CRx"
	cmp AL, 4
	ja disbad4		;; if too large
	jne @F
	mov [ai.dismach], 5	;; CR4 is new to the 586
@@:
	cmp [idxins], SPARSE_BASE+22h
	jne dop55		;; if not mov CRx, xx
	cmp AL, 1
	jne dop55		;; if not CR1
disbad4:
	jmp disbad		;; can't mov CR1, xx

;; --- DRx (_DRx).
DOpDRx::
	call getregmem_r
	mov BX, "RD"		;; "DRx"
	mov CX, -1		;; no max or illegal value (remove?)
	jmp dop55

;; --- MMx (_MMx)
DOpMMx::
	call getregmem_r
	mov BX, "MM"		;; "MMx"
	jmp dop55

;; --- TRx (_TRx).
DOpTRx::
	call getregmem_r
	cmp AL, 3
	jb disbad4		;; if too small
	cmp AL, 6
	jae @F			;; if TR6-7
	mov [ai.dismach], 4	;; TR3-5 are new to the 486
@@:
	mov BX, "RT"		;; "TRx"
dop55:
	xchg AX, BX
	stosw			;; store XX
	xchg AX, BX
	or AL, '0'
	stosb
	ret
DOpCRx endp

;; --- ST(I) (_STi).
DOpSTi proc
	mov AL, [ai.regmem]
	and AL, 7
	xchg AX, BX		;; mov BX, AX
	mov AX, 'TS'
	stosw			;; store ST(BL)
	mov AL, '('
	stosb
	mov AX, ')0'
	or AL, BL
	stosw
	ret
DOpSTi endp

;; --- far immediate (_Af).
;; --- Either far16 or far32
DOpAf proc
	mov BX, SP
	call disgetword
	push AX
	call dischk32d
	jz @F			;; if not 32-bit address
	call disgetword
	push AX
@@:
	call disgetword	;; get segment part
	call hexword
	mov AL, ':'
	stosb
@@:
	pop AX
	call hexword
	cmp BX, SP
	jnz @B
	ret
DOpAf endp

;; --- Immediate data (_I?)
DOpIx proc
	cmp AH, 0
	jl dop03		;; if just a byte
	pushf
	test [disflags], DIS_I_SHOWSIZ
	jz @F			;; if we don't need to show the size
	call showsize	;; print size in AH
	sub DI, 4		;; erase "PTR "
@@:
	call disgetword
	popf
	jz @F			;; if just a word
	push AX
	call disgetword	;; print the high order word
	call hexword
	pop AX
@@:
	call hexword
	ret

dop03:
	call disgetbyte	;; print immediate byte
	call hexbyte
	ret
DOpIx endp

;; --- 32-bit addressing without SIB
;; --- store "[E&reg]" at DI
showsqreg32 proc
	cbw
	shl AX, 1
	xchg AX, BX
	mov AX, 'E['
	stosw
	mov AX, [RwName+BX]
	stosw
	mov AL, ']'
	stosb
	ret
showsqreg32 endp

showsizeop proc
;; --- for push imm8 add D/W to opcode if size differs from default (word/dword)
	cmp [instru], 6ah
	jnz sso_skip
	call dischk32d
if ?PM
	mov AH, [bCSAttr]
	.286
	shr AH, 2		;; 40h -> 10h (=PRE32D)
	.8086
else
	mov AH, 0
endif
	mov AL, 'W'
	test AH, PRE32D
	jnz @F
	mov AL, 'D'
@@:
	xor AH, [preflags]
	test AH, PRE32D
	jz sso_skip
	mov [DI-4], AL
sso_skip:
	ret
showsizeop endp

;; DISCHK32D - Check for 32 bit operand size prefix (66h).
dischk32d proc
	or [preused], PRE32D
	test [preflags], PRE32D
	ret
dischk32d endp

;; GETREGMEM_R - Get the reg part of the reg/mem part of the instruction
;;	Uses	CL
getregmem_r proc
	call getregmem
	mov CL, 3
	shr AL, CL
	and AL, 7
	ret
getregmem_r endp

;; GETREGMEM - Get the reg/mem part of the instruction
getregmem proc
	test [preused], GOTREGM
	jnz @F			;; if we have it already
	or [preused], GOTREGM
	call disgetbyte		;; get the byte
	mov [ai.regmem], AL	;; save it away
@@:
	mov AL, [ai.regmem]
	ret
getregmem endp

;; DISP32 - Print 32-bit displacement for addressing modes.
;;	Entry	None
;;	Exit	None
;;	Uses	AX
disp32 proc
	call disgetword
	push AX
	call disgetword
	call hexword
	pop AX
	call hexword
	ret
disp32 endp

;; SHOWSEG - Show the segment descriptor in SEGMNT
;;	Entry	DI	Where to put it
;;	Exit	DI	Updated
;;	Uses	AX, BX
showseg proc
	mov AL, [segmnt]	;; segment number
	cbw
	shl AX, 1
	xchg AX, BX		;; mov BX, AX
	mov AX, [RsName+BX]	;; get register name
	stosw
	ret
showseg endp

;; SHOWOP Show the op code
;;	Entry	SI	Null-terminated string containing the op mnemonic
;;	Exit	DI	Address of next available byte in output line (>= offset line_out + 32 due to padding)
;;	Uses	AL
showop proc
	mov DI, offset line_out+MNEMONOFS
@@:
	lodsb
	mov AH, AL
	and AL, 7fh
	stosb
	and AH, AH
	jns @B
	mov AL, ' '
@@:
	stosb
	cmp DI, offset line_out+MNEMONOFS+8
	jb @B
	ret
showop endp

;; SHOWSIZE - Print a description of the size
;;	Entry	AH	10h=dword, 00h=word, f0h=byte, 20h=qword
;;	Uses	AX
;; SHOWPTR - Print " PTR"
;;	Uses	AX
;; SHOWDWD - Print "DWORD PTR"
;;	Uses	AX
showsize proc
	mov [rmsize], AH	;; save r/m size
	mov [sizeloc], DI	;; save where we're putting this
	mov AL, 'Q'
	cmp AH, 20h
	jz showqwd
	cmp AH, 0
	jg showdwd	;; if dword
	je showwd	;; if word
	mov AX, 'YB'
	stosw
	mov AX, 'ET'
	jmp ssz3
showdwd::		;; <---
	mov AL, 'D'
showqwd:
	stosb
showwd:
	mov AX, 'OW'
	stosw
	mov AX, 'DR'
ssz3:
	stosw
showptr::		;; <---
	mov AX, 'P '
	stosw
	mov AX, 'RT'
	stosw
	mov AL, ' '
	stosb
	ret
showsize endp

;; DISGETBYTE - Get byte for disassembler.
;;	Entry	None
;;	Exit	AL	Next byte in instruction stream
;;	Uses	None
disgetbyte proc
	push DS
if ?PM
	test [bCSAttr], CS32ATTR
	jnz @F
endif
	push SI
	mov SI, [u_addr]
	add SI, [dis_n]			;; index to the right byte
	mov DS, [u_addr+4]
	lodsb				;; get the byte
	pop SI
	pop DS
	inc [dis_n]			;; indicate that we've gotten this byte
	ret
if ?PM
	.386
@@:
	push ESI
	lds ESI, fword ptr [u_addr]
	add ESI, dword ptr CS:[dis_n]	;; index to the right byte
	lodsb DS:[ESI]
	pop ESI
	pop DS
	inc [dis_n]
	ret
	.8086
endif
disgetbyte endp

;; DISGETWORD - Get word for disassembler.
;;	Entry	None
;;	Exit	AX	Next word
;;	Uses	None
disgetword proc
	push DS
if ?PM
	test [bCSAttr], CS32ATTR
	jnz @F
endif
	push SI
	mov SI, [u_addr]
	add SI, [dis_n]		;; index to the right byte
	mov DS, [u_addr+4]
	lodsw
	pop SI
	pop DS
	add [dis_n], 2
	ret
if ?PM
	.386
@@:
	push ESI
	lds ESI, fword ptr [u_addr]
	add ESI, dword ptr CS:[dis_n]	;; index to the right byte
	lodsw DS:[ESI]
	pop ESI
	pop DS
	add [dis_n], 2
	ret
	.8086
endif
disgetword endp

;; DISSHOWBYTES - Show bytes for the disassembler.
;;	Entry	BX	Number of bytes (must be > 0)
;;	Exit	u_addr	updated
;;	Uses	BX, SI.
disshowbytes proc
if ?PM
	test [bCSAttr], CS32ATTR
	jnz dissb_1
endif
	mov SI, [u_addr]
	mov DS, [u_addr+4]
@@:
	lodsb
	call hexbyte
	dec BX
	jnz @B
	@RestoreSeg DS
	mov [u_addr], SI
	ret
if ?PM
	.386
dissb_1:
	lds ESI, fword ptr [u_addr]
@@:
	lodsb DS:[ESI]
	call hexbyte
	dec BX
	jnz @B
	@RestoreSeg DS
	mov dword ptr [u_addr], ESI
	ret
	.8086
endif
disshowbytes endp

;; MOVEOVER - Move the line to the right - disassembler subfunction.
;;	Entry	DI	Last address + 1 of line so far
;;	Exit	CX	Number of bytes to move
;;		DI	Updated
;;	Uses	SI
moveover proc
	cmp [sizeloc], 0
	je @F		;; if sizeloc not saved
	add [sizeloc], CX
@@:
	mov SI, DI
	add DI, CX
	mov CX, DI
	sub CX, offset line_out+MNEMONOFS
	push DI
	std
	dec SI
	dec DI
	rep movsb
	pop DI
	cld
	ret
moveover endp

;; TAB_TO - Space fill until reaching the column indicated by AX.
;; (Print a new line if necessary.)
tab_to proc
	push AX
	sub AX, DI
	ja @F			;; if there's room on this line
	call trimputs
	mov DI, offset line_out
@@:
	pop CX
	sub CX, DI
	mov AL, ' '
	rep stosb		;; space fill to the right end
	ret
tab_to endp
