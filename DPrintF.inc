;; --- debug printf - all registers preserved, including flags

if CATCHINT41
;; --- .486 makes jwasm avoid leave generation - problem if stack is 32-bit and hiword(EBP) != 0.
;; --- That can happen for @dprintf inside intr41().
	.486
endif

handle_char proc
	cmp AL, 10
	jnz @F
	mov AL, 13
	call @F
	mov AL, 10
@@:
	push BX
	xor BX, BX
	mov AH, 0eh
if RING0
	call CS:[int10vec]
else
	int 10h
endif
	pop BX
	ret
handle_char endp

;; --- ltob(long n, char *s, int base);
;; --- convert long to string
;; --- EAX=number
;; --- BX=buffer - is expected to be onto stack
;; --- CX=base
;; ltob proc stdcall uses EDI number: dword, outb: word, base: word
ltob proc
	push EDI
	push EDX
	movzx EDI, CX
	mov CH, 0
	cmp DI, -10
	jne @F
	mov DI, 10
	and EAX, EAX
	jns @F
	neg EAX
	mov CH, '-'
@@:
	add BX, 10
	mov byte ptr SS:[BX], 0
	dec BX
@@nextdigit:
	xor EDX, EDX
	div EDI
	add DL, '0'
	cmp DL, '9'
	jbe @F
	add DL, 7+20h
@@:
	mov SS:[BX], DL
	dec BX
	and EAX, EAX
	jne @@nextdigit
	cmp CH, 0
	je @F
	mov SS:[BX], CH
	dec BX
@@:
	inc BX
	mov AX, BX
	pop EDX
	pop EDI
	ret
ltob endp

;; --- SS doesn't need to be dgroup
;; --- v2.1: SS may be 32-bit!
dprintf proc
d_sp	equ word ptr [BP+16+2]
d_ret	equ word ptr [BP+16+2+2]
d_fmt	equ word ptr [BP+16+2+2+2]
d_args	equ word ptr [BP+16+2+2+2+2]

if 0
local size_: word
local flag: byte
local longarg: byte
local fill: byte
local szTmp[12]: byte
else
d_size		equ <[BP-2]>
d_flag		equ <byte ptr [BP-3]>
d_longarg	equ <byte ptr [BP-4]>
d_fill		equ <byte ptr [BP-5]>
d_szTmp		equ <[BP-18]>
endif

	push SP
	pushf
	pusha
	mov BP, SP
	sub SP, 18
	push DS
	push CS
	pop DS
	lea DI, d_args
@@L335:
	mov SI, d_fmt
nextchar:
	lodsb [SI]
	or AL, AL
	je done
	cmp AL, '%'
	je formatitem
	call handle_char
	jmp nextchar
done:
	sub DI, 2
	mov AX, d_ret
	mov SS:[DI], AX
	mov d_sp, DI
	pop DS
	mov SP, BP
	popa
	popf
	pop SP
	ret

formatitem:
	push @@L335
	xor DX, DX
	mov d_longarg, DL
	mov BL, 1
	mov CL, ' '
	cmp byte ptr [SI], '-'
	jne @F
	dec BX
	inc SI
@@:
	mov d_flag, BL
	cmp byte ptr [SI], '0'
	jne @F
	mov CL, '0'
	inc SI
@@:
	mov d_fill, CL
	mov BX, DX

	.while byte ptr [SI] >= '0' && byte ptr [SI] <= '9'
		lodsb
		sub AL, '0'
		cbw
		imul CX, BX, 10		;; CX = BX*10
		add AX, CX
		mov BX, AX
	.endw

	mov d_size, BX
	cmp byte ptr [SI], 'l'
	jne @F
	mov d_longarg, 1
	inc SI
@@:
	lodsb
	mov d_fmt, SI
	cmp AL, 'x'
	je handle_x
	cmp AL, 'X'
	je handle_x
	cmp AL, 'c'
	je handle_c
	cmp AL, 'd'
	je handle_d
	cmp AL, 'i'
	je handle_i
	cmp AL, 's'
	je handle_s
	cmp AL, 'u'
	je handle_u
	cmp AL, 0
	jnz @@L359
	pop AX
	jmp done
handle_c:
	mov AX, SS:[DI]
	add DI, 2
@@L359:
	call handle_char
	retn

handle_x:
	mov CX, 16
	jmp @@lprt262
handle_d:
handle_i:
	mov CX, -10
	jmp @@lprt262
handle_u:
	mov CX, 10
@@lprt262:
	mov AX, SS:[DI]
	add DI, 2
	sub DX, DX
	cmp CX, 0		;; signed or unsigned?
	jge @F
	cwd
@@:
	cmp d_longarg, 0
	je @F
	mov DX, SS:[DI]
	add DI, 2
@@:
	lea BX, d_szTmp
	push DX
	push AX
	pop EAX
;;	invoke ltob, EAX, BX, CX
	call ltob
	mov SI, AX
	push DS
	push SS
	pop DS
	call output_string
	pop DS
	retn

handle_s:
	mov SI, SS:[DI]
	add DI, 2

output_string:	;; display string at DS:SI
	mov AX, SI
	mov BX, d_size
	.while byte ptr [SI]
		inc SI
	.endw
	sub SI, AX
	xchg AX, SI
	sub BX, AX
	.if d_flag == 1
		.while sword ptr BX > 0
			mov AL, d_fill
			call handle_char
			dec BX
		.endw
	.endif

	.while byte ptr [SI]
		lodsb
		call handle_char
	.endw

	.while sword ptr BX > 0
		mov AL, d_fill
		call handle_char
		dec BX
	.endw
	retn
dprintf endp
