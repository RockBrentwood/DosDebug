;; --- defines procedures
;; --- PowerOf10
;; --- FloatToBCD
;; --- FloatToStr

;; These are bits in the FP status word.

FP_LESSTHAN	equ 01h
FP_EQUALTO	equ 40h

MAXNUM equ 16

CONST segment
;; ten		dq 10.0
;; ten16	dq 1.0e16
;; rounder	dq 5.0e10
iExp = 1
ten_1	label tbyte
repeat 15
	dt @CatStr(1.0e, %iExp)
	iExp = iExp + 1
endm
ten_16	label tbyte
repeat 15
	dt @CatStr(1.0e, %iExp)
	iExp = iExp + 16
endm
;; Just the first exponent is necessary for 8-byte doubles
ten_256	label tbyte
repeat 19
	dt @CatStr(1.0e, %iExp)
	iExp = iExp + 256
endm
CONST ends

;; --- called by FloatToStr
;; --- in: AX=exponent
;; --- modifies: BX, CL
PowerOf10 proc uses SI
	push AX
	cmp AX, 0		;; .if (sword ptr AX < 0)
	jge @F
	neg AX
@@:
	fld1
	mov BL, AL
	and BL, 0fh		;; bits 0-3
	je @F
	mov SI, offset ten_1
	call mul10
@@:
	mov BL, AL
	mov CL, 4
	shr BL, CL		;; bits 4-7
;;	and BL, 0fh
	je @F
	mov SI, offset ten_16
	call mul10
@@:
	mov BL, AH
	and BL, 1fh		;; bits 8-12
	je @F
	mov SI, offset ten_256
	call mul10
@@:
	pop AX
	cmp AX, 0		;; .if (sword ptr AX < 0)
	jge @F
	fdivp ST(1), ST
	ret
@@:
	fmulp ST(1), ST
	ret
mul10:
	dec BL
	push AX
	mov AL, 10		;; sizeof TBYTE
	mul BL
	xchg BX, AX
	pop AX
	fld tbyte ptr [BX + SI]
	fmulp ST(1), ST
	retn
PowerOf10 endp

;; Convert a floating point register to ASCII.
;; For internal use.
;; The result always has exactly 18 digits, with zero padding on the left if required.
;; Entry:	ST(0) = a number to convert, 0 <= ST(0) < 1E19.
;;		DI = an 18-character buffer.
;; modifies SI, DI, CX, AX
FloatToBCD proc
if FLATSS
	sub ESP, 12
	mov ESI, ESP
else
	sub SP, 12
	mov SI, SP
endif

	;; The fbstp instruction converts the top of the stack to a packed BCD form in ten bytes,
	;; with two digits per byte.
	;; The top byte has the sign, which we ignore.

if FLATSS
	fbstp [ESP]
else
	fbstp [SI]
endif

	;; Now we need to unpack the BCD to ASCII.

if FLATSS
	add ESI, 8
else
	add SI, 8
endif
	mov CX, 9
@@:
if FLATSS
	mov AL, SS:[ESI]	;; xxxx xxxx AAAA BBBB
	dec ESI
else
	mov AL, [SI]		;; xxxx xxxx AAAA BBBB
	dec SI
endif
if 0
	rol AX, 12		;; BBBB xxxx xxxx AAAA
	rol AH, 4		;; xxxx BBBB xxxx AAAA
	and AX, 0f0fh		;; 0000 BBBB 0000 AAAA
else
	db 0D4h, 10h		;; aam 16: 0000 AAAA 0000 BBBB
	xchg AL, AH		;; 0000 BBBB 0000 AAAA
endif
	add AX, 3030h
	stosw
	loop @B
if FLATSS
	add ESP, 12
else
	add SP, 12
endif
	ret
FloatToBCD endp

;; Convert a double precision number to a string.
;; Entry:	SI=fpin = 10-byte double to convert
;;		DI=pszDbl = buffer to hold converted double
;; Exit:	DI = behind converted double
FloatToStr proc uses SI
if FLATSS
_DATA segment
IExp dw 0
;; mystat dw 0
;; fpin dt dup (0)
;; szTemp db 22 dup (0)
_DATA ends
else
local IExp: word
local mystat: word
;; local fpin: tbyte
;; local szTemp[22]: byte
endif

;; --- Special case zero has been filtered already (fxtract fails for zero).
;;	mov SI, [pfpin]
;;	lea DI, [fpin]
;;	mov CX, 5
;;	rep movsw
;;	mov DI, [pszDbl]

;; --- Check for a negative number.

	mov CL, [SI+9]
	test CL, 80h
	jz @F
	and byte ptr [SI+9], 07fh		;; change to positive
	mov AL, '-'				;; store a minus sign
	stosb
@@:

;; --- load our value onto the stack.

	fld tbyte ptr [SI]
	fld ST
	mov [SI+9], CL	;; restore fpin, must be preserved.

;; Compute the closest power of 10 below the number.
;; We can't get an exact value because of rounding.
;; We could get close by adding in log10(mantissa), but it still wouldn't be exact.
;; Since we'll have to check the result anyway, it's silly to waste cycles worrying about the mantissa.
;;
;; The exponent is basically log2(fpin).
;; Those of you who remember algebra realize that log2(fpin) x log10(2) = log10(fpin), which is what we want.

	fxtract			;; ST=> mantissa, exponent, fpin
	fstp ST			;; drop the mantissa
	fldlg2			;; push log10(2)
	fmulp ST(1), ST		;; ST = log10(fpin), fpin
	fistp IExp		;; ST = fpin

;; --- A 10-byte double can carry almost 19 digits, but fbstp only stores the guaranteed 18.
;; --- If you're doing 10-byte doubles, change the '16' to '18'.

	cmp IExp, 18
	jnc notbelow18

	fld ST			;; ST = fpin, fpin
	frndint			;; ST = int(fpin), fpin
	fcomp ST(1)		;; ST = fpin, status set
if RING0
	fstsw AX
else
	fstsw mystat
	mov AX, mystat
endif
	test AH, FP_EQUALTO
	jz notequal

;; --- We have an integer!
;; --- Lucky day.
;; --- Go convert it into a temp buffer.

	push DI
;;	lea DI, szTemp
	call FloatToBCD
	pop DI

	mov AX, MAXNUM+1
	mov CX, IExp
	sub AX, CX
	inc CX
;;	lea SI, szTemp
	mov SI, DI
	add SI, AX

;; --- The off-by-one order of magnitude problem below can hit us here.
;; --- We just trim off the possible leading zero.

	cmp byte ptr [SI], '0'
	jnz @F
	inc SI
	dec CX
@@:

;; --- Copy the rest of the converted BCD value to our buffer.

	rep movsb
	jmp ftsExit

notequal:
notbelow18:

;; --- Have fbstp round to 17 places.

	mov AX, MAXNUM
	sub AX, IExp		;; adjust exponent to 17
	call PowerOf10

;; Either we have exactly 17 digits, or we have exactly 16 digits.
;; We can detect that condition and adjust now.

	fcom qword ptr [ten_16]
	;; x0xxxx00 means top of stack > ten16
	;; x0xxxx01 means top of stack < ten16
	;; x1xxxx00 means top of stack = ten16
if RING0
	fstsw AX
else
	fstsw mystat
	mov AX, mystat
endif
	test AH, 1
	jz @F
	fmul qword ptr [ten_1]
	dec IExp
@@:

;; --- Go convert to BCD.

	push DI
	lea  DI, [DI+8]
	call FloatToBCD
	pop DI

;;	lea SI, [szTemp+1]		;; point to converted buffer
	lea SI, [DI+8+1]		;; point to converted buffer

;; --- If the exponent is between -15 and 16, we should express this as a number without scientific notation.

	mov CX, [IExp]
	push CX
	add CX, MAXNUM-1
	cmp CX, MAXNUM*2-1
	pop CX
	ja fts6		;; if scientific notation

;; If the exponent is less than zero, we insert '0.', then -ECX leading zeros, then 16 digits of mantissa.
;; If the exponent is positive, we copy ECX+1 digits, then a decimal point (maybe), then the remaining 16-ECX digits.

	inc CX
	cmp CX, 0
	jg @F
	mov AX, '.0'
	stosw
	neg CX
	mov AL, '0'
	rep stosb
	mov CX, MAXNUM
	jmp fts3
@@:
	rep movsb
	mov AL, '.'
	stosb
	mov CX, MAXNUM
	sub CX, [IExp]
fts3:
	rep movsb

;; --- Trim off trailing zeros.

@@:
	cmp byte ptr [DI-1], '0'
	jnz @F
	dec DI
	jmp @B
@@:

;; --- If we cleared out all the decimal digits, kill the decimal point, too.

	cmp byte ptr [DI-1], '.'
	jnz @F
	dec DI
@@:

;; --- That's it.

	jmp ftsExit
fts6:
;; Now convert this to a standard, usable format.
;; If needed, a minus sign is already present in the outgoing buffer, and DI already points past it.

	movsb				;; copy the first digit
	mov AL, '.'
	stosb				;; plop in a decimal point
	movsw				;; copy four more digits
	movsw
	movsw				;; copy two more digits

if 0

;; The printf %g specified trims off trailing zeros here.
;; I dislike this, so I've disabled it.
;; Comment out the if 0 and endif if you want this.

@@:
	cmp byte ptr [DI-1], '0'
	jz @F
	dec DI
	jmp @B
@@:
endif

;; --- Shove in the exponent.
;; --- If you support 10-byte reals, remember to allow 4 digits for the exponent.

	mov AX, '+e'
	mov DX, [IExp]
	and DX, DX
	jns @F
	neg DX
	mov AH, '-'
@@:
	stosw

	xchg AX, DX
	mov SI, 10
	mov CX, 4
@@:
	xor DX, DX
	div SI
	push DX
	loop @B
	mov CL, 4
@@:
	pop AX
	add AL, '0'
	stosb
	loop @B

;;	add DI, 4	;; point to terminator

ftsExit:
	ret
FloatToStr endp
