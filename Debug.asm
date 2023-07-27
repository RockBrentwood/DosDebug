;; Debug.asm masm/jwasm assembler source for a clone of Debug.com.
;; To assemble, use:
;;	jwasm -bin -Fo Debug.com Debug.asm
;; To create DebugX, the DPMI aware version of Debug, use:
;;	jwasm -D_PM=1 -bin -Fo DebugX.com Debug.asm
;;
;; ============================================================================
;;
;; Copyright (c) 1995-2003 Paul Vojta
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to
;; deal in the Software without restriction, including without limitation the
;; rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
;; sell copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
;; PAUL VOJTA BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
;; IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;;
;; ============================================================================
;;
;; Japheth:	all extensions made by me are Public Domain.
;;		This does not affect other copyrights.
;;		This file is now best viewed with TAB size 8.
;; ============================================================================
;; Revision history:
;;	0.95e	2003-01-11	Fixed a bug in the assember.
;;	0.95f	2003-09-10	Converted to NASM; fixed some syntax incompatibilities.
;;	0.98	2003-10-27	Added EMS commands and copyright conditions.
;;
;;	The changes which were done by me, japheth, are described in doc/History.txt.
;;
;; ToDo:
;; ―	allow one to modify floating point registers,
;; ―	better syntax checks for A (so i.e. "mov AX, AL" is rejected),
;; ―	add MMX instructions for A and U,
;; ―	support loading *.HEX files.

VERSION	textequ <2.1>

	option casemap:none
	option proc:private
;;	option noljmp	;; enable to see the short jump extensions

BS		equ 8
TAB		equ 9
LF		equ 10
CR		equ 13
TOLOWER		equ 20h
TOUPPER		equ 0dfh
TOUPPER_W	equ (TOUPPER shl 8) or TOUPPER
MNEMONOFS	equ 28	;; offset in output line where mnemonics start (disassember)
STACKSIZ	equ 200h	;; debug's stack size
MCLOPT		equ 1	;; 1=accept /m cmdline opt (disable IRQ checks for int 08-0f)
LINE_IN_LEN	equ 257	;; length of line_in (including header stuff)

ifndef DRIVER
DRIVER		equ 0	;; 1=create a device driver (for CONFIG.SYS) variant
endif
ifndef BOOTDBG
BOOTDBG		equ 0	;; 1=create a bootstrap binary
endif
ifndef RING0
RING0		equ 0	;; 1=create a ring0 debugger variant
endif
ifndef _PM
_PM		equ 0	;; 1=create a DPMI-aware variant (DebugX)
endif
ifndef LMODE
LMODE		equ 0	;; 1=long mode version if RING0==1
endif

DGCMD		= 0	;; support DG cmd
DICMD		= 0	;; support DI cmd
DLCMD		= 0	;; support DL cmd
DMCMD		= 1	;; support DM cmd
DPCMD		= 0	;; support DP cmd
DTCMD		= 0	;; support DT cmd
DXCMD		= 0	;; support DX cmd
QCMD		= 1	;; support Q cmd
LCMD		= 1	;; support L cmd
WCMD		= 1	;; support W cmd
XCMDS		= 1	;; support Xx cmds
LCMDFILE	= 1	;; support L cmd for files and N cmd
WCMDFILE	= 1	;; support W cmd for files and N cmd
USESDA		= 1	;; use SDA to get/set PSP in real-mode
INT22		= 1	;; handle int 22h (DOS program termination)
INT2324		= 1	;; switch int 23h & 24h for debugger/debuggee
USEFP2STR	= 0	;; 1=use FloatToStr()
FLATSS		= 0	;; always 0 (1 is for a flat stack if RING0==1)

if LMODE
CS32ATTR	equ 40h or 20h	;; check both default size and 64-bit mode
else
CS32ATTR	equ 40h	;; check just the default size in legacy
endif

@VecAttr textequ <>

if RING0
 if LMODE
DBGNAME		equ <"DEBUG64">
DBGNAME2	equ <"Debug64">
@VecAttr	textequ <lowword>
;; --- long mode needs a flat 32-bit stack inside debug!
;; --- that's because otherwise an exception inside the PL0 debugger
;; --- would switch to 64-bit code with a 16-bit "flat" stack pointer.
FLATSS		= 1	;; 1=32-bit flat stack
 else
DBGNAME		equ <"DEB386">
DBGNAME2	equ <"Deb386">
 endif

?PM		equ 1
VDD		equ 0
NOEXTENDER	equ 0
DISPPL0STK	equ 0	;; 1=display ring 0 stack in register dump
CHKIOPL		equ 1	;; 1=don't stop if GPF cause of IOPL==0 and iosensitive instr
DGCMD		= 1
DICMD		= 1
DLCMD		= 1
DMCMD		= 0
DTCMD		= 1
VXCMD		= 1
elseif _PM
DBGNAME		equ <"DEBUGX">
DBGNAME2	equ <"DebugX">
?PM		equ 1
VDD		equ 1	;; 1=try to load debxxvdd.dll
NOEXTENDER	equ 1	;; 1=don't assume DPMI host includes a DOS extender
WIN9XSUPP	equ 1	;; 1=avoid to hook DPMI entry when running in Win9x
DOSEMU		equ 1	;; 1=avoid to hook DPMI entry when running in DosEmu
DISPHOOK	equ 1	;; 1=display "DPMI entry hooked..."
 ifndef CATCHEXC06
CATCHEXC06	equ 0	;; 1=catch exception 06h in protected-mode
 endif
 ifndef CATCHEXC07
CATCHEXC07	equ 0	;; 1=catch exception 07h in protected-mode
 endif
CATCHEXC0C	equ 1	;; 1=catch exception 0ch in protected-mode
CATCHINT21	equ 1	;; 1=hook into protected-mode int 21h
 ifndef CATCHINT31
CATCHINT31	equ 0	;; 1=hook DPMI int 31h
 endif
CATCHINT41	equ 1	;; 1=hook into protected-mode debug interface
MMXSUPP		equ 1	;; 1=support MMX specific commands
;; DPMIMSW	equ 0	;; 1=use int 2f, AX=1686h to detect mode, 0=use value of CS
DICMD		= 1
DLCMD		= 1
DXCMD		= 1
USEFP2STR	= 1
else
DBGNAME		equ <"DEBUG">
DBGNAME2	equ <"Debug">
?PM		equ 0
VDD		equ 0
NOEXTENDER	equ 0
endif

if DRIVER
CATCHINT06	= 1
QCMD		= 0
LCMDFILE	= 0
WCMDFILE	= 0
INT22		= 0
INT2324		= 0
elseif RING0
CATCHINT06	= 1
CATCHINT0C	= 0
CATCHINT0D	= 1
CATCHINT41	= 0
LCMD		= 0
QCMD		= 0
WCMD		= 0
XCMDS		= 0
LCMDFILE	= 0
WCMDFILE	= 0
USESDA		= 0
INT22		= 0
INT2324		= 0
elseif BOOTDBG
CATCHINT06	= 1
DICMD		= 1
DMCMD		= 0
DPCMD		= 1
DXCMD		= 1
QCMD		= 0
WCMD		= 0
XCMDS		= 0
LCMDFILE	= 0
WCMDFILE	= 0
USESDA		= 0
INT22		= 0
INT2324		= 0
endif

ifndef USEUNREAL
USEUNREAL	equ 0	;; 1=use "unreal" mode for DX cmd (won't work in v86)
endif
ifndef MMXSUPP
MMXSUPP		equ 0
endif
ifndef VXCHG
VXCHG		equ 0	;; 1=support video swap so outputs remain separated
endif
ifndef ALTVID
ALTVID		equ 0	;; 1=support alternate video adapter
endif
ifndef DICMD
DICMD		= 0
endif
ifndef DXCMD
DXCMD		= 0
endif
ifndef VXCMD
VXCMD		= 0
endif

if (DRIVER or BOOTDBG or RING0)
REDIRECT	equ 0
else
REDIRECT	equ 1	;; stdin/stdout redirection
endif

SYSRQINT	equ 9	;; if CATCHSYSREQ==1, defines the method (int 09h or int 15h)

ifndef CATCHINT01
CATCHINT01	equ 1	;; catch int 01 (single-step)
endif
ifndef CATCHINT03
CATCHINT03	equ 1	;; catch int 03 (break)
endif
ifndef CATCHINT06
CATCHINT06	equ 0	;; catch exception 06h
endif
ifndef CATCHINT07
CATCHINT07	equ 0	;; catch exception 07h
endif
ifndef CATCHINT0C
CATCHINT0C	equ 0	;; catch exception 0ch
endif
ifndef CATCHINT0D
CATCHINT0D	equ 0	;; catch exception 0dh
endif
ifndef CATCHSYSREQ
CATCHSYSREQ	equ 0	;; catch int 09h/15h (sysreq)
endif
ifndef CATCHINT41
CATCHINT41	equ 0	;; hook int 41h
endif

ife _PM
CATCHEXC06	equ 0
CATCHEXC07	equ 0
CATCHEXC0C	equ 0
endif

if ?PM or CATCHINT07
EXCCSIP		equ 1	;; display CS:IP where exception occured
EXCCSEIP	equ 0	;; may be activated if unknown exceptions occur in debugger
else
EXCCSIP		equ 0
endif

;; --- PSP offsets
if LCMDFILE or WCMDFILE
ALASAP		equ 02h	;; Address of Last segment allocated to program
DTA		equ 80h	;; Program arguments; also used to store file name (N cmd)
endif
if INT22
TPIV		equ 0ah	;; Terminate Program Interrupt Vector (int 22h)
PARENT		equ 16h	;; segment of parent PSP
endif
if INT2324
CCIV		equ 0eh	;; Control C Interrupt Vector (int 23h)
CEIV		equ 12h	;; Critical Error Interrupt Vector (int 24h)
endif
ife (DRIVER or BOOTDBG or RING0)
SPSAV		equ 2eh	;; Saved SS:SP in last DOS call
endif

;; --- attributes returned by int 21h, AX=4400h
AT_DEVICE	equ 80h	;; is device (not file)

ifdef _DEBUG
@dprintf macro text:req, a1, a2, a3, a4, a5, a6, a7, a8
local sym
CONST segment
sym db text, 10, 0
CONST ends
	pushcontext cpu
	.386
	for x, <a8, a7, a6, a5, a4, a3, a2, a1>
		ifnb <x>
			push x
		endif
	endm
	push offset sym
	call dprintf
	popcontext cpu
endm
else
@dprintf textequ <;>
endif

;; --- restore segment register (DS/ES) to DGROUP
@RestoreSeg macro segm
if FLATSS
	mov segm, CS:[pspdbg]
else
	push SS
	pop segm
endif
endm

;; --- mne macro, used for the assembler mnemonics table
mne macro val2:REQ, dbytes:VARARG
ASMDATA segment
CURROFS = $
	ifnb <dbytes>
		db dbytes
	endif
ASMDATA ends
	dw CURROFS - asmtab
MN_&val2 equ $ - mnlist
tmpstr catstr <!">, @SubStr(val2, 1, @SizeStr(val2)-1), <!", !'>, @SubStr(val2, @SizeStr(val2)), <!'>, <+80h>
	db tmpstr
endm

AGRP macro num, rfld
	exitm <240h + num*8 + rfld>
endm

variant macro opcode:req, key:req, lockb, machine
ASMDATA segment
	ifnb <lockb>
		db lockb
	endif
	ifnb <machine>
		db machine
	endif
ainfo = (opcode)*ASMMOD + key
	db HIGH ainfo, LOW ainfo
ASMDATA ends
endm

fpvariant macro opcode, key, addb, lockb, machine
	variant opcode, key, lockb, machine
ASMDATA segment
	db addb
ASMDATA ends
endm

endvariant macro
ASMDATA segment
	db -1
ASMDATA ends
endm

;; --- opl macro, used to define operand types
opidx = 0
opl macro value:VARARG
	.radix 16t
if opidx lt 10h
_line textequ <OPLIST_0>, %opidx, < equ $ - oplists>
else
_line textequ <OPLIST_>, %opidx, < equ $ - oplists>
endif
_line
	ifnb <value>
		db value
	endif
	db 0
	opidx = opidx + 1
	.radix 10t
endm

OT macro num
	exitm <OPLIST_&num+OPTYPES_BASE>
endm

;; --- sizeprf is to make Debug's support for 32bit code as small as possible.
;; --- for this to achieve a patch table is created in _IDATA which is filled by memory offsets
;; --- where prefix bytes 66h or 67h are found.
sizeprf macro
ife RING0
CurEIP = $
_IDATA segment
	dw CurEIP
_IDATA ends
endif
	db 66h
endm

sizeprfX macro
if ?PM
	sizeprf
endif
endm

if VDD
;; --- standard BOPs for communication with debxxvdd on NT platforms
RegisterModule macro
	db 0c4h, 0c4h, 58h, 0
endm
UnRegisterModule macro
	db 0c4h, 0c4h, 58h, 1
endm
DispatchCall macro
	db 0c4h, 0c4h, 58h, 2
endm
endif

	.8086

;; --- Define segments.
;; --- Usually, the debugger runs in the tiny memory model,
;; --- that is, all segments are grouped into "physical segment" DGROUP, and CS=SS=DS=ES=DGROUP (exception: RING0=1 && FLATSS=1).
;; --- When other memory regions are to be accessed, preferably ES is temporary used then, in a few cases (m/c cmds) also DS.
_TEXT segment dword public 'CODE'
_TEXT ends

if RING0
 if LMODE
	.x64
_TEXT64 segment use64 para public 'CODE'	;; alignment para is needed for correct offsets
_TEXT64 ends
	.8086
 endif
endif

CONST segment readonly word public 'DATA'
CONST ends

ASMDATA segment word public 'DATA'
asmtab label byte
ASMDATA ends

_DATA segment dword public 'DATA'
_DATA ends

if RING0
_ITEXT segment dword public 'I_CODE'
else
_ITEXT segment word public 'I_CODE'
endif
_ITEXT ends

_IDATA segment word public 'I_DATA'
patches label word
_IDATA ends

DGROUP group _TEXT, CONST, ASMDATA, _DATA, _ITEXT, _IDATA
if DRIVER
STACK segment para stack 'STACK'
	db STACKSIZ dup (?)
STACK ends
DGROUP group STACK
endif

	assume DS:DGROUP

_TEXT segment
if DRIVER
	dd -1
	dw 08000h		;; driver flags : character dev
Strat	dw offset strategy	;; offset to strategy routine
Intrp	dw offset driver_entry	;; offset to interrupt handler
device_name db 'DEBUG$RR'	;; device driver name

req_hdr struct
req_size	db ?		;; +0 number of bytes stored
unit_id		db ?		;; +1 unit ID code
cmd		db ?		;; +2 command code
status		dw ?		;; +3 status word
rsvd		db 8 dup(?)	;; +5 reserved
req_hdr ends

request_ptr dd 0

strategy:
	mov word ptr CS:[request_ptr+0], BX
	mov word ptr CS:[request_ptr+2], ES
	retf
interrupt:
	push DS
	push DI
	lds DI, CS:[request_ptr]	;; load address of request header
	mov [DI].req_hdr.status, 8103h
	pop DI
	pop DS
	ret
else

 ife (RING0 or BOOTDBG)
	org 100h
 endif
start:
	jmp initcode
 if RING0
	jmp getr0stk	;; get ring 0 SS:ESP
	org start+6		;; entercmd must be start+2*3
	jmp entercmd	;; enter command loop
 endif

endif
_TEXT ends

CONST segment
;; --- cmds b, j, k, v, y and z don't exist yet

cmdlist label word
	dw a_cmd, cmd_error, c_cmd, d_cmd
	dw e_cmd, f_cmd, g_cmd, h_cmd
	dw i_cmd, cmd_error, cmd_error
ife RING0
	dw l_cmd
else
	dw cmd_error
endif
	dw m_cmd
if LCMDFILE or WCMDFILE
	dw n_cmd
else
	dw cmd_error
endif
	dw o_cmd, p_cmd
if QCMD
	dw q_cmd
else
	dw cmd_error
endif
	dw r_cmd, s_cmd, t_cmd
	dw u_cmd
if VXCHG
	dw v_cmd
elseif VXCMD
	dw v_cmd
else
	dw cmd_error
endif
if WCMD
	dw w_cmd
else
	dw cmd_error
endif
if XCMDS
	dw x_cmd
else
	dw cmd_error
endif
ENDCMD	equ <'x'>
if _PM
dbg2324	dw i23pm, i24pm
endif
CONST ends

_DATA segment
if FLATSS
top_sp	dd 0		;; debugger's SP top (also end of debug's MCB)
run_sp	dd 0		;; debugger's SP when run() is executed (also used temp. by disasm)
else
top_sp	dw 0		;; debugger's SP top (also end of debug's MCB)
run_sp	dw 0		;; debugger's SP when run() is executed
endif
errret	dw 0		;; return here if error
ife (BOOTDBG or RING0)
spadjust dw 40h		;; adjust SP by this amount for save
pspdbe	dw 0		;; debuggee's program segment prefix
endif
pspdbg	dw 0		;; debugger's PSP (or DGROUP if no PSP available) - not translated if ?PM
if INT2324
run2324	dw 0, 0, 0, 0	;; debuggee's interrupt vectors 23 and 24 (both modes)
 if _PM
	dw 0, 0		;; in DPMI32, vectors are FWORDs
 endif
endif
if RING0
wFlat	dw 0
endif
if VDD
hVdd	dw -1		;; handle of NT helper VDD
endif

if INT2324
sav2324		dw 0, 0, 0, 0	;; debugger's interrupt vectors 23 and 24 (real-mode only)
endif
if INT22
psp22		dw 0, 0		;; original terminate address in debugger's PSP
parent		dw 0		;; original parent PSP in debugger's PSP (must be next)
endif
if DMCMD
wMCB		dw 0		;; start of MCB chain (always segment)
endif
ife (BOOTDBG or RING0)
pInDOS		dd 0		;; far16 address of InDOS flag (real mode)
endif
if _PM
InDosSel	dw 0		;; selector value for pInDOS in protected-mode
endif
if VXCHG
 ifndef VXCHGFLIP
XMSM struct
size_	dd ?
srchdl	dw ?
srcadr	dd ?
dsthdl	dw ?
dstadr	dd ?
XMSM ends
xmsdrv	dd 0		;; XMM driver address, obtained thru int 2f, AX=4310h
xmsmove XMSM <>		;; XMS block move struct, used to save/restore screens
csrpos	dw 0		;; cursor position of currently inactive screen
vrows	db 0		;; current rows; to see if debuggee changed video mode
 endif
endif
if ALTVID		;; exchange some video BIOS data fields for option /2.
oldcsrpos	dw 0	;; cursor position
oldcrtp		dw 0	;; CRTC port
oldcols		dw 80	;; columns
oldmr label word
oldmode		db 0	;; video mode
oldrows		db 24	;; rows - 1
endif
if USESDA
pSDA	dd 0		;; far16 address of DOS swappable data area (real-mode)
 if _PM
SDASel	dw 0		;; selector value for pSDA in protected-mode
 endif
endif
if INT2324
hakstat	db 0		;; whether we have hacked vectors 23/24 or not
endif
machine	db 0		;; cpu (0=8086, 1, 2, 3=80386, ...)

RM_386REGS	equ 1	;; bit 0: 1=386 register display
if RING0
rmode	db RM_386REGS
else
rmode	db 0		;; flags for R command
endif
tmode	db 0		;; bit 0: 1=ms-debug compatible trace mode

has_87	db 0		;; if there is a math coprocessor present
mach_87	db 0		;; coprocessor (0=8087, 1, 2, 3=80387, ...)
if MMXSUPP
has_mmx	db 0
endif
bInDbg	db 0		;; 1=debugger is running
if MCLOPT and (CATCHINT0C or CATCHINT0D)
bMPicB	db 8		;; master PIC base
endif
if REDIRECT
fStdin	db AT_DEVICE	;; flags stdin
fStdout	db AT_DEVICE	;; flags stdout
endif
swchar	db '-'		;; switch character
vpage	db 0		;; video page the debugger is to use for BIOS output
swch1	db ' '		;; switch character if it's a slash
promptlen dw 0		;; length of prompt
if REDIRECT
bufnext	dw line_in+2	;; if stdin=file: address of next available character
bufend	dw line_in+2	;; if stdin=file: address + 1 of last valid character
endif

a_addr	dw 0, 0, 0	;; address for next A command
d_addr	dw 0, 0, 0	;; address for last D command; must follow a_addr
u_addr	dw 0, 0, 0	;; address for last U command; must follow d_addr

if DXCMD
x_addr	dd 0		;; (phys) address for last DX command
endif
eqladdr	dw 0, 0, 0	;; optional '=' argument in G, P and T command
;; run_cs	dw 0		;; save original CS when running in G
lastcmd	dw dmycmd
run_intw label word
run_int	db 0, 0		;; interrupt type that stopped the running
eqflag	db 0		;; flag indicating presence of '=' argument
bInit	db 0		;; 0=ensure a valid opcode is at debuggee's CS:IP
if ?PM
scratchsel dw 0		;; scratch selector (used by cmds a, c, e, f, g, m, p, t)
bCSAttr db 0		;; current code attribute (D bit).
bAddr32 db 0		;; Address attribute. if 1, hiword(EDX) is valid
bFlagsPM db 0		;; bit 0: 0=no default set for A cmd
 if RING0
;; --- exceptions trapped (modified by VC/VT)
wTrappedExc dw (1 shl 0) or (1 shl 1) or (1 shl 3) or (CATCHINT06 shl 6) (CATCHINT07 shl 7) or \
		(CATCHINT0C shl 12) or (CATCHINT0D shl 13) or (1 shl 14)
  if FLATSS
bChar	db 0
  endif
 endif
endif
if LCMDFILE or WCMDFILE
fileext	db 0		;; file extension (0 if no file name)

EXT_OTHER	equ 1
EXT_COM		equ 2
EXT_EXE		equ 4
EXT_HEX		equ 8
endif

ife RING0

;; --- usepacket:
;; --- 0: packet is not used (int 25h/26h, CX!=ffff)
;; --- 1: packet is used (int 25h/26h, CX==ffff)
;; --- 2: packet is used (int 21h, AX=7305h, CX==ffff)
usepacket db 0

PACKET struc
secno	dd ?	;; sector number
numsecs	dw ?	;; number of sectors to read
dstofs	dw ?	;; ofs transfer address
dstseg	dw ?	;; seg transfer address
PACKET ends

 if ?PM
PACKET32 struc	;; this is for DPMI32 only
secno	dd ?
numsecs	dw ?
dstofs	dd ?
dstseg	dw ?
PACKET32 ends
 endif

	align 2

packet PACKET <0, 0, 0, 0>
 if ?PM
	dw 0	;; reserve space for the additional 2 bytes of PACKET32
 endif

endif

if RING0	;; vectors in intsave are either real-mode or - if RING0 == 1 - protected-mode
INTVEC textequ <fword>
else
INTVEC textequ <dword>
endif

;; --- order in intsave must match order in inttab

intsave label dword
oldi00	INTVEC 0	;; saved vector i00
if RING0 or CATCHINT01
oldi01	INTVEC 0	;; saved vector i01
endif
if RING0 or CATCHINT03
oldi03	INTVEC 0	;; saved vector i03
endif
if CATCHINT06
oldi06	INTVEC 0	;; saved vector i06
endif
if CATCHINT07
oldi07	INTVEC 0	;; saved vector i07
endif
if CATCHINT0C
oldi0C	INTVEC 0	;; saved vector i0C
endif
if CATCHINT0D
oldi0D	INTVEC 0	;; saved vector i0D
endif
if RING0
oldi0E	INTVEC 0	;; saved vector i0E
endif
if CATCHSYSREQ
oldisrq	INTVEC 0	;; saved vector i09/i15
endif
if INT22
		INTVEC 0	;; saved vector i22 (real-mode only)
endif
if RING0 and CATCHINT41
oldint41 INTVEC 0	;; saved vector i41 (protected-mode only)
endif
if _PM	;; must be last
oldi2f	dd 0		;; real-mode only
endif

if RING0
int10vec df 0	;; (int 10h) output routine
int16vec df 0	;; (int 16h) input routine
 if LMODE
jmpv64		label fword
		dd 0
		dw 8	;; selector 8 is 64-bit (Dos32cm)
jmpv161		label fword
		dw offset intrtnp1, 0
jmpv161s	dw 0	;; debugger CS
jmpv162		label fword
		dw offset intrtnp2, 0
jmpv162s	dw 0	;; debugger CS
dwBase64	dd 0	;; linear address start _TEXT64
 endif
 if FLATSS
dwBase	dd 0	;; linear address start _TEXT
 endif
endif

;; --- Parameter block for exec call.

if LCMDFILE
EXECS struc
environ	dw ?	;; +0 environment segment
cmdtail	dd ?	;; +2 address of command tail to copy
fcb1	dd ?	;; +6 address of first FCB to copy
fcb2	dd ?	;; +10 address of second FCB to copy
sssp	dd ?	;; +14 initial SS:SP
csip	dd ?	;; +18 initial CS:IP
EXECS ends

execblk	EXECS {0, 0, 5ch, 6ch, 0, 0}
endif

REGS struct
rDI	dw ?, ?	;; +00 EDI	;; must be in pushad order
rSI	dw ?, ?	;; +04 ESI
rBP	dw ?, ?	;; +08 EBP
	dw ?, ?	;; +12 reserved
rBX	dw ?, ?	;; +16 EBX
rDX	dw ?, ?	;; +20 EDX
rCX	dw ?, ?	;; +24 ECX
rAX	dw ?, ?	;; +28 EAX

rDS	dw ?	;; +32 DS		;; check run()/intrtn()/createdummytask() if this order changes!
rES	dw ?	;; +34 ES
rFS	dw ?	;; +36 FS		;; v2.0: order changed
rGS	dw ?	;; +38 GS
rSS	dw ?	;; +40 SS		;; should start on a dword boundary (in case AC is on)
rCS	dw ?	;; +42 CS
if ?PM
	dw ?	;; added (for 32-bit CS push)
endif

rSP	dw ?, ?	;; +46 ESP
rIP	dw ?, ?	;; +50 EIP
rFL	dw ?, ?	;; +54 eflags
if RING0
union
r0SSEsp		df ?
struct
r0Esp		dd ?
r0SS		dw ?
ends
ends
dwErrCode	dd ?
endif
if _PM	;; ?PM
msw		dw ?	;; 0000=real-mode, ffff=protected-mode
endif
REGS ends

;; --- Register save area.
	align 4		;; --- must be dword aligned!
regs REGS <>
_DATA ends

CONST segment
;; --- table of interrupt initialization
INTITEM struct
bInt	db ?
wOfs	dw ?
INTITEM ends

;; --- must match order in intsave
inttab label INTITEM
	INTITEM <00h, @VecAttr intr00>
if CATCHINT01
	INTITEM <01h, @VecAttr intr01>
endif
if CATCHINT03
	INTITEM <03h, @VecAttr intr03>
endif
if CATCHINT06
	INTITEM <06h, @VecAttr intr06>
endif
if CATCHINT07
	INTITEM <07h, @VecAttr intr07>
endif
if CATCHINT0C
	INTITEM <0ch, @VecAttr intr0C>
endif
if CATCHINT0D
	INTITEM <0dh, @VecAttr intr0D>
endif
if RING0
	INTITEM <0eh, @VecAttr intr0E>
endif
if CATCHSYSREQ
	INTITEM <SYSRQINT, intrsrq>
endif
if INT22
	INTITEM <22h, intr22dbg>
endif
if RING0 and CATCHINT41
itab41	INTITEM <41h, intr41>
endif
NUMINTS = ($ - inttab)/sizeof INTITEM
if _PM
	db 2fh
endif

;; --- register names for 'r'. One item is 2 bytes.
;; --- regofs must follow regnames and order of items must match those in regnames.
regnames db	'AX', 'BX', 'CX', 'DX',
		'SP', 'BP', 'SI', 'DI', 'IP', 'FL',
		'DS', 'ES', 'SS', 'CS', 'FS', 'GS'
NUMREGNAMES equ ($ - regnames)/2
regofs	dw	regs.rAX, regs.rBX, regs.rCX, regs.rDX,
		regs.rSP, regs.rBP, regs.rSI, regs.rDI, regs.rIP, regs.rFL,
		regs.rDS, regs.rES, regs.rSS, regs.rCS, regs.rFS, regs.rGS

;; --- arrays flgbits, flgnams and flgnons must be consecutive
flgbits dw 800h, 400h, 200h, 80h, 40h, 10h, 4, 1
flgnams db 'NV', 'UP', 'DI', 'PL', 'NZ', 'NA', 'PO', 'NC'
flgnons db 'OV', 'DN', 'EI', 'NG', 'ZR', 'AC', 'PE', 'CY'

;; --- Instruction set information needed for the 'p' command.
;; --- arrays ppbytes and ppinfo must be consecutive!

ppbytes	db 66h, 67h, 26h, 2eh, 36h, 3eh, 64h, 65h, 0f2h, 0f3h	;; prefixes
	db 0ach, 0adh, 0aah, 0abh, 0a4h, 0a5h	;; lods, stos, movs
	db 0a6h, 0a7h, 0aeh, 0afh		;; cmps, scas
	db 6ch, 6dh, 6eh, 6fh			;; ins, outs
	db 0cch, 0cdh				;; int instructions
	db 0e0h, 0e1h, 0e2h			;; loop instructions
	db 0e8h						;; call rel16/32
	db 09ah						;; call far seg16:16/32
;; (This last one is done explicitly by the code.)
;;	db 0ffh						;; ff/2 or ff/3: indirect call

;; Info for the above, respectively.
;;	80h = prefix;
;;	81h = address size prefix.
;;	82h = operand size prefix;
;; If the high bit is not set, the next highest bit (40h) indicates
;; that the instruction size depends on whether there is an address size prefix,
;; and the remaining bits tell the number of additional bytes in the instruction.
PP_ADRSIZ	equ 01h
PP_OPSIZ	equ 02h
PP_PREFIX	equ 80h
PP_VARSIZ	equ 40h

ppinfo	db 82h, 81h, 80h, 80h, 80h, 80h, 80h, 80h, 80h, 80h	;; prefixes
	db 0, 0, 0, 0, 0, 0					;; string instr
	db 0, 0, 0, 0						;; string instr
	db 0, 0, 0, 0						;; string instr
	db 0, 1							;; int instr
	db 1, 1, 1						;; loop* instr
	db 42h							;; near call instr
	db 44h							;; far call instr
PPLEN	equ $ - ppinfo

;; --- Strings.
ife (BOOTDBG or RING0)
	db '!'	;; additional prompt if InDos flag is set
endif
ifdef PROMPT
prompt1	db @CatStr(!', %PROMPT, !')
else
prompt1	db '-'	;; main prompt
endif

prompt2	db ':'	;; prompt for register value

if ?PM
 if _PM
	db '!'
 endif
prompt3	db '#'	;; protected-mode prompt
endif

helpmsg	db DBGNAME2, ' v', @CatStr(!', %VERSION, !'), CR, LF
	db 'assemble	A [address]', CR, LF
	db 'compare		C range address', CR, LF
	db 'dump		D [range]', CR, LF
if DGCMD
	db 'dump GDT	DG selector [count]', CR, LF
endif
if DICMD
 if RING0
	db 'dump IDT	DI interrupt [count]', CR, LF
 else
	db 'dump interrupt	DI interrupt [count]', CR, LF
 endif
endif
if DLCMD
	db 'dump LDT	DL selector [count]', CR, LF
endif
if DMCMD
	db 'dump MCB chain	DM', CR, LF
endif
if DPCMD
	db 'dump partitions	DP physical_disk', CR, LF
endif
if DTCMD
	db 'dump TSS	DT', CR, LF
endif
if DXCMD
	db 'dump ext memory	DX [physical_address]', CR, LF
endif
	db 'enter		E address [list]', CR, LF
	db 'fill		F range list', CR, LF
	db 'go		G [=address] [breakpts]', CR, LF
	db 'hex add/sub	H value1 value2', CR, LF
	db 'input		I[W|D] port', CR, LF
if LCMDFILE
	db 'load program	L [address]', CR, LF
endif
if BOOTDBG
	db 'load sectors	L address disk sector count', CR, LF
elseife RING0
	db 'load sectors	L address drive sector count', CR, LF
endif
	db 'move		M range address', CR, LF
	db '80x86 mode	M [x] (x=0..6)', CR, LF
	db 'set FPU mode	MC [2|N] (2=287,N=no FPU)', CR, LF
if LCMDFILE or WCMDFILE
	db 'set name	N [[drive:][path]progname [arglist]]', CR, LF
endif
	db 'output		O[W|D] port value', CR, LF
	db 'proceed		P [=address] [count]', CR, LF
if QCMD
	db 'quit		Q', CR, LF
 if _PM
	db 'forced pm quit	QQ', CR, LF
 endif
endif
	db 'register	R [register [value]]', CR, LF
if _PM
helpmsg2 label byte
endif
if MMXSUPP
	db 'MMX register	RM', CR, LF
endif
	db 'FPU register	RN', CR, LF
	db 'toggle 386 regs	RX', CR, LF
	db 'search		S range list', CR, LF
if _PM eq 0
helpmsg2 label byte
endif
if RING0
	db 'skip exception	SK', CR, LF
endif
	db 'trace		T [=address] [count]', CR, LF
	db 'trace mode	TM [0|1]', CR, LF
	db 'unassemble	U [range]', CR, LF
if VXCHG
	db 'view screen	V', CR, LF
endif
if VXCMD
	db 'clr/trap vector	V[C|T] vector', CR, LF
	db 'list vectors	VL', CR, LF
endif
if WCMDFILE
	db 'write program	W [address]', CR, LF
endif
if WCMD
	db 'write sectors	W address drive sector count', CR, LF
endif
if XCMDS
	db 'expanded mem	XA/XD/XM/XR/XS,X? for help'
endif
if _PM
	db CR, LF, LF
	db "prompts: '-' = real/v86-mode; '#' = protected-mode"
endif
crlf	db CR, LF
size_helpmsg2 equ $ - helpmsg2
	db '$'

presskey	db '[more]'

errcarat	db '^ Error'

ife (BOOTDBG or RING0)
dskerr0	db 'Write protect error', 0
dskerr1	db 'Unknown unit error', 0
dskerr2	db 'Drive not ready', 0
dskerr3	db 'Unknown command', 0
dskerr4	db 'Data error (CRC)', 0
dskerr6	db 'Seek error', 0
dskerr7	db 'Unknown media type', 0
dskerr8	db 'Sector not found', 0
dskerr9	db 'Unknown error', 0
dskerra	db 'Write fault', 0
dskerrb	db 'Read fault', 0
dskerrc	db 'General failure', 0

dskerrs	db dskerr0-dskerr0, dskerr1-dskerr0
	db dskerr2-dskerr0, dskerr3-dskerr0
	db dskerr4-dskerr0, dskerr9-dskerr0
	db dskerr6-dskerr0, dskerr7-dskerr0
	db dskerr8-dskerr0, dskerr9-dskerr0
	db dskerra-dskerr0, dskerrb-dskerr0
	db dskerrc-dskerr0
elseif BOOTDBG
dskerr1	db "Invalid disk", CR, LF, '$'
dskerrb	db "Read fault", CR, LF, '$'
szNoHD	db "Not a HD", CR, LF, '$'
endif

if LCMD or WCMD
szDrive	db ' ____ing drive '
driveno	db 0, 0			;; drive# for L/W cmds
endif

msg8088		db '8086/88', 0
msgx86		db 'x86', 0
no_copr		db ' without coprocessor', 0
has_copr	db ' with coprocessor', 0
has_287		db ' with 287', 0
regs386		db '386 regs o', 0
tmodes		db 'trace mode is '
tmodes2		db '? - INTs are ', 0
tmode1		db 'traced', 0
tmode0		db 'processed', 0
unused		db ' (unused)', 0

needsmsg	db '[needs x86]'		;; <--- modified (7 and 9)
needsmath	db '[needs math coprocessor]'
obsolete	db '[obsolete]'

;; --- exception 00-0e, Int 22h & SysReq messages
int0msg	db 'Divide error', CR, LF, '$'
int1msg	db 'Unexpected single-step interrupt', CR, LF, '$'
int3msg	db 'Unexpected breakpoint interrupt', CR, LF, '$'
if CATCHINT06 or CATCHEXC06
exc06msg	db 'Invalid opcode fault', CR, LF, '$'
endif
if CATCHINT07 or CATCHEXC07
exc07msg	db 'Coprocessor not present', CR, LF, '$'
endif
if CATCHINT0C or CATCHEXC0C
exc0Cmsg	db 'Stack fault', CR, LF, '$'
endif
if CATCHINT0D or ?PM
exc0Dmsg	db 'General protection fault', CR, LF, '$'
endif
if ?PM
 if RING0
exc0Emsg	db 'Page fault, CR2='
exc0Ecr2	db '________', CR, LF, '$'
 else
exc0Emsg	db 'Page fault.', CR, LF, '$'
 endif
endif
if INT22
progtrm		db CR, LF, 'Program terminated normally ('
progexit	db '____)', CR, LF, '$'
endif
if CATCHSYSREQ
sysrqmsg	db 'SysRq detected', CR, LF, '$'
endif

EXC00MSG equ offset int0msg - offset int0msg
EXC01MSG equ offset int1msg - offset int0msg
EXC03MSG equ offset int3msg - offset int0msg
if CATCHINT06 or CATCHEXC06
EXC06MSG equ offset exc06msg - offset int0msg
endif
if CATCHINT07 or CATCHEXC07
EXC07MSG equ offset exc07msg - offset int0msg
endif
if CATCHINT0C or CATCHEXC0C
EXC0CMSG equ offset exc0Cmsg - offset int0msg
endif
if CATCHINT0D or ?PM
EXC0DMSG equ offset exc0Dmsg - offset int0msg
endif
if ?PM
EXC0EMSG equ offset exc0Emsg - offset int0msg
endif
if INT22
INT22MSG equ offset progtrm - offset int0msg
endif
if CATCHSYSREQ
SYSRQMSG equ offset sysrqmsg - offset int0msg
endif

if EXCCSIP
excloc	db 'CS:IP=', 0
endif
if _PM
nodosext db 'Command not supported in protected-mode without a DOS-Extender', CR, LF, '$'
nopmsupp db 'Command not supported in protected-mode', CR, LF, '$'
 if DISPHOOK
dpmihook db 'DPMI entry hooked, new entry=', 0
 endif
nodesc	db 'not accessible in real-mode', 0
gatewrong db 'gate not accessible', 0
endif
if RING0
segerr	db "Debuggee segments invalid", CR, LF, '$'
endif
cantwritebp db "Can't write breakpoint", CR, LF, '$'

if WCMDFILE
nowhexe	db 'EXE and HEX files cannot be written', CR, LF, '$'
nownull	db 'Cannot write: no file name given', CR, LF, '$'
wwmsg1	db 'Writing $'
wwmsg2	db ' bytes', CR, LF, '$'
diskful	db 'Disk full', CR, LF, '$'
endif
if LCMDFILE or WCMDFILE
openerr	db 'Error '
openerr1 db '____ opening file', CR, LF, '$'
doserr2	db 'File not found', CR, LF, '$'
doserr3	db 'Path not found', CR, LF, '$'
doserr5	db 'Access denied', CR, LF, '$'
doserr8	db 'Insufficient memory', CR, LF, '$'
endif

if XCMDS

;; --- EMS error strings

;; emmname	db	'EMMXXXX0'
emsnot	db 'EMS not installed', 0
emserr1	db 'EMS internal error', 0
emserr3	db 'Handle not found', 0
emserr5	db 'No free handles', 0
emserr7	db 'Total pages exceeded', 0
emserr8	db 'Free pages exceeded', 0
emserr9	db 'Parameter error', 0
emserra	db 'Logical page out of range', 0
emserrb	db 'Physical page out of range', 0
emserrx	db 'EMS error '
emserrxa db '__', 0

emserrs	dw emserr1, emserr1, 0, emserr3, 0, emserr5, 0, emserr7, emserr8, emserr9
	dw emserra, emserrb

xhelpmsg	db 'Expanded memory (EMS) commands:', CR, LF
		db '  Allocate	XA count', CR, LF
		db '  Deallocate	XD handle', CR, LF
		db '  Map memory	XM logical-page physical-page handle', CR, LF
		db '  Reallocate	XR handle count', CR, LF
		db '  Show status	XS', CR, LF
size_xhelpmsg	equ $ - xhelpmsg

;; --- strings used by XA, XD, XR and XM commands
xaans	db 'Handle created: ', 0
xdans	db 'Handle deallocated: ', 0
xrans	db 'Handle reallocated', 0
xmans	db 'Logical page '
xmans_pos1 equ $ - xmans
	db '____ mapped to physical page '
xmans_pos2 equ $ - xmans
	db '__', 0

;; --- strings used by XS command
xsstr1	db 'Handle '
xsstr1a	db '____ has '
xsstr1b	db '____ pages allocated', CR, LF
size_xsstr1 equ $ - xsstr1

xsstr2	db 'phys. page '
xsstr2a	db '__ = segment '
xsstr2b	db '____  '
size_xsstr2 equ $ - xsstr2

xsstr3	db ' of a total ', 0
xsstr3a	db ' EMS ', 0
xsstrpg	db 'pag', 0
xsstrhd	db 'handl', 0
xsstr3b	db 'es have been allocated', 0

xsnopgs	db 'no mappable pages', CR, LF, CR, LF, '$'
endif

;; --- Flags for instruction operands.
;; --- First the sizes.
OpX	equ 40h		;; byte/word/dword operand (could be 30h but ...)
OpV	equ 50h		;; word or dword operand
OpB	equ 60h		;; byte operand
OpW	equ 70h		;; word operand
OpD	equ 80h		;; dword operand
OpQ	equ 90h		;; qword operand
OpLo	equ OpX		;; the lowest of these

;; --- These operand types need to be combined with a size flag.
;; --- The order must match items in AsmJump1, BitTab and DisJump1.
_I?	equ 00h		;; Immediate.
_E?	equ 02h		;; Register/Memory, determined form xr in xrm: memory of x ≠ 3, register r if x ≡ 3.
_M?	equ 04h		;; Memory (but not Register), determined from xm in xrm, with x ≠ 3.
_X?	equ 06h		;; Register (but not Memory), determined from m in xrm, with x ≡ 3.
_O?	equ 08h		;; Memory Offset; e.g., [1234].
_R?	equ 0ah		;; Register, determined from r in xrm.
_r?	equ 0ch		;; Register, determined from the low-order octal digit of the instruction byte.
_A?	equ 0eh		;; Accumulator: AL or AX or EAX.

;; --- The combinations in actual use are the following:
_Ix	equ OpX + _I?
_Iv	equ OpV + _I?
_Ib	equ OpB + _I?
_Iw	equ OpW + _I?
_Ex	equ OpX + _E?
_Ev	equ OpV + _E?
_Eb	equ OpB + _E?
_Ew	equ OpW + _E?
_Ed	equ OpD + _E?
_Eq	equ OpQ + _E?
_Mv	equ OpV + _M?
_Mw	equ OpW + _M?
_Md	equ OpD + _M?
_Xv	equ OpV + _X?
_Xd	equ OpD + _X?
_Ox	equ OpX + _O?
_Rx	equ OpX + _R?
_Rv	equ OpV + _R?
_Rw	equ OpW + _R?
_rv	equ OpV + _r?
_rb	equ OpB + _r?
_rd	equ OpD + _r?
_Ax	equ OpX + _A?
_Av	equ OpV + _A?
_Aw	equ OpW + _A?

;; --- These don't need a size.
;; --- The order must match items in AsmJump1, BitTab and DisOpTab.
;; --- Additionally, the order of _Q - _Mf is used in table AsmSizeNum.

;; --- The value 0 is used to terminate an operand list (see the macro opl).
_Q	equ 02h	;; qword memory (obsolete?)
_MF	equ 04h	;; float memory
_MD	equ 06h	;; double-precision floating memory
_MLD	equ 08h	;; tbyte memory
_Mx	equ 0ah	;; memory (size unknown)
_Mf	equ 0ch	;; memory far16/far32 pointer
_Af	equ 0eh	;; far16/far32 immediate
_Jb	equ 10h	;; byte address relative to IP
_Jv	equ 12h	;; word or dword address relative to IP
_ST1	equ 14h	;; check for ST(1)
_STi	equ 16h	;; ST(I)
_CRx	equ 18h	;; CRx
_DRx	equ 1ah	;; DRx
_TRx	equ 1ch	;; TRx
_Rs	equ 1eh	;; segment register
_Ds	equ 20h	;; sign extended immediate byte
_Db	equ 22h	;; immediate byte (other args may be (d)word)
_MMx	equ 24h	;; MMx
_N	equ 26h	;; set flag to always show the size

_1	equ 28h	;; 1 (simple "string" ops from here on)
_3	equ 2ah	;; 3
_DX	equ 2ch	;; DX
_CL	equ 2eh	;; CL
_ST	equ 30h	;; ST (top of coprocessor stack)
_CS	equ 32h	;; CS
_DS	equ 34h	;; DS
_ES	equ 36h	;; ES
_FS	equ 38h	;; FS
_GS	equ 3ah	;; GS
_SS	equ 3ch	;; SS
_Str	equ _1	;; The first "string" op.

;; --- Instructions that have an implicit operand subject to a segment override
;; --- (outsb/w, movsb/w, cmpsb/w, lodsb/w, xlat).
prfxtab	db 06eh,06fh, 0a4h,0a5h, 0a6h,0a7h, 0ach,0adh, 0d7h
P_LEN	equ $ - prfxtab

;; --- Instructions that can be used with rep/repe/repne.
replist		db 06ch, 06eh, 0a4h, 0aah, 0ach	;; rep (insb, outsb, movsb, stosb, lodsb)
N_REPNC		equ $ - replist
		db 0a6h, 0aeh			;; repe/repne (cmpsb, scasb)
N_REPALL	equ $ - replist

	include <DebugTab.inc>

opindex label byte
	.radix 16t
opidx = 0
	repeat ASMMOD
if opidx lt 10h
oi_name textequ <OPLIST_0>, %opidx
else
oi_name textequ <OPLIST_>, %opidx
endif
	db oi_name
opidx = opidx + 1
	endm
	.radix 10t
CONST ends

_TEXT segment
if RING0

;; --- get ring0 SS:ESP

getr0stk proc
	.386
	mov EAX, CS:[regs.r0Esp]
	mov DX, CS:[regs.r0SS]
 if LMODE
	sub EAX, 6*8
	and AL, 0f0h	;; aligned to 16-byte
 else
	sub EAX, 6*4	;; adjust ESP (ERRC, EIP, CS, EFL, ESP, SS)
 endif
	retd
	.8086
getr0stk endp

;; --- save/restore GDT descriptor of scratch selector
;; --- AL=1 -> save, AL=0 -> restore
;; --- DS=dgroup

srscratch:
	.386
if FLATSS
	sub ESP, 6
	sgdt [ESP]
else
	mov BP, SP
	sub SP, 6
	sgdt [BP-6]
endif
	movzx ESI, [scratchsel]
	pop AX
	pop EAX
	add ESI, EAX
	mov DI, offset sdescsave
	push DS
	mov DS, [wFlat]
	cmp AL, 0
	jz @F
	mov EAX, [ESI+0]
	mov EDX, [ESI+4]
	pop DS
	mov [DI+0], EAX
	mov [DI+4], EDX
	ret
@@:
	mov EAX, CS:[DI+0]
	mov EDX, CS:[DI+4]
	mov [ESI+0], EAX
	mov [ESI+4], EDX
	pop DS
	ret

_DATA segment
sdescsave dd 0, 0
_DATA ends
endif

if _PM
intcall proto stdcall :word, :word
_DATA segment
	align 4
dpmientry	dd 0	;; dpmi entry point returned by dpmi host
dpmiwatch	dd 0	;; address of dpmi initial switch to protected mode
dssel		dw 0	;; debugger's segment DATA
cssel		dw 0	;; debugger's segment CODE
dpmi_rm2pm	dd 0	;; raw mode switch real-mode to protected-mode
dpmi_pm2rm	df 0	;; raw mode switch protected-mode to real-mode
dpmi_size	dw 0	;; size of raw mode save state buffer
dpmi_rmsav	dd 0	;; raw mode save state real-mode
dpmi_pmsav	df 0	;; raw mode save state protected-mode
dpmi32		db 0	;; bit 0: 0=16-bit client, 1=32-bit client
bNoHook2F	db 0	;; 1=int 2f, AX=1687h cannot be hooked (win3x/9x dos box, DosEmu?)

;; --- pmints and pmvectors must match!
pmvectors label fword	;; vectors must be consecutive and in this order!
if CATCHINT41
oldint41	label dword
		dw 0, 0, 0
endif
if CATCHINT31
oldint31	label dword
		dw 0, 0, 0
endif
if CATCHINT21
oldint21	label dword
		dw 0, 0, 0
endif
_DATA ends

;; --- int 2f handler
debug2F:
	pushf
	cmp AX, 1687h
dpmidisable:		;; set [IP+1]=0 if hook 2f is to be disabled
	jz @F
	popf
	jmp CS:[oldi2f]
@@:
	call CS:[oldi2f]
	and AX, AX
	jnz @F
	mov word ptr CS:[dpmientry+0], DI
	mov word ptr CS:[dpmientry+2], ES
	mov DI, offset mydpmientry
	push CS
	pop ES
@@:
	iret

;; --- this code is called
;; --- 1.	if int 2f, AX=1687h has been hooked (winnt, hdpmi, ...)
;; ---		the debuggee will then call this proc directly to switch to protected-mode
;; --- 2.	if int 2f, AX=1687h has NOT been hooked (win3x, win9x, dosemu)
;; ---		the debugger has to detect (inside trace cmd) that the dpmi entry address has been reached.
mydpmientry:
	mov CS:[dpmi32], AL
	call CS:[dpmientry]	;; call the real dpmi entry
	jc @F
	call installdpmi
@@:
	retf

	.286

CONST segment
pmints label byte	;; pmints and pmvectors must match!
if CATCHINT41
	db 41h
	dw intr41pm
endif
if CATCHINT31
	db 31h
	dw intr31pm
endif
if CATCHINT21
	db 21h
	dw intr21pm
endif
LPMINTS equ ($ - offset pmints)/3

if 0	;; v2.0: removed
convsegs label word
;;	dw offset run_cs
;;	dw offset pInDOS+2
;; if USESDA
;;	dw offset pSDA+2
;; endif
	dw offset a_addr+4
	dw offset d_addr+4
NUMSEGS equ ($-convsegs)/2
endif

exctab label byte	;; DPMI exception table
	db 0
	db 1
	db 3
if CATCHEXC06
	db 06h
endif
if CATCHEXC07
	db 07h
endif
if CATCHEXC0C
	db 0ch
endif
	db 0dh
	db 0eh
endexctab label byte
CONST ends

_DATA segment
dbeexc0d0e label word	;; saved debuggee's exc 0d/0e when debugger is entered
	dw 2 dup (0, 0, 0)
_DATA ends

;; --- client entered protected mode.
;; --- inp: [SP+4] = client real-mode CS

INSTFRM struct
	org -2
_ds	dw ?			;; client's DS (selector)
	dw 8 dup (?)	;; pusha
_ret dw ?			;; return addr installdpmi()
_ip	dw ?			;; client's IP
_cs	dw ?			;; client's CS
INSTFRM ends

installdpmi proc
	pusha
	mov BP, SP
	push DS
	mov BX, CS
	mov AX, 000ah	;; get a data descriptor for Debug's segment
	int 31h
	jc fataldpmierr
	mov DS, AX
	@dprintf "installdpmi: client entered pm"
	mov [cssel], CS
	mov [dssel], DS
	mov CX, 2		;; alloc 2 descriptors
	xor AX, AX
	int 31h
	jnc @F
fataldpmierr:
	mov AX, 4cffh
	int 21h
@@:
	mov [scratchsel], AX	;; the first is used as scratch descriptor
	mov BX, AX
	xor CX, CX
if 1
	cmp [machine], 3		;; is at least a 80386?
	jb @F
else
	cmp [dpmi32], 0		;; is a 16-bit client?
	jz @F
endif
	dec CX			;; set a limit of ffffffffh
@@:
	or DX, -1
	mov AX, 0008h
	int 31h
	add BX, 8		;; the second selector is client's CS
	xor CX, CX		;; this limit is ffff even for 32-bits
	mov AX, 0008h
	int 31h
	mov DX, [BP].INSTFRM._cs	;; get client's CS
	call setrmaddr			;; set base
	mov AX, CS
	lar CX, AX
	shr CX, 8				;; CS remains 16-bit
	mov AX, 0009h
	int 31h
	mov [BP].INSTFRM._cs, BX	;; set client's CS

if 1
;; --- v2.0: (re)init default for d cmd
	mov AX, [BP].INSTFRM._ds
	mov [d_addr+4], AX
	mov [bFlagsPM], 0		;; reset all pm flags
endif

	cld

	mov BX, word ptr [pInDOS+2]
	mov AX, 2
	int 31h
	mov [InDosSel], AX
if USESDA
	mov BX, word ptr [pSDA+2]
	mov AX, 2
	int 31h
	mov [SDASel], AX
endif

if 0	;; v2.0: removed, default for a/d cmds see above
	mov SI, offset convsegs
	mov CX, NUMSEGS
@@:
	lodsw
	mov DI, AX
	mov BX, [DI]
	mov AX, 2
	int 31h
	jc fataldpmierr
	mov [DI], AX
	loop @B
endif

	sizeprf			;; push EDI - save hiword(EDI)
	push DI

	mov BP, 2		;; 2=size offset for DPMi16
	cmp dpmi32, 0
	jz @F
	inc BP
	inc BP			;; 4=size offset for DPMI32
@@:
	mov AX, 0305h			;; get raw-mode save state addresses
	int 31h
	mov word ptr [dpmi_rmsav+0], CX
	mov word ptr [dpmi_rmsav+2], BX
	sizeprf					;; mov dword ptr [dpmi_pmsav], EDI
	mov word ptr [dpmi_pmsav], DI
	mov word ptr DS:[BP+dpmi_pmsav], SI
	mov word ptr [dpmi_size], AX
	mov AX, 0306h			;; get raw-mode switch addresses
	int 31h
	mov word ptr [dpmi_rm2pm+0], CX
	mov word ptr [dpmi_rm2pm+2], BX
	sizeprf					;; mov dword ptr [dpmi_pm2rm], EDI
	mov word ptr [dpmi_pm2rm], DI
	mov word ptr DS:[BP+dpmi_pm2rm], SI

	sizeprf			;; pop EDI - restore hiword(EDI)
	pop DI

;; --- hook exceptions 0, 1, 3, 6, (7), (c), d, e
	mov SI, offset exctab
	sizeprf			;; push EDX - save hiword(EDX)
	push DX
	sizeprf			;; xor EDX, EDX
	xor DX, DX
	mov DX, offset exc00
@@:
	lodsb
	mov BL, AL
	mov CX, CS
	mov AX, 0203h
	int 31h
	add DX, exc01-exc00
	cmp SI, offset endexctab
	jb @B

;; --- hook DPMI protected-mode interrupts
if LPMINTS
	mov SI, offset pmvectors
	mov DI, offset pmints
	mov CX, LPMINTS
nextpmint:
	mov BL, CS:[DI]
	push CX
	mov AX, 204h
	int 31h
	sizeprf	;; mov [SI], EDX
	mov [SI], DX
	mov DS:[SI+BP], CX
	sizeprf	;; xor EDX, EDX
	xor DX, DX
	mov DX, [DI+1]
	mov CX, CS
	mov AL, 5
	int 31h
	add SI, sizeof fword
	add DI, 3
	pop CX
	loop nextpmint
endif

	sizeprf				;; pop EDX - restore hiword(EDX)
	pop DX

	mov BL, 2fh			;; get int 2fh real-mode vector
	mov AX, 200h
	int 31h
	cmp CX, [pspdbg]		;; did we hook it and are the last in chain?
	jnz int2fnotours
	mov DX, word ptr [oldi2f+0]
	xor CX, CX
	xchg CX, word ptr [oldi2f+2]	;; then unhook
	mov AX, 201h
	int 31h
int2fnotours:
	pop DS
	popa
	clc
	ret

installdpmi endp

;; --- v2.0: set/reset debugger's exception vectors for 0d/0e.
;; --- Since the debugger very easily causes those exceptions,
;; --- and the debuggee might have set the vectors to its own routines,
;; --- it's a must to restore them to debugger code while the debugger is active.

;; --- setdbeexc0d0e: set debuggee's exception 0d/0e when running it
setdbeexc0d0e proc
	call ispm_dbe
	jz done
	mov SI, offset dbeexc0d0e
	mov BL, 0dh
nextexc:
	sizeprf	;; lodsd
	lodsw
	sizeprf	;; mov EDX, EAX
	mov DX, AX
	lodsw
	mov CX, AX
	jcxz @F
	mov AX, 0203h
	int 31h
@@:
	inc BL
	cmp BL, 0eh
	jbe nextexc
done:
	ret
setdbeexc0d0e endp

;; --- set debugger's exception 0d/0e when reentering it
;; --- for int 31h, AX=203h, flag [bInDbg] must be 1 if CATCHINT31 is active.

setdbgexc0d0e proc
	call ispm_dbe
	jz done
	mov DI, offset dbeexc0d0e
	mov SI, offset exc0d
	mov BL, 0dh
@@:
	mov AX, 0202h
	int 31h
	sizeprf
	mov AX, DX
	sizeprf
	stosw
	mov AX, CX
	stosw
	sizeprf			;; movzx EDX, SI
	lea DX, [SI]
	mov CX, CS
	mov AX, 0203h
	int 31h
	add SI, exc01-exc00
	inc BL
	cmp BL, 0eh
	jbe @B
done:
	ret
setdbgexc0d0e endp

	include <TrapD.inc>

if CATCHINT21
intr21pm proc
	cmp AH, 04ch
	jz is4c
prevint21:
	cmp CS:[dpmi32], 0
	jz @F
	db 66h
@@:
	jmp CS:[oldint21]
is4c:
	push DS
	mov DS, CS:[dssel]
	call exitdpmi
	pop DS
	jmp prevint21
intr21pm endp
endif

if CATCHINT31
intr31pm proc
	cmp CS:[bInDbg], 0	;; v2.0 do nothing if debugger is active
	jnz notinterested
	cmp AX, 0203h	;; set exception vector?
	jz is203
	cmp AX, 0212h	;; v2.0: set exception vector v1.0?
	jz is212
notinterested:
	cmp CS:[dpmi32], 0
	jz @F
	db 66h
@@:
	jmp CS:[oldint31]
is203:
is212:
	cmp BL, 1
	jz @F
	cmp BL, 3
	jz @F
	cmp BL, 0dh
	jz @F
	cmp BL, 0eh
	jnz notinterested
@@:
;;	jmp execiret
intr31pm endp
endif

;; --- fall thru!

execiret:
	cmp CS:[dpmi32], 0
	jz @F
	db 66h		;; iretd
@@:
	iret

i23pm:
i24pm:
	cmp CS:[dpmi32], 0	;; clears C
	jz @F
	retd 4
@@:
	retf 2

	.8086

endif	;; _PM

if CATCHINT41
 if _PM
intr41pm:
 endif
intr41 proc
	cmp AX, 004fh
	jz is4f
 if _PM
	cmp CS:[dpmi32], 0
	jz @F
	db 66h
@@:
 endif
	jmp CS:[oldint41]
is4f:
	mov AX, 0f386h
 if _PM
	jmp execiret
 else
	iretd
 endif
intr41 endp
endif

if INT22
;; INTR22DBG - int 22 (Program terminate) interrupt handler.
;; This is for Debug itself:
;; it's a catch-all for the various int 23 and int 24 calls that may occur unpredictably at any time.
;; What we do is pretend to be a command interpreter (which we are, in a sense, just a different sort of command)
;; by setting the PSP of our parent equal to our own PSP so that DOS does not free our memory when we quit.
;; Therefore control ends up here when Control-Break or an Abort in Abort/Retry/Fail is selected.
intr22dbg:
	cld			;; reestablish things
	mov AX, CS
	mov DS, AX
	mov SS, AX
elseif RING0
entercmd:
	mov DS, CS:[pspdbg]
	push DS
	pop SS
endif
;; --- fall through to cmdloop!
;; --- Begin main command loop.
cmdloop proc
if FLATSS
	mov ESP, [top_sp]	;; restore stack (this must be first)
else
	mov SP, [top_sp]	;; restore stack (this must be first)
endif
	mov [errret], offset cmdloop
	push DS
	pop ES
if LCMDFILE
	call isdebuggeeloaded
	jnz @F
	call createdummytask	;; if no task is active, create a dummy one
@@:
endif
	mov CX, 1
ife ?PM
	mov DX, offset prompt1
else
 if _PM
	mov DX, offset prompt1
	call ispm_dbe			;; debuggee in rm/pm?
	jz @F
 endif
	mov DX, offset prompt3
@@:
endif
ife (BOOTDBG or RING0)
	call InDos
	jz @F
 ife VXCHG
	mov AH, 0fh
	int 10h
	mov [vpage], BH	;; ensure [vpage] is initialized if InDos is set
 endif
	dec DX		;; if inside DOS, display a '!' before the real prompt
	inc CX
@@:
endif
	call getline	;; prompted input
	cmp AL, CR
	jnz @F
	mov DX, [lastcmd]
	dec SI
	jmp cmd4
@@:
	cmp AL, ';'
	je cmdloop	;; if comment
	cmp AL, '?'
	je printhelp	;; if request for help
	or AL, TOLOWER
	sub AL, 'a'
	cmp AL, ENDCMD - 'a'
	ja errorj1		;; if not recognized
	cbw
	xchg BX, AX
	call skipcomma
	shl BX, 1
	mov DX, [cmdlist+BX]
	mov [lastcmd], offset dmycmd
	mov AH, [SI-2]	;; v2.0: for easily detecting 2-byte cmds
	or AH, TOLOWER
cmd4:
	mov DI, offset line_out
	call DX
	jmp cmdloop		;; back to the top

errorj1:
	jmp cmd_error
cmdloop endp

dmycmd:
	ret

printhelp:
	mov DX, offset helpmsg
	mov CX, offset helpmsg2 - offset helpmsg
	call stdout
	call waitkey
	mov DX, offset helpmsg2
	mov CX, size_helpmsg2
	call stdout
	jmp cmdloop		;; done

waitkey proc
if REDIRECT
	test [fStdin], AT_DEVICE	;; stdin a file?
	jz nowait
	test [fStdout], AT_DEVICE	;; stdout a file?
	jz nowait
endif
	push DS
ife RING0
	mov AX, 40h			;; 0040h is a bimodal segment/selector
	mov DS, AX
	cmp byte ptr DS:[84h], 30	;; rows >= 30?
else
	mov DS, [wFlat]
	cmp byte ptr DS:[484h], 30
endif
	pop DS
	jnc nowait
	mov DX, offset presskey
	mov CX, sizeof presskey
	call stdout
;;	mov AH, 8		;; use DOS
;;	int 21h
	mov AH, 0		;; v1.27: use BIOS
if RING0
	.386
	call CS:[int16vec]
	.8086
else
	int 16h
endif
	mov AL, CR
	call stdoutal
nowait:
	ret
waitkey endp

;; --- A command - tiny assembler.
_DATA segment
asm_mn_flags	db 0	;; flags for the mnemonic

AMF_D32		equ 1		;; 32bit opcode/data operand
AMF_WAIT	equ 2
AMF_A32		equ 4		;; address operand is 32bit
AMF_SIB		equ 8		;; there's a SIB in the arguments
AMF_MSEG	equ 10h		;; if a seg prefix was given b4 mnemonic
AMF_FSGS	equ 20h		;; if FS or GS was encountered

AMF_D16		equ 40h		;; 16bit opcode/data operand
AMF_ADDR	equ 80h		;; address operand is given

;; --- aa_saved_prefix and aa_seg_pre must be consecutive.
aa_saved_prefix	db 0	;; wait or rep... prefix
aa_seg_pre	db 0	;; segment prefix

mneminfo	dw 0	;; address associated with the mnemonic
a_opcode	dw 0	;; op code info for this variant
a_opcode2	dw 0	;; copy of a_opcode for obs-instruction

;; --- dmflags values
DM_COPR		equ 1	;; math coprocessor
DM_MMX		equ 2	;; MMX extensions

;; --- varflags values
VAR_LOCKABLE	equ 1	;; variant is lockable
VAR_MODRM	equ 2	;; if there's a XRM here
VAR_SIZ_GIVN	equ 4	;; if a size was given
VAR_SIZ_FORCD	equ 8	;; if only one size is permitted
VAR_SIZ_NEED	equ 10h	;; if we need the size
VAR_D16		equ 20h	;; if operand size is word
VAR_D32		equ 40h	;; if operand size is dword

AINSTR struct
rmaddr		dw ?	;; address of operand giving the R/M byte (asm only)
;; --- regmem and sibbyte must be consecutive
regmem		db ?	;; mod reg r/m part of instruction
sibbyte		db ?	;; SIB byte
immaddr		dw ?	;; address of operand giving the immed stf (asm only)
xxaddr		dw ?	;; address of additional stuff (asm only)
;; --- dismach and dmflags must be consecutive
dismach		db ?	;; type of processor needed
dmflags		db ?	;; flags for extra processor features
opcode_or	db ?	;; extra bits in the op code (asm only)
opsize		db ?	;; size of this operation (2 or 4) (asm only)
varflags	db ?	;; flags for this variant (asm only)
reqsize		db ?	;; size that this arg should be (asm only)
AINSTR ends

ai	AINSTR <?>		;; used by assembler and disassembler
_DATA ends

CONST segment
;; --- search for "obsolete" instructions
;; --- dbe0: feni
;; --- dbe1: fdisi
;; --- dbe4: fsetpm
;; --- 124: mov TRx, Xd
;; --- 126: mov Xd, TRx
OldOp	dw 0dbe0h, 0dbe1h, 0dbe4h, 124h, 126h	;; obsolete instruction codes
OldCPU	db 1, 1, 2, 4, 4			;; max permissible machine for the above
XrmTab	db 11, 0, 13, 0, 15, 0, 14, 0		;; [BX], [BP], [DI], [SI]
	db 15, 13, 14, 13, 15, 11, 14, 11	;; [BP+DI], [BP+SI], [BX+DI], [BX+SI]
BcdArg	db 'a', CR

;; --- Equates for parsed arguments, stored in ArgT.Flags
ArgMx	equ 01h	;; non-immediate memory reference
ArgXRM	equ 02h	;; if we've computed the XRM byte
ArgRx	equ 04h	;; a solo register
ArgSx	equ 08h	;; if it's a segment register or CR, etc.
ArgIx	equ 10h	;; if it's just a number
ArgAf	equ 20h	;; if it's of the form xxxx:yyyyyyyy

;; --- For each operand type in the following table,
;; --- the first byte is the bits, at least one of which must be present;
;; --- the second is the bits all of which must be absent.
;; --- the items in BitTab must be ordered similiar to AsmJump1 and DisJump1.
BitTab label byte
	db ArgIx	;; _I?
	db ArgMx+ArgRx	;; _E?
	db ArgMx	;; _M?
	db ArgRx	;; _X?
	db ArgMx	;; _O?
	db ArgRx	;; _R?
	db ArgRx	;; _r?
	db ArgRx	;; _A?

	db ArgMx	;; _Q
	db ArgMx	;; _MF
	db ArgMx	;; _MD
	db ArgMx	;; _MLD
	db ArgMx	;; _Mx
	db ArgMx	;; _Mf
	db ArgAf	;; _Af
	db ArgIx	;; _Jb
	db ArgIx	;; _Jv
	db ArgSx	;; _ST1
	db ArgSx	;; _STi
	db ArgSx	;; _CRx
	db ArgSx	;; _DRx
	db ArgSx	;; _TRx
	db ArgSx	;; _Rs
	db ArgIx	;; _Ds
	db ArgIx	;; _Db
	db ArgSx	;; _MMx
	db 0ffh		;; _N

	db ArgIx	;; _1
	db ArgIx	;; _3
	db ArgRx	;; _DX
	db ArgRx	;; _CL
	db ArgSx	;; _ST
	db ArgSx	;; _CS
	db ArgSx	;; _DS
	db ArgSx	;; _ES
	db ArgSx	;; _FS
	db ArgSx	;; _GS
	db ArgSx	;; _SS

;; --- Special ops DX, CL, ST, CS, DS, ES, FS, GS, SS
;; --- An entry required if AOpReg is set above.
;; --- The order of entries matches the last 9 ones in DisOpTab.
asm_regnum label byte
	db REG_DX, REG_CL, REG_ST, REG_CS, REG_DS, REG_ES, REG_FS, REG_GS, REG_SS

;; --- Size qualifiers
SIZ_NONE	equ 0
SIZ_BYTE	equ 1	;; BY = byte ptr
SIZ_WORD	equ 2	;; WO = word ptr
			;; unused
SIZ_DWORD	equ 4	;; DW = dword ptr
SIZ_QWORD	equ 5	;; QW = qword ptr
SIZ_FLOAT	equ 6	;; FL = float ptr (real4)
SIZ_DOUBLE	equ 7	;; DO = double ptr (real8)
SIZ_TBYTE	equ 8	;; TB = tbyte ptr (real10)
SIZ_SHORT	equ 9	;; SH = short
SIZ_LONG	equ 10	;; LO = long
SIZ_NEAR	equ 11	;; NE = near ptr
SIZ_FAR		equ 12	;; FA = far ptr
sizetcnam	db 'BY', 'WO', 'WO', 'DW', 'QW', 'FL', 'DO', 'TB', 'SH', 'LO', 'NE', 'FA'

;; --- sizes for _Q, _MF, _MD, _MLD, _Mx, _Mf
AsmSizeNum	db SIZ_QWORD, SIZ_FLOAT, SIZ_DOUBLE, SIZ_TBYTE
		db -1, SIZ_FAR			;; -1 = none
CONST ends

;; --- write byte in AL to BX/[E]DX, then increment [E]DX
writeasm proc
	call writemem
	sizeprfX	;; inc EDX
	inc DX
	ret
writeasm endp

;; --- write CX bytes from DS:SI to BX:[E]DX
writeasmn proc
	jcxz nowrite
@@:
	lodsb
	call writeasm
	loop @B
nowrite:
	ret
writeasmn endp

a_cmd proc
	mov [errret], offset aa01
	cmp AL, CR
	je aa01x		;; if end of line
	mov BX, [regs.rCS]	;; default segment to use
aa00a:
	call getaddr		;; get address into BX:(E)DX
	call chkeol		;; expect end of line here
	sizeprfX		;; mov [a_addr+0], EDX
	mov [a_addr+0], DX	;; save the address
	mov word ptr [a_addr+4], BX
if ?PM
	jmp aa01
aa01x:
 if _PM
	call ispm_dbe
	jz aa01
;; --- v2.0: def seg for a is no longer automatically converted
;; --- when pm is entered.
 endif
	test [bFlagsPM], 1	;; default for a-cmd already set?
	jnz aa01
	mov AX, [regs.rCS]	;; use current CS:IP as default
	mov [a_addr+4], AX
	sizeprfX
	mov AX, [regs.rIP]
	sizeprfX
	mov [a_addr+0], AX
else
aa01x:
endif

;; --- Begin loop over input lines.
aa01:
if ?PM
	or [bFlagsPM], 1
endif
	@dprintf "a: a_addr=%X:%lX", word ptr [a_addr+4], dword ptr [a_addr+0]
if FLATSS
	.386
	mov ESP, [top_sp]	;; restore the stack (this implies no "ret")
else
	mov SP, [top_sp]	;; restore the stack (this implies no "ret")
endif
	mov DI, offset line_out
	mov AX, [a_addr+4]
	call hexword
	mov AL, ':'
	stosb
	mov [asm_mn_flags], 0
	mov BP, offset hexword
if ?PM
	mov BX, [a_addr+4]
	call getseldefsize
	mov [bCSAttr], AL
	jz @F
	mov BP, offset hexdword
;;	mov [asm_mn_flags], AMF_D32
	db 66h	;; mov EAX, [a_addr]
@@:
endif
	mov AX, [a_addr+0]
	call BP
	mov AL, ' '
	stosb
	call getline00
	cmp AL, CR
	je aa_exit	;; if done
	cmp AL, ';'
	je aa01		;; if comment
	mov word ptr [aa_saved_prefix], 0	;; clear aa_saved_prefix and aa_seg_pre

;; --- Get mnemonic and look it up.
aa02:
	mov DI, offset line_out	;; return here after lock/rep/seg prefix
	push SI			;; save position of mnemonic
aa03:
	cmp AL, 'a'
	jb @F			;; if not lower case letter
	cmp AL, 'z'
	ja @F
	and AL, TOUPPER		;; convert to upper case
@@:
	stosb
	lodsb
	cmp AL, CR
	je @F			;; if end of mnemonic
	cmp AL, ';'
	je @F
	cmp AL, ' '
	je @F
	cmp AL, ':'
	je @F
	cmp AL, TAB
	jne aa03
@@:
	or byte ptr [DI-1], 80h	;; set highest bit of last char of mnemonic
	call skipwh0		;; skip to next field
	dec SI
	push SI			;; save position in input line
;;	mov AL, 0
;;	stosb

;; --- now search mnemonic in list
	mov SI, offset mnlist
aa06:		;; <--- next mnemonic
	mov BX, SI
	add SI, 2		;; skip the 'asmtab' offset
	mov CX, SI
@@:
	lodsb			;; skip to end of string
	and AL, AL
	jns @B			;; if not end of string
	xchg CX, SI
	push CX
	sub CX, SI		;; size of opcode in mnlist
	mov DI, offset line_out
	repe cmpsb
	pop SI
	je aa14			;; if found it
	cmp SI, offset end_mnlist
	jc aa06			;; next mnemonic
	pop SI			;; skip position in input line
aa13a:
	pop SI			;; skip position of mnemonic
aa13b:
	jmp cmd_error	;; complain
aa_exit:
	jmp cmdloop		;; done with this command

;; --- We found the mnemonic.
aa14:
	mov SI, [BX]		;; get the offset into asmtab
	add SI, offset asmtab

;; Now SI points to the spot in asmtab corresponding to this mnemonic.
;; The format of the assembler table is as follows.
;; First, there is optionally one of the following bytes:
;;	ASM_DB		db mnemonic
;;	ASM_DW		dw mnemonic
;;	ASM_DD		dd mnemonic
;;	ASM_WAIT	the mnemonic should start with a wait instruction.
;;	ASM_D32		This is a 32 bit instruction variant.
;;	ASM_D16		This is a 16 bit instruction variant.
;;	ASM_AAX		Special for aam and aad instructions: put 0ah in for a default operand.
;;	ASM_SEG		This is a segment prefix.
;;	ASM_LOCKREP	This is a lock or rep... prefix.
;; Then, in most cases, this is followed by one or more of the following sequences, indicating an instruction variant.
;;	ASM_LOCKABLE	(optional) indicates that this instruction can follow a lock prefix.
;;	ASM_MACHx	(optional) indicates the first machine on which this instruction appeared.
;;	[word]		This is a 16-bit integer, most significant byte first,
;;			giving ASMMOD*a + b, where b is an index into the array opindex
;;			(indicating the key, or type of operand list), and a is as follows:
;;			0-255	The (one-byte) instruction.
;;			256-511	The lower 8 bits give the second byte of a two-byte instruction beginning with 0fh.
;;			512-575	Bits 2-0 say which floating point instruction this is (0d8h-0dfh), and 5-3 give the /r field.
;;			576-...	(a-576)/8 is the index in the array agroups
;;				(which gives the real value of a), and the low-order 3 bits gives the /r field.
;;	[byte]		This gives the second byte of a floating instruction if 0d8h <= a <= 0dfh.
;; Following these is an ASM_END byte.
;; Exceptions:
;;	ASM_SEG and ASM_LOCKREP are followed by just one byte, the prefix byte.
;;	ASM_DB, ASM_DW, and ASM_DD don't need to be followed by anything.
ASM_END		equ 0ffh
ASM_DB		equ 0feh
ASM_DW		equ 0fdh
ASM_DD		equ 0fch
ASM_ORG		equ 0fbh
ASM_WAIT	equ 0fah
ASM_D32		equ 0f9h
ASM_D16		equ 0f8h
ASM_AAX		equ 0f7h
ASM_SEG		equ 0f6h
ASM_LOCKREP	equ 0f5h
ASM_LOCKABLE equ 0f4h
ASM_MACH6	equ 0f3h
ASM_MACH5	equ 0f2h
ASM_MACH4	equ 0f1h
ASM_MACH3	equ 0f0h
ASM_MACH2	equ 0efh
ASM_MACH1	equ 0eeh
ASM_MACH0	equ 0edh

	cmp byte ptr [SI], ASM_LOCKREP	;; check for mnemonic flag byte
	jb aa15				;; if none
	lodsb				;; get the prefix
	sub AL, ASM_LOCKREP		;; convert to 0-9
	je aa18				;; if lock or rep...
	cbw
	dec AX
	jz aa17				;; if segment prefix (ASM_SEG)
	dec AX
	jz aa16				;; if aad or aam (ASM_AAX)
	dec AX
	jz aa15_1			;; if ASM_D16
	cmp AL, 3
	jae aa20			;; if ASM_ORG or ASM_DD or ASM_DW or ASM_DB
	or [asm_mn_flags], AL		;; save AMF_D32 or AMF_WAIT (1 or 2)
aa15:
	jmp ab01			;; now process the arguments
aa15_1:
	or [asm_mn_flags], AMF_D16
	inc SI				;; skip the ASM_D32 byte
	jmp ab01			;; now process the arguments

aa16:
	jmp ab00

;; --- segment prefix
aa17:
	lodsb			;; get prefix value
	mov [aa_seg_pre], AL
	mov CL, AL
	or [asm_mn_flags], AMF_MSEG
	pop SI			;; get position in input line
	pop AX			;; skip
	lodsb
	cmp AL, ':'
	jne aa13b
	call skipwhite
	cmp AL, CR
	je @F
	cmp AL, ';'
	jne aa13b
@@:
	mov DI, offset line_out
	mov AL, CL
	stosb
	jmp aa27		;; back for more

;; --- lock or rep prefix
aa18:
	lodsb				;; get prefix value
	xchg AL, [aa_saved_prefix]
	cmp AL, 0
	jnz aa13a			;; if there already was a saved prefix
	pop SI
	pop AX
	lodsb
	cmp AL, CR
	je @F				;; if end of line
	cmp AL, ';'
	je @F				;; if end of line (comment)
	jmp aa02			;; back for more
@@:
	mov AL, [aa_saved_prefix]	;; just a prefix, nothing else
	mov DI, offset line_out
	stosb
	jmp aa27

;; --- Pseudo ops (org or db/dw/dd).
aa20:
	cmp word ptr [aa_saved_prefix], 0
	jnz aa13a		;; if there was a prefix or a segment: error
	pop SI			;; get position in input line
	sub AL, 3		;; AX=0 if org, 1 if dd, 2 if dw, 3 if db.
	jnz aa20m		;; if not org

;; --- Process the org pseudo op.
	call skipwhite
	cmp AL, CR
	je @F			;; if nothing
	mov BX, [a_addr+4]	;; default segment
	jmp aa00a		;; go to top
@@:
	jmp aa01		;; get next line

;; --- Data instructions (db/dw/dd).
aa20m:
	mov DI, offset line_out	;; put the bytes here when we get them
	xchg AX, BX		;; mov BX, AX
	shl BX, 1
	mov BP, [BX+aadbsto-2]	;; get address of storage routine
	call skipwhite
	cmp AL, CR
	je aa27			;; if end of line

aa21:		;; <--- loop
	cmp AL, '"'
	je aa22			;; if string
	cmp AL, "'"
	je aa22			;; if string
	call aageti		;; get a numerical value into DX:BX, size into CL
	cmp CL, CS:[BP-1]	;; compare with size
	jg aa24			;; if overflow
	xchg AX, BX
	call BP			;; store value in AL/AX/DX:AX
	cmp DI, offset real_end
	ja aa24			;; if output line overflow
	xchg AX, BX
	jmp aa26		;; done with this one

aa22:
	mov AH, AL
aa23:
	lodsb
	cmp AL, CR
	je aa24			;; if end of line
	cmp AL, AH
	je aa25			;; if end of string
	stosb
	cmp DI, offset real_end
	jbe aa23		;; if output line not overflowing
aa24:
	jmp aa13b		;; error
aa25:
	lodsb
aa26:
	call skipcomm0
	cmp AL, CR
	jne aa21		;; if not end of line

;; --- End of line.
;; --- Copy it to debuggee's memory
aa27:
	mov SI, offset line_out
	mov BX, [a_addr+4]
	sizeprfX	;; mov EDX, [a_addr+0]
	mov DX, [a_addr+0]
	mov CX, DI
	sub CX, SI
	call writeasmn
	sizeprfX	;; mov [a_addr+0], EDX
	mov [a_addr+0], DX
	jmp aa01

CONST segment
;; --- table for routine to store a number (index dd=1, dw=2, db=3)
aadbsto dw sto_dd, sto_dw, sto_db
CONST ends

;; --- Routines to store a byte/word/dword.
	db 4		;; size to store
sto_dd:
	stosw		;; store a dword value
	xchg AX, DX
	stosw
	xchg AX, DX
	ret
	db 2		;; size to store
sto_dw:
	stosw		;; store a word value
	ret
	db 1		;; size to store
sto_db:
	stosb		;; store a byte value
	ret

;; Here we process the aad and aam instructions.
;; They are special in that they may take a one-byte argument, or none
;; (in which case the argument defaults to 0ah = ten).
ab00:
	mov [mneminfo], SI	;; save this address
	pop SI
	lodsb
	cmp AL, CR
	je ab00a		;; if end of line
	cmp AL, ';'
	jne ab01b		;; if not end of line
ab00a:
	mov SI, offset BcdArg	;; fake a 0ah argument
	jmp ab01a

;; --- Process normal instructions.
;; First we parse each argument into a 12-byte data block (ArgT), stored consecutively at line_out, line_out+12, etc.
;; This is stored as follows.
;;	[DI]	Flags (ArgMx, etc.)
;;	[DI+1]	Unused
;;	[DI+2]	Size argument, if any (
;;			1=byte, 2=word, 3=(unused), 4=dword, 5=qword, 6=float,
;;			7=double, 8=tbyte, 9=short, 10=long, 11=near, 12=far
;		), see SIZ_xxx and sizetcnam
;;	[DI+3]	Size of XRM displacement
;;	[DI+4]	First register, or XRM byte, or the number of additional bytes
;;	[DI+5]	Second register or index register or SIB byte
;;	[DI+6]	Index factor
;;	[DI+7]	Sizes of numbers are or-ed here
;;	[DI+8]	(dword) number
;; For arguments of the form xxxx:yyyyyyyy, xxxx is stored in <Num2>, and yyyyyyyy in <Num>.
;; The number of bytes in yyyyyyyy is stored in opaddr, 2 is stored in <ExtraN>, and DI is stored in xxaddr.
ArgT struc
Flags	db ?	;; +0
	db ?
ArgN	db ?	;; +2
DispN	db ?	;; +3
union
Reg1	db ?	;; +4
ExtraN	db ?	;; +4 (additional bytes, stored at Num2 (up to 4)
ends
union
struct
Reg2	db ?	;; +5
Index	db ?	;; +6
ends
Num2	dw ?	;; +5
ends
OredN	db ?	;; +7
Num	dd ?	;; +8
ArgT ends

ab01:
	mov [mneminfo], SI	;; save this address
	pop SI			;; get position in line
ab01a:
	lodsb
ab01b:
	mov DI, offset line_out

;; --- Begin loop over operands.
ab02:		;; <--- next operand
	cmp AL, CR
	je ab03			;; if end of line
	cmp AL, ';'
	jne ab04		;; if not end of line
ab03:
	jmp ab99		;; to next phase

ab04:
	push DI			;; clear out the current ArgT storage area
	mov CX, sizeof ArgT/2
	xor AX, AX
	rep stosw
	pop DI

;; --- Small loop over "byte ptr" and segment prefixes.
ab05:
	dec SI
	mov AX, [SI]
	and AX, TOUPPER_W
	cmp [DI].ArgT.ArgN, SIZ_NONE
	jne ab07		;; if already have a size qualifier ("byte ptr", ...)
	push DI
	mov DI, offset sizetcnam
	mov CX, sizeof sizetcnam/2
	repne scasw
	pop DI
	jne ab07		;; if not found
	or CX, CX
	jnz @F			;; if not 'FA'
	mov AL, [SI+2]
	and AL, TOUPPER
	cmp AL, 'R'
	jne ab09		;; if not 'far' (could be hexadecimal)
@@:
	sub CL, sizeof sizetcnam/2
	neg CL			;; convert to 1, ..., 12
	mov [DI].ArgT.ArgN, CL
	call skipalpha	;; go to next token
	mov AH, [SI]
	and AX, TOUPPER_W
	cmp AX, 'TP'
	jne ab05		;; if not 'ptr'
	call skipalpha	;; go to next token
	jmp ab05

ab07:
	cmp [aa_seg_pre], 0
	jne ab09		;; if we already have a segment prefix
	push DI
	mov DI, offset RsName
	mov CX, NUM_Rss
	repne scasw
	pop DI
	jne ab09		;; if not found
	push SI			;; save SI in case there's no colon
	lodsw
	call skipwhite
	cmp AL, ':'
	jne ab08		;; if not followed by ':'
	pop AX			;; discard saved SI
	call skipwhite	;; skip it
	mov BX, offset prefixlist + 5
	sub BX, CX
	mov AL, [BX]		;; look up the prefix byte
	mov [aa_seg_pre], AL	;; save it away
	jmp ab05
ab08:
	pop SI

;; --- Begin parsing main part of argument.

;; --- first check registers
ab09:
	push DI			;; check for solo registers
	mov DI, offset RvName
	mov CX, NUM_Regs	;; 8+16bit regs, segment regs, special regs
	call aagetreg
	pop DI
	jc ab14			;; if not a register
	or [DI].ArgT.Flags, ArgRx
	mov [DI].ArgT.Reg1, BL	;; save register number
	cmp BL, 24		;; 0-23 = AL-DH, AX-DI, EAX-EDI (REG_NO_GPR)
	jae @F			;; if it's not a normal register
	xchg AX, BX		;; mov AL, BL
	mov CL, 3
	shr AL, CL		;; AL = size: 0 -> byte, 1 -> word, 2 -> dword
	add AL, -2
	adc AL, 3		;; convert to 1, 2, 4 (respectively)
	jmp ab13
@@:
	xor [DI].ArgT.Flags, ArgRx + ArgSx
	mov AL, SIZ_WORD	;; register size
	cmp BL, REG_ST
	ja ab11			;; if it's MM, CR, DR or TR
	je @F			;; if it's ST
	cmp BL, 28		;; 24-27 are ES, CS, SS, DS (RsName)
	jb ab13			;; if it's a normal segment register
	or [asm_mn_flags], AMF_FSGS	;; flag it
	jmp ab13
@@:
	cmp byte ptr [SI], '('
	jne ab12		;; if just plain ST
	lodsb
	lodsb
	sub AL, '0'
	cmp AL, 7
	ja ab10			;; if not 0..7
	mov [DI].ArgT.Reg2, AL	;; save the number
	lodsb
	cmp AL, ')'
	je ab12			;; if not error
ab10:
	jmp aa13b		;; error

;; --- other registers 31-34 (MM, CR, DR, TR)
ab11:
	lodsb
	sub AL, '0'
	cmp AL, 7
	ja ab10			;; if error
	mov [DI].ArgT.Reg2, AL	;; save the number
	mov AL, SIZ_DWORD	;; register size
	cmp BL, REG_MM
	jne ab13		;; if not MM register
	or [DI].ArgT.Flags, ArgRx
	mov AL, SIZ_QWORD
	jmp ab13
ab12:
	mov AL, 0		;; size for ST regs
ab13:
	cmp AL, [DI].ArgT.ArgN	;; compare with stated size
	je @F			;; if same
	xchg AL, [DI].ArgT.ArgN
	cmp AL, 0
	jne ab10		;; if wrong size given - error
@@:
	jmp ab44		;; done with this operand

;; --- It's not a register reference.
;; --- Try for a number.
ab14:
	lodsb
	call aaifnum
	jc ab17			;; it's not a number
	call aageti		;; get the number
	mov [DI].ArgT.OredN, CL
	mov word ptr [DI].ArgT.Num+0, BX
	mov word ptr [DI].ArgT.Num+2, DX
	call skipwh0
	cmp CL, 2
	jg ab17			;; if we can't have a colon here
	cmp AL, ':'
	jne ab17		;; if not xxxx:yyyy
	call skipwhite
	call aageti
	mov CX, word ptr [DI].ArgT.Num+0
	mov [DI].ArgT.Num2, CX
	mov word ptr [DI].ArgT.Num+0, BX
	mov word ptr [DI].ArgT.Num+2, DX
	or [DI].ArgT.Flags, ArgAf
	jmp ab43		;; done with this operand

;; --- Check for [...].
ab15:
	jmp ab30		;; do post-processing

ab16:
	call skipwhite
ab17:
	cmp AL, '['		;; begin loop over sets of []
	jne ab15		;; if not [
	or [DI].ArgT.Flags, ArgMx	;; set the flag
ab18:
	call skipwhite
ab19:
	cmp AL, ']'		;; begin loop within []
	je ab16			;; if done

;; --- Check for a register (within []).
	dec SI
	push DI
	mov DI, offset RwName
	mov CX, NUM_Rws
	call aagetreg
	pop DI
	jc ab25			;; if not a register
	cmp BL, 16
	jae @F			;; if 32-bit register
	add BL, 8		;; adjust 0..7 to 8..15
	jmp ab21
@@:
	cmp [DI].ArgT.Reg2, 0
	jnz ab21		;; if we already have an index
	call skipwhite
	dec SI
	cmp AL, '*'
	jne ab21		;; if not followed by '*'
	inc SI
	mov [DI].ArgT.Reg2, BL	;; save index register
	call skipwhite
	call aageti
	call aaconvindex
	jmp ab28		;; ready for next part

ab21:
	cmp [DI].ArgT.Reg1, 0
	jne @F			;; if there's already a register
	mov [DI].ArgT.Reg1, BL
	jmp ab23
@@:
	cmp [DI].ArgT.Reg2, 0
	jne ab24		;; if too many registers
	mov [DI].ArgT.Reg2, BL
ab23:
	call skipwhite
	jmp ab28		;; ready for next part
ab24:
	jmp aa13b		;; error

;; --- Try for a number (within []).
ab25:
	lodsb
ab26:
	call aageti		;; get a number (or flag an error)
	call skipwh0
	cmp AL, '*'
	je ab27			;; if it's an index factor
	or [DI].ArgT.OredN, CL
	add word ptr [DI].ArgT.Num+0, BX
	adc word ptr [DI].ArgT.Num+2, DX
	jmp ab28		;; next part ...

ab27:
	call aaconvindex
	call skipwhite
	dec SI
	push DI
	mov DI, offset RwName
	xor CX, CX
	call aagetreg
	pop DI
	jc ab24			;; if error
	cmp [DI].ArgT.Reg2, 0
	jne ab24		;; if there is already a register
	mov [DI].ArgT.Reg2, BL
	call skipwhite

;; --- Ready for the next term within [].
ab28:
	cmp AL, '-'
	je ab26			;; if a (negative) number is next
	cmp AL, '+'
	jne @F			;; if no next term (presumably)
	jmp ab18
@@:
	jmp ab19		;; back for more

;; --- Post-processing for complicated arguments.
ab30:
	cmp word ptr [DI].ArgT.Reg1, 0	;; check both Reg1+Reg2
	jnz ab32		;; if registers were given (==> create XRM)
	cmp [DI].ArgT.OredN, 0
	jz ab31			;; if nothing was given (==> error)
	cmp [DI].ArgT.Flags, 0
	jnz ab30b		;; if it was not immediate
	or [DI].ArgT.Flags, ArgIx
ab30a:
	jmp ab43		;; done with this argument
ab30b:
	or [asm_mn_flags], AMF_ADDR
	mov AL, 2		;; size of the displacement
	test [DI].ArgT.OredN, 4
	jz @F			;; if not 32-bit displacement
	inc AX
	inc AX
	or [asm_mn_flags], AMF_A32	;; 32-bit addressing
@@:
	mov [DI].ArgT.DispN, AL	;; save displacement size
	jmp ab30a		;; done with this argument
ab31:
	jmp aa13b		;; flag an error

;; Create the XRM byte.
;; (For disp-only or register, this will be done later as needed.)
ab32:
	or [DI].ArgT.Flags, ArgXRM
	mov AL, [DI].ArgT.Reg1
	or AL, [DI].ArgT.Reg2
	test AL, 16
	jnz ab34		;; if 32-bit addressing
	test [DI].ArgT.OredN, 4
	jnz ab34		;; if 32-bit addressing
;;	or [asm_mn_flags], AMF_ADDR | AMF_A32
	or [asm_mn_flags], AMF_ADDR
	mov AX, word ptr [DI].ArgT.Reg1	;; get Reg1+Reg2
	cmp AL, AH
	ja @F			;; make sure AL >= AH
	xchg AL, AH
@@:
	push DI
	mov DI, offset XrmTab
	mov CX, 8
	repne scasw
	pop DI
	jne ab31		;; if not among the possibilities
	mov BX, 206h		;; max disp = 2 bytes; 6 ==> (non-existent) [BP]
	jmp ab39		;; done (just about)

;; --- 32-bit addressing
ab34:
	or [asm_mn_flags], AMF_A32 + AMF_ADDR
	mov AL, [DI].ArgT.Reg1
	or AL, [DI].ArgT.Index
	jnz @F			;; if we can't optimize [EXX*1] to [EXX]
	mov AX, word ptr [DI].ArgT.Reg1	;; get Reg1+Reg2
	xchg AL, AH
	mov word ptr [DI].ArgT.Reg1, AX
@@:
	mov BX, 405h		;; max disp = 4 bytes; 5 ==> (non-existent) [BP]
	cmp [DI].ArgT.Reg2, 0
	jne @F			;; if there's a SIB
	mov CL, [DI].ArgT.Reg1
	cmp CL, 16
	jl ab31			;; if wrong register type
	and CL, 7
	cmp CL, 4		;; check for ESP
	jne ab39		;; if not, then we're done (otherwise do SIB)
@@:
	or [asm_mn_flags], AMF_SIB	;; form SIB
	mov CH, [DI].ArgT.Index		;; get SS bits
	mov CL, 3
	shl CH, CL			;; shift them halfway into place
	mov AL, [DI].ArgT.Reg2	;; index register
	cmp AL, 20
	je ab31			;; if ESP (==> error)
	cmp AL, 0
	jne @F			;; if not zero
	mov AL, 20		;; set it for index byte 4
@@:
	cmp AL, 16
	jl ab31			;; if wrong register type
	and AL, 7
	or CH, AL		;; put it into the SIB
	shl CH, CL		;; shift it into place
	inc CX			;; R/M for SIB = 4
	mov AL, [DI].ArgT.Reg1	;; now get the low 3 bits
	cmp AL, 0
	jne @F			;; if there was a first register
	or CH, 5
	jmp ab42		;; MOD = 0, disp is 4 bytes
@@:
	cmp AL, 16
	jl ab45			;; if wrong register type
	and AL, 7		;; first register
	or CH, AL		;; put it into the SIB
	cmp AL, 5
	je ab40			;; if it's EBP, then we don't recognize disp=0
				;; otherwise BL will be set to 0

;; --- Find the size of the displacement.
ab39:
	cmp CL, BL
	je ab40			;; if it's [(E)BP], then disp=0 is still 1 byte
	mov BL, 0		;; allow 0-byte disp

ab40:
	push CX
	mov AL, byte ptr [DI].ArgT.Num+0
	mov CL, 7
	sar AL, CL
	pop CX
	mov AH, byte ptr [DI].ArgT.Num+1
	cmp AL, AH
	jne @F			;; if it's bigger than 1 byte
	cmp AX, word ptr [DI].ArgT.Num+2
	jne @F			;; ditto
	mov BH, 0		;; no displacement
	or BL, byte ptr [DI].ArgT.Num+0
	jz ab42			;; if disp = 0 and it's not (E)BP
	inc BH			;; disp = 1 byte
	or CL, 40h		;; set MOD = 1
	jmp ab42		;; done
@@:
	or CL, 80h		;; set MOD = 2
ab42:
	mov [DI].ArgT.DispN, BH		;; store displacement size
	mov word ptr [DI].ArgT.Reg1, CX	;; store XRM and maybe SIB

;; --- Finish up with the operand.
ab43:
	dec SI
ab44:
	call skipwhite
	add DI, sizeof ArgT
	cmp AL, CR
	je ab99			;; if end of line
	cmp AL, ';'
	je ab99			;; if comment (ditto)
	cmp AL, ','
	jne ab45		;; if not comma (==> error)
	cmp DI, offset line_out + 3*sizeof ArgT
	jae ab45		;; if too many operands
	call skipwhite
	jmp ab02

ab45:
	jmp aa13b		;; error jump

ab99:
	mov [DI].ArgT.Flags, -1	;; end of parsing phase
	push SI			;; save the location of the end of the string

;; For the next phase, we match the parsed arguments with the set of permissible argument lists for the opcode.
;; The first match wins.
;; Therefore the argument lists should be ordered such that the cheaper ones come first.

;; There is a tricky issue regarding sizes of memory references.
;; Here are the rules:
;; 1.	If a memory reference is given with a size, then it's OK.
;; 2.	If a memory reference is given without a size, but some other argument is a register (which implies a size),
;;	then the memory reference inherits that size.
;;	Exceptions:	_CL does not imply a size
;;			_N
;; 3.	If 1 and 2 do not apply, but this is the last possible argument list,
;;	and if the argument list requires a particular size, then that size is used.
;; 4.	In all other cases, flag an error.
ac01:		;; <--- next possible argument list
	xor AX, AX
	mov DI, offset ai
	mov CX, sizeof ai/2
	rep stosw
	mov SI, [mneminfo]	;; address of the argument variant

;; --- Sort out initial bytes.
;; --- At this point:
;; --- SI = address of argument variant
ac02:		;; <--- next byte of argument variant
	lodsb
	sub AL, ASM_MACH0
	jb ac05			;; if no more special bytes
	cmp AL, ASM_LOCKABLE - ASM_MACH0
	je @F			;; if ASM_LOCKABLE
	ja ac04			;; if ASM_END (==> error)
	mov [ai.dismach], AL	;; save machine type
	jmp ac02		;; back for next byte
@@:
	or [ai.varflags], VAR_LOCKABLE
	jmp ac02		;; back for next byte

ac04:
	jmp aa13a		;; error

;; --- Get and unpack the word.
ac05:
	dec SI
	lodsw
	xchg AL, AH			;; put into little-endian order
	xor DX, DX
	mov BX, ASMMOD
	div BX				;; AX = a_opcode; DX = index into opindex
	mov [a_opcode], AX		;; save AX
	mov [a_opcode2], AX		;; save the second copy
	cmp AX, 0dfh
	ja @F				;; if not coprocessor instruction
	cmp AL, 0d8h
	jb @F				;; ditto
	or [ai.dmflags], DM_COPR	;; flag it as an x87 instruction
	mov AH, AL			;; AH = low order byte of opcode
	lodsb				;; get extra byte
	mov [ai.regmem], AL		;; save it in regmem
	mov [a_opcode2], AX		;; save this for obsolete-instruction detection
	or [ai.varflags], VAR_MODRM	;; flag its presence
@@:
	mov [mneminfo], SI		;; save SI back again
	mov SI, DX
	mov BL, [opindex+SI]
	lea SI, [oplists+BX]		;; SI = the address of our operand list
	mov DI, offset line_out		;; DI = array of ArgT

;; --- Begin loop over operands.
ac06:		;; <--- next operand
	lodsb			;; get next operand byte
	cmp AL, 0
	je ac10			;; if end of list
	cmp [DI].ArgT.Flags, -1
	je ac01			;; if too few operands were given
	cmp AL, OpLo
	jb @F			;; if no size needed
;;	mov AH, 0
;;	mov CL, 4
;;	shl AX, CL		;; move bits 4-7 (size) to AH (OpV=5, OpB=6, OpW=7, ...)
;;	shr AL, CL		;; move bits 0-3 back
	db 0d4h, 10h		;; =aam 10h (AX=00XY -> AX=0X0Y)
	mov [ai.reqsize], AH	;; save size away
	jmp ac08
@@:				;; AL = _Q - ...
	add AL, ASM_OPOFF - _Q	;; adjust for the start entries im AsmJump1
ac08:
	cbw
	xchg AX, BX		;; now BX contains the offset
	mov CX, [AsmJump1+BX]	;; subroutine address
	shr BX, 1
	mov AL, [BitTab+BX]
	test AL, [DI].ArgT.Flags
	jz ac09			;; if no required bits are present
	call CX			;; call its specific routine
	cmp word ptr [SI-1], (OpV+_R?)*256+(OpV+_X?)
	je ac06			;; (hack) for imul instruction
	add DI, sizeof ArgT	;; next operand
	jmp ac06		;; back for more

ac09:
	jmp ac01		;; back to next possibility

;; --- End of operand list.
ac10:
	cmp [DI].ArgT.Flags, -1
	jne ac09		;; if too many operands were given

;; --- Final check on sizes
	mov AL, [ai.varflags]
	test AL, VAR_SIZ_NEED
	jz ac12			;; if no size needed
	test AL, VAR_SIZ_GIVN
	jnz ac12		;; if a size was given
	test AL, VAR_SIZ_FORCD
	jz ac09			;; if the size was not forced (==> reject)
	mov SI, [mneminfo]
	cmp byte ptr [SI], ASM_END
	je ac12			;; if this is the last one
ac11:
	jmp aa13a		;; it was not ==> error (not a retry)

;; --- Check other prefixes.
ac12:
	mov AL, [aa_saved_prefix]
	cmp AL, 0
	jz ac14			;; if no saved prefixes to check
	cmp AL, 0f0h
	jne @F			;; if it's a rep prefix
	test [ai.varflags], VAR_LOCKABLE
	jz ac11			;; if this variant is not lockable - error
	jmp ac14		;; done
@@:
	mov AX, [a_opcode]	;; check if opcode is OK for rep{,z,nz}
	and AL, not 1		;; clear low order bit (movsw -> movsb)
	cmp AX, 0ffh
	ja ac11			;; if it's not a 1 byte instruction - error
	mov DI, offset replist	;; list of instructions that go with rep
	mov CX, N_REPALL	;; scan all (rep + repxx)
	repne scasb
	jnz ac11		;; if it's not among them - error

ac14:
	test [asm_mn_flags], AMF_MSEG
	jz @F			;; if no segment prefix before mnemonic
	mov AX, [a_opcode]	;; check if opcode allows this
	cmp AX, 0ffh
	ja ac11			;; if it's not a 1 byte instruction - error
	mov DI, offset prfxtab
	mov CX, P_LEN
	repne scasb
	jnz ac11		;; if it's not in the list - error
@@:
	mov BX, [ai.immaddr]
	or BX, BX
	jz ac16			;; if no immediate data
	mov AL, [ai.opsize]
	neg AL
	shl AL, 1
	test AL, [BX+7]
	jnz ac11		;; if the immediate data was too big - error

;; Put the instruction together (maybe is this why they call it an assembler).
;; First, the prefixes (including preceding wait instruction).
ac16:
	sizeprfX		;; mov EDX, [a_addr]
	mov DX, [a_addr+0]
	mov BX, [a_addr+4]
	test [asm_mn_flags], AMF_WAIT
	jz @F			;; if no wait instruction beforehand
	mov AL, 9bh
	call writeasm
@@:
	mov AL, [aa_saved_prefix]
	cmp AL, 0
	jz @F			;; if no lock or rep prefix
	call writeasm
@@:
;; --- a 67h address size prefix is needed
;; --- 1. for CS32: if AMF_ADDR=1 and AMF_A32=1
;; --- 2. for CS16: if AMF_ADDR=1 and AMF_A32=0
	mov AL, [asm_mn_flags]
	test AL, AMF_ADDR
	jz @F
	and AL, AMF_A32
if ?PM
	mov AH, [bCSAttr]
	and AH, 40h
	or AL, AH
endif
	and AL, AMF_A32 + 40h
	jz @F
	cmp AL, AMF_A32 + 40h
	jz @F
	mov AL, 67h
	call writeasm
@@:
;; --- a 66h data size prefix is needed
;; --- for CS16: if VAR_D32 == 1 or AMF_D32 == 1
;; --- for CS32: if VAR_D16 == 1 or AMF_D16 == 1
	mov AH, [asm_mn_flags]
	mov AL, [ai.varflags]
if ?PM
	test [bCSAttr], 40h
	jz @F
	test AL, VAR_D16
	jnz ac20_1
	test AH, AMF_D16
	jnz ac20_1
	jmp ac21
@@:
endif
	test AL, VAR_D32
	jnz ac20_1
	test AH, AMF_D32
	jz ac21
ac20_1:
	mov AL, 66h
	call writeasm			;; store operand-size prefix
ac21:
	mov AL, [aa_seg_pre]
	cmp AL, 0
	jz @F				;; if no segment prefix
	call writeasm
	cmp AL, 64h
	jb @F				;; if not 64 or 65 (FS or GS)
	or [asm_mn_flags], AMF_FSGS	;; flag it
@@:
;; --- Now emit the instruction itself.
	mov AX, [a_opcode]
	mov DI, AX
	sub DI, 240h
	jae @F			;; if 576-...
	cmp AX, 200h
	jb ac24			;; if regular instruction
	or [ai.dmflags], DM_COPR	;; flag it as an x87 instruction
	and AL, 038h		;; get register part
	or [ai.regmem], AL
	xchg AX, DI		;; mov AX, DI (the low bits of DI are good)
	and AL, 7
	or AL, 0d8h
	jmp ac25		;; on to decoding the instruction
@@:
	mov CL, 3		;; one instruction of a group
	shr DI, CL
	and AL, 7
	shl AL, CL
	or [ai.regmem], AL
	shl DI, 1
	mov AX, [agroups+DI]	;; get actual opcode

ac24:
	cmp AH, 0
	jz ac25			;; if no 0fh first
	push AX			;; store a 0fh
	mov AL, 0fh
	call writeasm
	pop AX

ac25:
	or AL, [ai.opcode_or]	;; put additional bits into the op code
	call writeasm		;; store the op code itself

;; --- Now store the extra stuff that comes with the instruction.
	mov AX, word ptr [ai.regmem]
	test [ai.varflags], VAR_MODRM
	jz @F			;; if no mod reg/mem
	push AX
	call writeasm
	pop AX
	test [asm_mn_flags], AMF_SIB
	jz @F			;; if no SIB
	mov AL, AH
	call writeasm		;; store the XRM and SIB, too
@@:
	mov DI, [ai.rmaddr]
	or DI, DI
	jz @F			;; if no offset associated with the R/M
	mov CL, [DI].ArgT.DispN
	mov CH, 0
	lea SI, [DI].ArgT.Num	;; store the R/M offset (or memory offset)
	call writeasmn
@@:
;; --- Now store immediate data
	mov DI, [ai.immaddr]
	or DI, DI
	jz @F			;; if no immediate data
	mov AL, [ai.opsize]
	cbw
	xchg AX, CX		;; mov CX, AX
	lea SI, [DI].ArgT.Num
	call writeasmn
@@:
;; --- Now store additional bytes (needed for, e.g., enter instruction) also for far memory address.
	mov DI, [ai.xxaddr]
	or DI, DI
	jz @F			;; if no additional data
	lea SI, [DI].ArgT.ExtraN	;; number of bytes (2 for far, size of segment)
	lodsb
	cbw
	xchg AX, CX		;; mov CX, AX
	call writeasmn
@@:
;; --- Done emitting. Update asm address offset.
	sizeprfX		;; mov [a_addr], EDX
	mov [a_addr], DX

;; --- Compute machine type.
	cmp [ai.dismach], 3
	jae ac31		;; if we already know a 386 is needed
	test [asm_mn_flags], AMF_D32 or AMF_A32 or AMF_FSGS
	jnz ac30		;; if 386
	test [ai.varflags], VAR_D32
	jz ac31			;; if not 386
ac30:
	mov [ai.dismach], 3
ac31:
	mov DI, offset OldOp	;; obsolete instruction table
	mov CX, [a_opcode2]
	call showmach		;; get machine message into SI, length into CX
	jcxz ac33		;; if no message

ac32:
	mov DI, offset line_out
	rep movsb		;; copy the line to line_out
	call putsline

ac33:
	jmp aa01		;; back for the next input line

if 0
;; --- This is debugging code.
;; --- It assumes that the original value of a_addr is on the top of the stack.
	pop SI		;; get orig. a_addr
	mov AX, [a_addr+4]
	mov [u_addr+0], SI
	mov [u_addr+4], AX
	mov BX, [a_addr]
	sub BX, SI
	mov DI, offset line_out
	mov CX, 10
	mov AL, ' '
	rep stosb
	mov DS, [a_addr+4]
@@:
	lodsb
	call hexbyte	;; display the bytes generated
	dec BX
	jnz @B
	push SS
	pop DS
	call putsline
	call disasm1	;; disassemble the new instruction
	jmp aa01	;; back to next input line
endif

CONST segment
	align 2
;; --- Jump table for operand types.
;; --- The entries in AsmJump1 must be in the same order as the corresponding ones in DisJump1/DisOpTab.
AsmJump1 label word
	dw AOpIx, AOpEx, AOpMx, AOpXx	;; _I?, _E?, _M?, _X?
	dw AOpAn, AOpRx, AOprx, AOpAx	;; _O?, _R?, _r?, _A?
ASM_OPOFF equ $ - AsmJump1
;; --- The order must match the one in DisOpTab.
	dw AOpRef, AOpRef, AOpRef	;; _Q, _MF, _MD
	dw AOpRef, AOpRef, AOpRef	;; _MLD, _Mx, _Mf
	dw AOpAf, AOpJb, AOpJv		;; _Af, _Jb, _Jv
	dw AOpST1, AOpSTi, AOpCRx	;; _ST1, _STi, _CRx
	dw AOpDRx, AOpTRx, AOpSx	;; _DRx, _TRx, _Rs
	dw AOpDs, AOpDb, AOpMMx		;; _Ds, _Db, _MMx
	dw AOpN, AOp1, AOp3		;; _N, _1, _3
	dw AOpReg, AOpReg, AOpReg	;; _DX, _CL, _ST
	dw AOpReg, AOpReg, AOpReg	;; _CS, _DS, _ES
	dw AOpReg, AOpReg, AOpReg	;; _FS, _GS, _SS
CONST ends

;; Routines to check for specific operand types.
;; Upon success, the routine returns.
;; Upon failure, it pops the return address and jumps to ac01.
;; The routines must preserve SI and DI.

;; --- _E?, _M?, _X?: form XRM byte.
AOpEx:
AOpMx:
AOpXx:
	call ao90		;; form reg/mem byte
	jmp ao07		;; go to the size check

;; --- _R?: register.
AOpRx:
	mov AL, [DI].ArgT.Reg1	;; register number
	and AL, 7
	mov CL, 3
	shl AL, CL		;; shift it into place
	or [ai.regmem], AL	;; put it into the reg/mem byte
	jmp ao07		;; go to the size check

;; --- _r?: register, added to the instruction.
AOprx:
	mov AL, [DI].ArgT.Reg1
	and AL, 7
	mov [ai.opcode_or], AL	;; put it there
	jmp ao07		;; go to the size check

;; --- _I?: immediate data.
AOpIx:
	mov [ai.immaddr], DI	;; save the location of this
	jmp ao07		;; go to the size check

;; --- _O?: just the memory offset
AOpAn:
	test [DI].ArgT.Flags, ArgXRM
	jnz ao11		;; if XRM byte (==> reject)
	mov [ai.rmaddr], DI	;; save the operand pointer
	jmp ao07		;; go to the size check

;; --- _A?: check for AL/AX/EAX
AOpAx:
	test [DI].ArgT.Reg1, 7
	jnz ao11		;; if wrong register
;;	jmp ao07		;; go to the size check

;; --- Size check
ao07:		;; <--- entry for _E?, _M?, _X?, _R?, _r?...
	or [ai.varflags], VAR_SIZ_NEED
	mov AL, [ai.reqsize]
	sub AL, 5		;; OpV >> 4
	jl AOpX			;; if OpX
	jz AOpV			;; if OpV
;; --- OpB=1, OpW=2, OpD=3, OpQ=4
	add AL, -3
	adc AL, 3		;; convert 3 --> 4 and 4 --> 5
ao08:		;; <--- entry for _Q ... _Mf
	or [ai.varflags], VAR_SIZ_FORCD + VAR_SIZ_NEED
ao08_1:
	mov BL, [DI].ArgT.ArgN
	or BL, BL
	jz @F			;; if no size given
	or [ai.varflags], VAR_SIZ_GIVN
	cmp AL, BL
	jne ao11		;; if sizes conflict
@@:
	cmp AL, [ai.opsize]
	je @F			;; if sizes agree
	xchg AL, [ai.opsize]
	cmp AL, 0
	jnz ao11		;; if sizes disagree
	or [ai.varflags], VAR_SIZ_GIVN	;; v1.18 added!!!
@@:
	ret

ao11:
	jmp ao50		;; reject

;; --- OpX - Allow all sizes.
AOpX:
	mov AL, [DI].ArgT.ArgN
	cmp AL, SIZ_BYTE
	je ao15			;; if byte
	jb ao14			;; if unknown
	or [ai.opcode_or], 1	;; set bit in instruction
	jmp ao14		;; if size is 16 or 32

;; --- OpV - word or dword.
AOpV:
	mov AL, [DI].ArgT.ArgN
ao14:
	cmp AL, SIZ_NONE
	je ao16			;; if still unknown
	cmp AL, SIZ_WORD
	jne @F			;; if word
	or [ai.varflags], VAR_D16
	jmp ao15
@@:
	cmp AL, SIZ_DWORD
	jne ao11		;; if not dword
	or [ai.varflags], VAR_D32
ao15:
	mov [ai.opsize], AL
	or [ai.varflags], VAR_SIZ_GIVN
ao16:
	ret

;; _Q	― 64-bit memory reference.
;; _MF	― single-precision floating point memory reference.
;; _MD	― double-precision floating point memory reference.
;; _MLD	― 80-bit memory reference.
;; _Mx	― memory reference, size unknown.
;; _Mf	― far memory pointer
;; --- BX contains byte index for BitTab
AOpRef:
	call ao90		;; form reg/mem byte
	mov AL, [AsmSizeNum+BX-ASM_OPOFF/2]
	jmp ao08		;; check size

;; --- _Af - far address contained in instruction
AOpAf:
	mov AL, 2
if ?PM
	test [bCSAttr], 40h
	jnz @F
endif
	cmp word ptr [DI].ArgT.Num+2, 0
	jz ao22			;; if 16 bit address
@@:
	or [ai.varflags], VAR_D32
	mov AL, 4
ao22:
	mov [DI].ArgT.ExtraN, 2	;; 2 additional bytes (segment part)
	mov [ai.immaddr], DI
	mov [ai.opsize], AL	;; 2/4, size of offset
ao22_1:
	mov [ai.xxaddr], DI
	ret

;; --- _Jb - relative address
;; --- jcc, loopx, jxcxz
AOpJb:
	mov AL, SIZ_SHORT
	call aasizchk		;; check the size
	mov CX, 2		;; size of instruction
	mov AL, [asm_mn_flags]

	test AL, AMF_D32 or AMF_D16
	jz ao23_1		;; if not jxcxz, loopx
	test AL, AMF_D32
	jz @F
	or AL, AMF_A32		;; jxcxz and loopx need a 67h, not a 66h prefix
@@:
	and AL, not (AMF_D32 or AMF_D16)
	or AL, AMF_ADDR
	mov [asm_mn_flags], AL
if ?PM
	mov AH, [bCSAttr]
	and AH, 40h
else
	mov AH, 0
endif
	and AL, AMF_A32
	or AL, AH
	jz ao23_1
	cmp AL, AMF_A32+40h
	jz ao23_1
	inc CX			;; instruction size = 3
ao23_1:
	mov BX, [a_addr+0]
	add BX, CX
	mov CX, [a_addr+2]	;; v1.22: handle HiWord(EIP) properly
	adc CX, 0
	mov AX, word ptr [DI].ArgT.Num+0
	mov DX, word ptr [DI].ArgT.Num+2
;; --- CX:BX holds E/IP (=src), DX:AX holds dst
	sub AX, BX
	sbb DX, CX
	mov byte ptr [DI].ArgT.Num2, AL
	mov CL, 7		;; range must be ffffff80 <= x <= 0000007f
	sar AL, CL		;; 1xxxxxxxb -> ff, 0xxxxxxxb -> 00
	cmp AL, AH
	jne ao_err1		;; if too big
	cmp AX, DX
	jne ao_err1		;; if too big
	mov [DI].ArgT.ExtraN, 1	;; save the length
	jmp ao22_1		;; save it away

;; --- _Jv: relative jump/call to a longer address.
;; --- size of instruction is
;; --- a) CS 16-bit:
;; ---	3 (xx xxxx, jmp/call) or
;; ---	4 (0f xx xxxx)
;; ---	6 (66 xx xxxxxxxx)
;; ---	7 (66 0f xx xxxxxxxx)
;; --- b) CS 32-bit:
;; ---	5 (xx xxxxxxxx, jmp/call) or
;; ---	6 (0f xx xxxxxxxx)
AOpJv:
	mov BX, [a_addr+0]
	mov CX, 3
	mov DX, word ptr [DI].ArgT.Num+2
	mov AL, [DI].ArgT.ArgN
	cmp [a_opcode], 100h	;; is a 0f xx opcode?
	jb @F
	inc CX
@@:
	cmp AL, SIZ_NONE
	je @F			;; if no size given
	cmp AL, SIZ_DWORD
	je ao27			;; if size "dword"
	cmp AL, SIZ_LONG
	jne ao_err1		;; if not size "long"
@@:
if ?PM
	test [bCSAttr], 40h
	jnz ao27
endif
	or DX, DX
	jnz ao_err1		;; if operand is too big
	mov AL, 2		;; displacement size 2
	jmp ao28
ao27:
	mov AL, 4		;; displacement size 4
	or [ai.varflags], VAR_D32
	add CX, 3		;; add 3 to instr size (+2 for displ, +1 for 66h)
if ?PM
	test [bCSAttr], 40h
	jz @F
	dec CX			;; no 66h prefix byte in 32-bit code
@@:
endif
ao28:
	add BX, CX
	mov CX, [a_addr+2]
	adc CX, 0
	mov [DI].ArgT.ExtraN, AL	;; store size of displacement (2 or 4)
	mov AX, word ptr [DI].ArgT.Num+0
	sub AX, BX		;; compute DX:AX - CX:BX
	sbb DX, CX
	mov [DI].ArgT.Num2, AX
	mov [DI].ArgT.Num2+2, DX
	mov [ai.xxaddr], DI
	ret
ao_err1:
	jmp ao50		;; reject

;; --- _ST1 - The assembler can ignore this one.
AOpST1:
	pop AX			;; discard return address
	jmp ac06		;; next operand

;; --- _STi - ST(I).
AOpSTi:
	mov AL, REG_ST		;; code for ST
	mov BL, [DI].ArgT.Reg2
	jmp ao38		;; to common code

;; --- _MMx [previously was OP_ECX (used for loopx)]
AOpMMx:
	mov AL, REG_MM
	jmp ao37		;; to common code

;; --- _CRx
AOpCRx:
	mov AL, [DI].ArgT.Reg2	;; get the index
	cmp AL, 4
	ja ao_err1		;; if too big
	jne @F			;; if not CR4
	mov [ai.dismach], 5	;; CR4 is new to the 586
@@:
	cmp AL, 1
	jne @F
	cmp [DI+sizeof ArgT].ArgT.Flags, -1
	jne ao_err1		;; if another arg (can't mov CR1, xx)
@@:
	mov AL, REG_CR		;; code for CR
	jmp ao37		;; to common code

;; --- _DRx
AOpDRx:
	mov AL, REG_DR		;; code for DR
	jmp ao37		;; to common code

;; --- _TRx
AOpTRx:
	mov AL, [DI].ArgT.Reg2	;; get the index
	cmp AL, 3
	jb ao_err1		;; if too small
	cmp AL, 6
	jae @F
	mov [ai.dismach], 4	;; TR3-5 are new to the 486
@@:
	mov AL, REG_TR		;; code for TR

;; --- Common code for these weird registers.
ao37:
	mov BL, [DI].ArgT.Reg2
	mov CL, 3
	shl BL, CL
ao38:
	or [ai.regmem], BL
	or [ai.varflags], VAR_MODRM
	cmp AL, [DI].ArgT.Reg1	;; check for the right numbered register
	je ao40			;; if yes, then return
ao38a:
	jmp ao50		;; reject

;; --- _Rs
AOpSx:
	mov AL, [DI].ArgT.Reg1
	sub AL, 24
	cmp AL, 6
	jae ao38a		;; if not a segment register
	mov CL, 3
	shl AL, CL
	or [ai.regmem], AL
;; --- v1.26: don't force size for mov sreg, mxx / mov mxx, sreg
	or [ai.varflags], VAR_SIZ_GIVN
ao40:
	ret

;; --- _Ds - Sign-extended immediate byte (push xx)
AOpDs:
	and [ai.varflags], not VAR_SIZ_NEED	;; added for v1.09. Ok?
	mov AX, word ptr [DI].ArgT.Num+0
	mov CL, 7
	sar AL, CL
	jmp ao43		;; common code

;; --- _Db - Immediate byte
AOpDb:
	mov AX, word ptr [DI].ArgT.Num+0
	mov AL, 0
ao43:
	cmp AL, AH
	jne ao50		;; if too big
	cmp AX, word ptr [DI].ArgT.Num+2
	jne ao50		;; if too big
	mov AL, SIZ_BYTE
	call aasizchk	;; check that size == 0 or 1
	mov AH, byte ptr [DI].ArgT.Num+0
	mov word ptr [DI].ArgT.ExtraN, AX	;; store length (0/1) + the byte
	mov [ai.xxaddr], DI
ao43r:
	ret

;; --- _N - force the user to declare the size of the next operand
AOpN:
	test [ai.varflags], VAR_SIZ_NEED
	jz ao45			;; if no testing needs to be done
	test [ai.varflags], VAR_SIZ_GIVN
	jz ao50			;; if size was given (==> reject)
ao45:
	and [ai.varflags], not VAR_SIZ_GIVN	;; clear the flag
	cmp byte ptr [SI], _Db
	je ao45a		;; if _Db is next, then don't set VAR_SIZ_NEED
	or [ai.varflags], VAR_SIZ_NEED
ao45a:
	mov byte ptr [ai.opsize], 0
	pop AX			;; discard return address
	jmp ac06		;; next operand

;; --- _1
AOp1:
	cmp word ptr [DI+7], 101h	;; check both size and value
	jmp ao49			;; test it later

;; --- _3
AOp3:
	cmp word ptr [DI+7], 301h	;; check both size and value
	jmp ao49			;; test it later

;; --- _DX, _CL, _ST, _CS/_DS/_ES/_FS/_GS/_SS
;; --- BX contains index for BitTab
AOpReg:
	mov AL, [asm_regnum+BX-(ASM_OPOFF + _DX - _Q)/2]
	cbw
	cmp AX, word ptr [DI].ArgT.Reg1

ao49:
	je ao51

;; --- Reject this operand list.
ao50:
	pop AX			;; discard return address
	jmp ac01		;; go back to try the next alternative

ao51:
	ret

;; AASIZCHK - Check that the size given is 0 or AL.
aasizchk:
	cmp [DI].ArgT.ArgN, SIZ_NONE
	je ao51
	cmp [DI].ArgT.ArgN, AL
	je ao51
	pop AX		;; discard return address
	jmp ao50
a_cmd endp

;; --- Do reg/mem processing.
;; --- in: DI->ArgT
;; --- Uses AX
ao90 proc
	test [DI].ArgT.Flags, ArgRx
	jnz ao92		;; if just register
	test [DI].ArgT.Flags, ArgXRM
	jz @F			;; if no precomputed XRM byte
	mov AX, word ptr [DI].ArgT.Reg1	;; get the precomputed bytes
	jmp ao93		;; done
@@:
	mov AL, 6		;; convert plain displacement to XRM
	test [asm_mn_flags], AMF_A32
	jz ao93			;; if 16 bit addressing
	dec AX
	jmp ao93		;; done

ao92:
	mov AL, [DI].ArgT.Reg1	;; convert register to XRM
if 1
	cmp AL, REG_MM
	jnz @F
	mov AL, [DI].ArgT.Reg2
@@:
endif
	and AL, 7		;; get low 3 bits
	or AL, 0c0h

ao93:
	or word ptr [ai.regmem], AX	;; store the XRM and SIB
	or [ai.varflags], VAR_MODRM	;; flag its presence
	mov [ai.rmaddr], DI		;; save a pointer
	ret				;; done
ao90 endp

;; AAIFNUM - Determine if there's a number next.
;;	Entry	AL	First character of number
;;		SI	Address of next character of number
;;	Exit	CY	Clear if there's a number, set otherwise.
;;	Uses	None.
aaifnum proc
	cmp AL, '-'
	je aai2			;; if minus sign (carry is clear)
	push AX
	sub AL, '0'
	cmp AL, 10
	pop AX
	jb aai1			;; if a digit
	push AX
	and AL, TOUPPER
	sub AL, 'A'
	cmp AL, 6
	pop AX
aai1:
	cmc			;; carry clear <==> it's a number
aai2:
	ret
aaifnum endp

;; AAGETI - Get a number from the input line.
;;	Entry	AL	First character of number
;;		SI	Address of next character of number
;;	Exit	DX:BX	Resulting number
;;		CL	1 if it's a byte ptr, 2 if a word, 4 if a dword
;;		AL	Next character not in number
;;		SI	Address of next character after that
;;	Uses	AH, CH
aageti proc
	cmp AL, '-'
	je aag1			;; if negative
	call aag4		;; get the bare number
	mov CX, 1		;; set up CX
	or DX, DX
	jnz aag2		;; if dword
	or BH, BH
	jnz aag3		;; if word
	ret			;; it's a byte

aag1:
	lodsb
	call aag4		;; get the bare number
	mov CX, BX
	or CX, DX
	mov CX, 1
	jz aag1a		;; if -0
	not DX			;; negate the answer
	neg BX
	cmc
	adc DX, 0
	test DH, 80h
	jz aag7			;; if error
	cmp DX, -1
	jne aag2		;; if dword
	test BH, 80h
	jz aag2			;; if dword
	cmp BH, -1
	jne aag3		;; if word
	test BL, 80h
	jz aag3			;; if word
aag1a:
	ret			;; it's a byte

aag2:
	inc CX			;; return: it's a dword
	inc CX
aag3:
	inc CX			;; return: it's a word
	ret

aag4:
	xor BX, BX		;; get the basic integer
	xor DX, DX
	call getnyb
	jc aag7			;; if not a hex digit
aag5:
	or BL, AL		;; add it to the number
	lodsb
	call getnyb
	jc aag1a		;; if done
	test DH, 0f0h
	jnz aag7		;; if overflow
	mov CX, 4
aag6:
	shl BX, 1		;; shift it by 4
	rcl DX, 1
	loop aag6
	jmp aag5

aag7:
	jmp cmd_error		;; error
aageti endp

;; AACONVINDEX - Convert results from AAGETI and store index value
;;	Entry	DX:BX, CL	As in exit from AAGETI
;;		DI		Points to information record for this arg
;;	Exit	SS bits stored in [DI].ArgT.Index
;;	Uses	DL
aaconvindex proc
	cmp CL, 1
	jne aacv1		;; if the number is too large
	cmp BL, 1
	je aacv2		;; if 1
	inc DX
	cmp BL, 2
	je aacv2		;; if 2
	inc DX
	cmp BL, 4
	je aacv2		;; if 4
	inc DX
	cmp BL, 8
	je aacv2		;; if 8
aacv1:
	jmp cmd_error	;; error

aacv2:
	mov [DI].ArgT.Index, DL	;; save the value
	ret
aaconvindex endp

;; AAGETREG - Get register for the assembler.
;;	Entry	DI	Start of register table
;;		CX	Length of register table (or 0)
;;		SI	Address of first character in register name
;;	Exit	NC	if a register was found
;;		SI	Updated if a register was found
;;		BX	Register number, defined as in the table below.
;;	Uses	AX, CX, DI
;;
;;	Exit value of BX:
;;	DI = RvName, CX = 27	DI = RwName, CX = 8
;;	--------------------	-------------------
;;	00 .. 07: AL .. BH	00 .. 07: AX .. DI
;;	08 .. 15: AX .. DI	16 .. 23: EAX..EDI
;;	16 .. 23: EAX..EDI
;;	24 .. 29: ES .. GS
;;	30 .. 34: ST .. TR
aagetreg proc
	mov AX, [SI]
	and AX, TOUPPER_W	;; convert to upper case
	cmp AL, 'E'		;; check for EAX, etc.
	jne aagr1		;; if not
	push AX
	mov AL, AH
	mov AH, [SI+2]
	and AH, TOUPPER
	push DI
	mov DI, offset RwName
	push CX
	mov CX, NUM_Rws
	repne scasw
	mov BX, CX
	pop CX
	pop DI
	pop AX
	jne aagr1		;; if no match
	inc SI
	not BX
	add BL, 8+16		;; adjust BX
	jmp aagr2		;; finish up

aagr1:
	mov BX, CX		;; (if CX = 0, this is always reached with
	repne scasw		;; ZF clear)
	jne aagr3		;; if no match
	sub BX, CX
	dec BX
	cmp BL, 16
	jb aagr2		;; if AL .. BH or AX .. DI
	add BL, 8
aagr2:
	inc SI			;; skip the register name
	inc SI
	clc
	ret
aagr3:
	stc			;; not found
	ret
aagetreg endp

;; --- C command - compare bytes.
c_cmd proc
	call parsecm		;; parse arguments (sets DS:E/SI, ES:E/DI, E/CX)
;; --- note: DS unknown here
if ?PM
	cmp CS:[bAddr32], 0
	jz $+3
	db 66h	;; inc ECX
endif
	inc CX
cc1:		;; <--- continue compare
if INT2324
	push DS
	push SS		;; DS=DGROUP
	pop DS
	call dohack	;; set debuggee's int 23/24
	pop DS
endif
if ?PM
	cmp CS:[bAddr32], 0
	jz $+3
	db 67h	;; repe cmpsb DS:[ESI], ES:[EDI]
endif
	repe cmpsb
	lahf

;; --- v2.0: "mov DL, [SI-1]" and "mov DL, [ESI-1]" differ not just in the prefix!
;; --- mov DL, [SI-1]:	8a 54 ff
;; --- mov DL, [ESI-1]:	67 8a 56 ff
if ?PM
	cmp CS:[bAddr32], 0
	jz @F
	.386
	mov DL, [ESI-1]
	mov DH, ES:[EDI-1]
	.8086
	jmp c_cont
@@:
endif
	mov DL, [SI-1]	;; save the possibly errant characters
	mov DH, ES:[DI-1]
c_cont:
if INT2324
	push DS
	push SS
	pop DS
	call unhack	;; set debugger's int 23/24
	pop DS
endif
	sahf
	jne @F
	jmp cc2		;; if we're done
@@:
	push CX
	push ES

;; --- set ES to dgroup (needed for output routines)
	@RestoreSeg ES
	sizeprfX	;; mov EBX, EDI
	mov BX, DI	;; save [E]DI
	mov DI, offset line_out
	mov AX, DS
	call hexword
	mov AL, ':'
	stosb
if ?PM
	mov BP, offset hexword
	sizeprf		;; dec ESI
	dec SI
	sizeprf		;; mov EAX, ESI
	mov AX, SI
	sizeprf		;; inc ESI
	inc SI
	cmp CS:[bAddr32], 0
	jz @F
	mov BP, offset hexdword
@@:
	call BP
else
	lea AX, [SI-1]
	call hexword
endif
	mov AX, '  '
	stosw
	mov AL, DL
	call hexbyte
	mov AX, '  '
	stosw
	mov AL, DH
	call hexbyte
	mov AX, '  '
	stosw
	pop AX
	push AX
	call hexword
	mov AL, ':'
	stosb
if ?PM
	sizeprf		;; dec EBX
	dec BX
	sizeprf		;; mov EAX, EBX
	mov AX, BX
	sizeprf		;; inc EBX
	inc BX
	call BP
else
	lea AX, [BX-1]
	call hexword
endif

	push DS
;; --- set DS to dgroup
	@RestoreSeg DS
	push BX
	call putsline
	pop DI
	pop DS

	pop ES
	pop CX
if ?PM
	cmp CS:[bAddr32], 0
	jz $+3
	db 67h	;; jecxz cc2
endif
	jcxz cc2
	jmp cc1		;; if not done yet
cc2:
	@RestoreSeg DS
	push DS
	pop ES
	ret
c_cmd endp

if DPCMD
;; --- DP disk - display partition table of a fixed disk
dp_cmd proc
	call skipwhite
	call getbyte		;; get byte into DL
	call chkeol		;; expect end of line here
	mov BP, SP
	mov AL, DL
	mov DX, offset szNoHD
	and AL, AL
	jns error
	sub SP, 512
	mov word ptr packet.secno+0, 0
	mov word ptr packet.secno+2, 0
	mov packet.numsecs, 1
	mov packet.dstofs, SP
	mov packet.dstseg, DS
	call readsect
	jc error
	add SP, 1beh	;; offset PT
	mov SI, SP
	mov CX, 4
nextp:
	push CX
	mov DI, offset line_out
	mov AX, ' 4'
	sub AL, CL
	stosw
	mov AL, [SI+4]	;; partition type
	call hexbyte
	mov AL, ' '
	stosb
	mov AX, [SI+10]	;; hiword start LBA
	call hexword
	mov AX, [SI+8]	;; loword start LBA
	call hexword
	mov AL, ' '
	stosb
	mov AX, [SI+14]	;; hiword size LBA
	call hexword
	mov AX, [SI+12]	;; loword size LBA
	call hexword
	call putsline
	pop CX
	add SI, 16
	loop nextp
	mov SP, BP
	ret
error:
	mov SP, BP
	call int21ah9
	ret
dp_cmd endp
endif

if RING0
;; --- get base of descriptor table for selector in BX
;; --- out: EAX=base, DX=limit, C if error
getlinearbase proc
	.386
if FLATSS
	sub ESP, 6
	sgdt [ESP]
else
	push BP
	mov BP, SP
	sub SP, 6
	sgdt [BP-6]
endif
;;	mov DX, [BP-6]
;;	mov EAX, [BP-4]	;; get linear address GDT
	pop DX
	pop EAX
	test BL, 4
	jz exit
	sldt DX
	and DX, DX	;; any LDT?
	stc
	jz exit
	movzx EDX, DX
	add EAX, EDX	;; now EAX -> LDT descriptor
	push DS
	mov DS, [wFlat]
	mov DL, [EAX+4]
	mov DH, [EAX+7]
	shl EDX, 16
	mov DX, [EAX+2]
	push word ptr [EAX+0]
	mov EAX, EDX
	pop DX
	pop DS
	clc
exit:
ife FLATSS
	pop BP
endif
	ret
getlinearbase endp
endif

if DGCMD or DLCMD
 if RING0
CONST segment
szldtr db "LDTR=", 0
szgdtr db "GDTR=", 0
CONST ends
 endif

;; --- DG/DL commands
;; --- AL = 'l' or 'g'
CONST segment
descbase db ' base=???????? limit=???????? attr=????', 0
CONST ends

dgl_cmd proc
	push AX
	call skipwhite
	call getword	;; get word into DX
	pop CX
	mov BX, DX

	and BL, 0f8h
 if DGCMD
	cmp CL, 'g'
	jz @F
 endif
	or BL, 4
@@:
	call skipcomm0
	mov DX, 1
	cmp AL, CR
	jz @F
	call getword
	call chkeol
	and DX, DX
	jnz @F
	inc DX
@@:
	mov SI, DX		;; save count
if RING0
 if FLATSS
	mov EBP, ESP
 else
	mov BP, SP
 endif
	call getlinearbase		;; get base, limit
	.386
	push EAX
	push DX
	pushf
	push SI
	test BL, 4
	jz @F
	mov SI, offset szldtr
	call copystring
	sldt AX
	call hexword
	jmp ldtrdone
@@:
	mov SI, offset szgdtr
	call copystring
 if FLATSS
	mov AX, [EBP-6]
 else
	mov AX, [BP-6]
 endif
	call hexword
	mov AL, '.'
	stosb
 if FLATSS
	mov EAX, [EBP-4]
 else
	mov EAX, [BP-4]
 endif
	call hexdword
ldtrdone:
	call putsline
	pop SI
	popf
	jc done
endif
if _PM
	.286
	call ispm_dbg
	jnz nextdesc
	mov SI, offset nodesc	;; error "not accessible in real-mode"
	call copystring
	jmp putsline
endif

nextdesc:
	mov DI, offset line_out
	mov AX, BX
	call hexword
	push SI
	push DI
	mov SI, offset descbase
	call copystring
	pop DI
	pop SI
;;	lar AX, BX
;;	jnz skipdesc	;; tell that this descriptor is invalid
 if _PM
	mov AX, 6
	int 31h
	jc @F
 elseif RING0
	.386
  if FLATSS
	cmp BX, [EBP-6]	;; beyond limit?
  else
	cmp BX, [BP-6]	;; beyond limit?
  endif
	jae nogdt
	push DS
	movzx EAX, BX
	and AL, 0f8h
  if FLATSS
	add EAX, [EBP-4]
  else
	add EAX, [BP-4]
  endif
	mov DS, [wFlat]
	mov DX, [EAX+2]
	mov CL, [EAX+4]
	mov CH, [EAX+7]
	.286
	pop DS
	stc
nogdt:
	jnc done
	lar AX, BX
	jnz desc_out
 endif
	add DI, 6	;; render base
	mov AX, CX
	call hexword
	mov AX, DX
	call hexword
@@:
	sizeprf		;; lsl EAX, EBX
	lsl AX, BX
	jnz desc_out
	sizeprf		;; lar EDX, EBX
	lar DX, BX
	sizeprf		;; shr EDX, 8
	shr DX, 8
	mov DI, offset line_out+25
	cmp [machine], 3
	jb @F
	call hexdword	;; limit 32-bit
	jmp desc_o2
@@:
	call hexword	;; limit 16-bit
	mov AX, "  "
	stosw
	stosw
desc_o2:
	mov DI, offset line_out+25+14
	mov AX, DX
	call hexword	;; attr
desc_out:
	mov DI, offset line_out+25+14+4	;; position to end of line
	call putsline	;; add cr/lf, then print
	add BX, 8
	dec SI
	jnz nextdesc
done:
if RING0
 if FLATSS
	.386
	mov ESP, EBP
 else
	mov SP, BP
 endif
endif
	ret
dgl_cmd endp
endif

if DICMD
 if RING0
CONST segment
szidtr db "IDTR=", 0
CONST ends
 endif

;; --- DI command
di_cmd proc
	call skipwhite
	call getbyte	;; get byte into DL
	mov BX, DX
	call skipcomm0
	mov DX, 1
	cmp AL, CR
	jz @F
	call getword	;; get word into DL (max is 100h)
	call chkeol
	and DX, DX
	jnz @F
	inc DX			;; ensure that count is > 0
@@:
	mov SI, DX		;; save count
if RING0
 if FLATSS
	push EBP
	mov EBP, ESP
	sub ESP, 6
	sidt [EBP-6]
 else
	push BP
	mov BP, SP
	sub SP, 6
	sidt [BP-6]
 endif
	push SI
	mov SI, offset szidtr
	call copystring
	pop SI
 if FLATSS
	mov AX, [EBP-6]
 else
	mov AX, [BP-6]
 endif
	call hexword
	mov AL, '.'
	stosb
	.386
 if FLATSS
	mov EAX, [EBP-4]
 else
	mov EAX, [BP-4]
 endif
	call hexdword
	call putsline
endif
	call prephack
gateout_00:		;; <--- next int/exc
	mov DI, offset line_out
	mov AL, BL
	call hexbyte
	mov AL, ' '
	stosb
if ?PM
 if _PM
	call ispm_dbe
	jz gaterm
	.286
	mov AX, 204h
	cmp BL, 20h
	adc BH, 1
gateout_01:
	int 31h
	jc gatefailed
	mov AX, CX
	call hexword
	mov AL, ':'
	stosb
	cmp [dpmi32], 0
	jz gate16
	.386
	shld EAX, EDX, 16
	call hexword
	.8086
gate16:
	mov AX, DX
	call hexword
	mov AL, ' '
	stosb
	mov AX, 0202h
	dec BH
	jnz gateout_01
 else
	.386
	push BX
	movzx EBX, BL
 if LMODE
	shl BX, 4
 else
	shl BX, 3
 endif
 if FLATSS
	cmp BX, [EBP-6]
 else
	cmp BX, [BP-6]
 endif
	ja di_done
 if FLATSS
	add EBX, [EBP-4]
 else
	add EBX, [BP-4]
 endif
	push DS
	mov DS, [wFlat]
	mov AX, [EBX+2]
	call hexword
	mov AL, ':'
	stosb
	mov AX, [EBX+6]
	call hexword
	mov AX, [EBX+0]
	call hexword
	mov EAX, '=ta '
	stosd
	mov AX, [EBX+4]
	call hexword
	.8086
	pop DS
	pop BX
 endif
else
	jmp gaterm
endif
gate_exit:
	call putsline
	inc BL
	jz di_done
	dec SI
	jnz gateout_00
di_done:
if RING0
 if FLATSS
	.386
	mov ESP, EBP
	pop EBP
 else
	mov SP, BP
	pop BP
 endif
endif
	ret
if _PM
gatefailed:
	mov DI, offset line_out
	mov SI, offset gatewrong
	call copystring
	mov SI, 1
	jmp gate_exit
endif
gaterm:
	call dohack		;; set debuggee's int 23/24
	mov CL, 2
	push BX
	shl BX, CL
	push DS
	xor AX, AX
	mov DS, AX
	mov AX, [BX+2]
	mov DX, [BX+0]
	pop DS
	pop BX
	call unhack		;; set debugger's int 23/24
	call hexword
	mov AL, ':'
	stosb
	mov AX, DX
	call hexword
	jmp gate_exit
di_cmd endp
endif

	.8086
if DMCMD
mcbout proc
;;	mov DI, offset line_out
	mov AX, "SP"
	stosw
	mov AX, ":P"
	stosw
	mov AX, [pspdbe]
	call hexword
	call putsline	;; destroys CX, DX, BX

	mov SI, [wMCB]
nextmcb:
	mov DI, offset line_out
	push DS
	call setds2si
	mov CH, DS:[0000]
	mov BX, DS:[0001]	;; owner psp
	mov DX, DS:[0003]
	mov AX, SI
	call hexword	;; segment address of MCB
	mov AL, ' '
	stosb
	mov AL, CH
	call hexbyte	;; 'M' or 'Z'
	mov AL, ' '
	stosb
	mov AX, BX
	call hexword	;; MCB owner
	mov AL, ' '
	stosb
	mov AX, DX
	call hexword	;; MCB size in paragraphs
	mov AL, ' '
	stosb
	and BX, BX
	jz mcbisfree
	push SI
	push CX
	push DX
	mov SI, 8
	mov CX, 2
	cmp BX, SI	;; is it a "system" MCB?
	jz nextmcbchar
	dec BX
	call setds2bx	;; destroys CX if in pm
	mov CX, 8
nextmcbchar:		;; copy "name" of owner MCB
	lodsb
	stosb
	and AL, AL
	loopnz nextmcbchar
	pop DX
	pop CX
	pop SI
mcbisfree:
	pop DS
	add SI, DX
	jc mcbout_done
	inc SI
	push CX
	call putsline	;; destroys CX, DX, BX
	pop CX
	cmp CH, 'Z'
	jz nextmcb
	cmp CH, 'M'
	jz nextmcb
mcbout_done:
	ret

setds2si:
	mov BX, SI
setds2bx:
if _PM
	call ispm_dbe
	jz sd2s_ex
	mov DX, BX
	call setrmsegm
sd2s_ex:
endif
	mov DS, BX
	ret
mcbout endp
endif

if DTCMD
CONST segment
if LMODE
szPL0Stk db " RSP0=", 0
else
szPL0Stk db " R0 SS:ESP=", 0
endif
CONST ends

 if 0
;; --- "legacy TSS "
TSSSTR struct
dwLink	dd ?	;; +00 selector
_ESP0	dd ?	;; +04
_SS0	dd ?
dqStk1	dq ?	;; +0c
dqStk2	dq ?	;; +14
_CR3	dd ?	;; +1c
_EIP	dd ?	;; +20
_Efl	dd ?	;; +24
_EAX	dd ?	;; +28
_ECX	dd ?	;; +2c
_EDX	dd ?	;; +30
_EBX	dd ?	;; +34
_ESP	dd ?	;; +38
_EBP	dd ?	;; +3c
_ESI	dd ?	;; +40
_EDI	dd ?	;; +44
_ES	dd ?	;; +48
_CS	dd ?	;; +4c
_SS	dd ?	;; +50
_DS	dd ?	;; +54
_FS	dd ?	;; +58
_GS	dd ?	;; +5c
_LDT	dd ?	;; +60
wFlags	dw ?	;; +64
wOffs	dw ?	;; +66
TSSSTR ends
;; --- long mode TSS
TSSSTR struct
	dd ?	;; +00
_Rsp0	dq ?	;; +04
_Rsp1	dq ?	;; +0c
_Rsp2	dq ?	;; +14
	dd ?	;; +1c
_Ist1	dq ?	;; +24
_Ist2	dq ?	;; +2c
_Ist3	dq ?	;; +34
_Ist4	dq ?	;; +3c
_Ist5	dq ?	;; +44
_Ist6	dq ?	;; +4c
_Ist7	dq ?	;; +54
	dq ?	;; +5c
	dw ?	;; +64
wOffs	dw ?	;; +66
TSSSTR ends
 endif

dt_cmd proc
	.386
	mov AX, "RT"
	stosw
	mov AL, '='
	stosb
	str AX
	mov BX, AX
	call hexword
	cmp BX, 0
	jz @F
	call getlinearbase
	jc @F
	movzx EBX, BX
	add EBX, EAX	;; EBX=linear addr of TR in GDT
	mov SI, offset szPL0Stk
	call copystring
	push DS
	mov DS, [wFlat]
	mov AH, [EBX+7]
	mov AL, [EBX+4]
	shl EAX, 16
	mov AX, [EBX+2]	;; EAX=linear addr TSS
	@dprintf "dt: EBX=%lX EAX=%lX", EBX, EAX
	mov EBX, EAX
if LMODE
	mov EAX, [EBX+8]	;; get high32 RSP0
	call hexdword
else
	mov AX, [EBX+8]	;; get PL0 SS
	call hexword
	mov AL, ':'
	stosb
endif
	mov EAX, [EBX+4]	;; get PL0 ESP / low32 RSP0
	call hexdword
	pop DS
@@:
	call putsline
	ret
dt_cmd endp
endif

;; --- DX command. Display extended memory
;; --- works for 80386+ only.
if DXCMD
if USEUNREAL
    align 4
gdt label qword
	dw -1, 0, 9200h, 0cfh	;; 32-bit flat data descriptor
	dw -1, 0, 9200h, 0	;; 16-bit data descriptor
GDTR label fword
	dw 3*8-1
	dd 0

SEL_FLAT equ 8
SEL_DATA16 equ 16

	.386p
;; --- set/reset unreal mode
setdspm:
	cli
	mov AX, CS
	movzx EAX, AX
	shl EAX, 4
	add EAX, offset gdt-8
	mov dword ptr CS:[GDTR+2], EAX
	lgdt CS:[GDTR]
	mov EAX, cr0
	inc AX
	mov cr0, EAX
	jmp @F
@@:
	mov DS, CX
	dec AX
	mov cr0, EAX
	jmp @F
@@:
	sti
	ret

	.386
;; --- exception 0d:
int0d:
if 1
	push AX		;; check for IRQ. If request, jmp to previous handler
	mov AL, 0bh
	out 20h, AL
	in AL, 20h
	test AL, 20h	;; real IRQ 5?
	pop AX
	jz @F
	db 0eah
oldint0d dd ?
@@:
endif
	push DS
	push EAX
	push CX
	mov CX, SEL_FLAT
	call setdspm
	pop CX
	pop EAX
	mov AL, 0
	pop DS
	iret
endif

	.386
dx_cmd proc
	mov DX, word ptr [x_addr+0]
	mov BX, word ptr [x_addr+2]
	call skipwhite
	cmp AL, CR
	jz @F
	call getdword	;; get linear address into BX:DX
	call chkeol	;; expect end of line here
@@:
	mov [lastcmd], offset dx_cmd
	push BX
	push DX
	pop EBP

if USEUNREAL
;; --- the DX cmd, when using int 15h, AH=87, has the side effect that unreal-mode most likely is disabled after the call.
;; --- Setting USEUNREAL=1 avoids that, but has the disadvantange that DX won't work in v86-mode!
	smsw AX			;; don't use ispm, since that won't detect v86!
	test AL, 1
	jnz dx_exit
	push DS
	push CS
	push offset int0d
	pop EAX
	xor ECX, ECX
	mov DS, CX
	mov EBX, DS:[0dh*4]
	mov CS:[oldint0d], EBX
	mov DS:[0dh*4], EAX
	mov ESI, EBP
	mov AL, 1
	mov CL, 20h
	mov EDI, offset line_out+128
	rep movsd ES:[EDI], DS:[ESI]
	mov DS:[0dh*4], EBX
	dec AL		;; has an exception occured?
	jz @F		;; if no, don't reset unreal mode!
	mov CX, SEL_DATA16
	call setdspm
@@:
	pop DS
else
	mov DI, offset line_out	;; create a GDT for Int 15h, AH=87h
	xor AX, AX
	mov CX, 24	;; init 6 descriptors (48 bytes)
	rep stosw
	sub DI, 4*8
	mov AX, 007fh	;; limit of source (128 bytes)
	stosw
	mov AX, DX	;; base[0-15] of source
	stosw
	mov AL, BL	;; base[16-23] of source
	stosb
	mov AX, 0093h
	stosw
	mov AL, BH	;; base[24-31] of source
	stosb
	mov AX, 007fh	;; limit of dest
	stosw
	lea EAX, [line_out+128]
	movzx EBX, [pspdbg]
	shl EBX, 4
	add EAX, EBX
	stosw		;; base[0-15] of dest
	shr EAX, 16
	stosb		;; base[16-23] of dest
	mov BL, AH
	mov AX, 0093h
	stosw
	mov AL, BL
	stosb		;; base[24-31] of dest
 if _PM
	call ispm_dbg
 endif
	mov SI, offset line_out	;; DS:SI -> GDT
	mov CX, 0040h	;; number of word to copy
	mov AH, 87h
 if _PM
	jz @F
	invoke intcall, 15h, CS:[pspdbg]
	jmp i15ok
@@:
 endif
	int 15h
i15ok:
	jc dx_exit
endif
	mov SI, offset line_out+128
	mov CH, 8h
nextline:
	mov DI, offset line_out
	mov EAX, EBP
	call hexdword
	mov AX, "  "
	stosw
	lea BX, [DI+3*16]
	mov CL, 10h
nextbyte:
	lodsb
	mov AH, AL
	cmp AL, 20h
	jnc @F
	mov AH, '.'
@@:
	mov [BX], AH
	inc BX
	call hexbyte
	mov AL, ' '
	stosb
	dec CL
	jnz nextbyte
	mov byte ptr [DI-(8*3+1)], '-'	;; display a '-' after 8 bytes
	mov DI, BX
	push CX
	call putsline
	pop CX
	add EBP, 10h
	dec CH
	jnz nextline
	mov [x_addr], EBP
dx_exit:
	ret
	.8086
dx_cmd endp
endif

;; --- D command - hex/ascii dump.
d_cmd proc
	cmp AL, CR
	jne dd1		;; if an argument was given
	sizeprfX	;; mov EDX, [d_addr]
	mov DX, [d_addr]
	mov BX, [d_addr+4]
if RING0
	verr BX
	jz @F
	mov BX, [regs.rDS]
	xor EDX, EDX
@@:
endif
	sizeprfX	;; mov ESI, EDX
	mov SI, DX

;; --- ?PM: we don't know yet if limit is > 64kB
;; --- so we stop at 64 kB in any case
	add DX, 80h-1	;; compute range of 80h or until end of segment
	jnc dd2
	or DX, -1
	jmp dd2

dd1:
if DGCMD or DICMD or DLCMD or DMCMD or DPCMD or DTCMD or DXCMD
	cmp AH, 'd'
	jnz dd1_1
	or AL, TOLOWER
 if DGCMD
	cmp AL, 'g'
	jnz @F
	jmp dgl_cmd
@@:
 endif
 if DLCMD
	cmp AL, 'l'
	jnz @F
	jmp dgl_cmd
@@:
 endif
 if DICMD
	cmp AL, 'i'
	jnz @F
	jmp di_cmd
@@:
 endif
 if DTCMD
	cmp AL, 't'
	jnz @F
	jmp dt_cmd
@@:
 endif
 if DXCMD
	cmp AL, 'x'
	jnz @F
	cmp [machine], 3
	jb @F
	jmp dx_cmd
@@:
 endif
 if DPCMD
	cmp AL, 'p'
	jnz @F
	jmp dp_cmd
@@:
 endif
 if DMCMD
	cmp AL, 'm'
	jnz @F
	jmp mcbout
@@:
 endif
dd1_1:
endif
	sizeprfX		;; clear hiword ECX (14.2.2021)
	xor CX, CX
	mov CL, 80h		;; default length
	mov BX, [regs.rDS]
	call getrange		;; get address range into BX:(E)DX ... BX:(E)CX
	call chkeol		;; expect end of line here

	sizeprfX		;; mov ESI, EDX
	mov SI, DX
	sizeprfX		;; mov EDX, ECX (14.2.2021)
	mov DX, CX		;; DX = end address

;; --- Parsing is done.
;; --- Print first/next line.
;; --- DI=output pos, BX=segment/selector
;; --- E/SI=src offset, E/DX=end src
dd2:
	mov [lastcmd], offset d_cmd
	mov [d_addr+4], BX	;; save segment (offset is saved later)
if ?PM
	xor BP, BP
	call getseglimit	;; Z flag set if segment limit is <= 64 kB
	jz @F
	inc BP
@@:
endif
	@dprintf "d: BX:ESI=%X:%lX EDX=%lx", BX, ESI, EDX
	call prephack	;; set up for faking int vectors 23 and 24
dd_loop:
	mov AX, [d_addr+4]
	call hexword
	mov AL, ':'
	stosb
if ?PM
	and BP, BP
	jz @F
	.386
	shld EAX, ESI, 16		;; AX=HiWord(ESI)
	.8086
	call hexword
@@:
endif
	mov AX, SI
	and AL, 0f0h
	mov CX, SI
	sub CX, AX
	call hexword

;; --- blank the line
	mov AX, '  '
	stosw
	lea BX, [DI+3*16]
	add BX, CX
	push CX
	push DI
	mov CX, BX
	sub CX, DI
	rep stosb
	pop DI
	pop CX
	mov byte ptr [DI+3*8-1], '-'
	add DI, CX
	add CX, CX
	add DI, CX

if ?PM
	and BP, BP
	jz dd4a
	.386
	mov ECX, ESI
	or CL, 0fh
	cmp ECX, EDX
	jb @F
	mov ECX, EDX
@@:
	sub ECX, ESI
	inc ECX
	.8086
	jmp dd4b
dd4a:
endif
	mov CX, SI
	or CL, 0fh
	cmp CX, DX		;; compare with end address
	jb @F			;; if we write to the end of the line
	mov CX, DX
@@:
	sub CX, SI
	inc CX			;; CX = number of bytes to print this line
dd4b:
	call dohack		;; set debuggee's int 23/24
	mov DS, [d_addr+4]
dd6:
if ?PM
	and BP, BP
	jz $+3
	db 67h			;; lodsb [ESI]
endif
	lodsb
	push AX
	call hexbyte
	inc DI
;;	mov AL, ' '
;;	stosb
	pop AX
	cmp AL, ' '
	jb dd7		;; if control character
	cmp AL, '~'
	jbe dd8		;; if printable
dd7:
	mov AL, '.'
dd8:
	mov ES:[BX], AL
	inc BX
	loop dd6

	push ES		;; restore DS
	pop DS

	sizeprfX	;; mov [d_addr], ESI
	mov [d_addr], SI
	call unhack	;; set debugger's int 23/24
	mov DI, BX
	push DX
	call putsline
	pop DX
	mov DI, offset line_out	;; set up for next time
if ?PM
	and BP, BP
	jz @F
	.386
	dec ESI
	cmp ESI, EDX
	jae dd11
	inc ESI
	.8086
	jmp dd_loop
@@:
endif
	dec SI
	cmp SI, DX
	jae dd11
	inc SI
	jmp dd_loop
dd11:
	ret
d_cmd endp

errorj4:
	jmp cmd_error

;; --- E command - edit memory.
e_cmd proc
	call prephack
	mov BX, [regs.rDS]
	call getaddr		;; get address into BX:(E)DX
	call skipcomm0
	cmp AL, CR
	je ee1			;; if prompt mode
	push DX			;; save destination offset
	call getstr		;; get data bytes SI -> line_out
	mov CX, DI
	mov DX, offset line_out
	sub CX, DX		;; length of byte string
	pop DI
	mov AX, CX
	dec AX
if ?PM
	cmp [bAddr32], 0	;; v1.29: if limit is > 64kB, skip test
	jnz @F
endif
	add AX, DI
	jc errorj4		;; if it wraps around
@@:
	call dohack		;; set debuggee's int 23/24
	mov SI, DX
if ?PM
	call IsWriteableBX
endif
	mov ES, BX
if ?PM
	cmp [bAddr32], 0
	jz @F
	.386
	mov DX, DI		;; DX was destroyed
	mov EDI, EDX
	movzx ESI, SI
	movzx ECX, CX
	db 67h			;; rep movsb [EDI], [ESI]
	.8086
@@:
endif
	rep movsb

;; --- Restore DS + ES and undo the interrupt vector hack.
;; --- This code is also used by the 'm' command.
ee0a::
	@RestoreSeg DS
	push DS			;; restore ES
	pop ES
if INT2324
;; --- prehak1 is called after debuggee memory has been written (just e cmd)
	mov DI, offset run2324	;; debuggee's int 23/24 values
	call prehak1		;; copy IVT 23/24 to DI (real-mode only)
	call unhack		;; set debugger's int 23/24
endif
	ret

;; --- Prompt mode.
ee1:
	@dprintf "e: BX:EDX=%X:%lX", BX, EDX
if REDIRECT
	mov [bufnext], SI	;; update buffer ptr in case stdin is file
endif

;; --- Begin loop over lines.
ee2:		;; <--- next line
	mov AX, BX		;; print out segment and offset
	call hexword
	mov AL, ':'
	stosb
	mov BP, offset hexword
if ?PM
	cmp [bAddr32], 0
	jz @F
	mov BP, offset hexdword
	db 66h	;; mov EAX, EDX
@@:
endif
	mov AX, DX
	call BP

;; --- Begin loop over bytes.
ee3:		;; <--- next byte
	mov AX, '  '		;; print old value of byte
	stosw
	call dohack		;; set debuggee's int 23/24
	call readmem		;; read mem at BX:(E)DX
	call unhack		;; set debugger's int 23/24
	call hexbyte
	mov AL, '.'
	stosb
	push BX
	push DX
	call puts
	pop DX
	pop BX
	mov SI, offset line_out+16	;; address of buffer for characters
	xor CX, CX			;; number of characters so far

ee4:		;; <--- get next char
if REDIRECT
	test [fStdin], AT_DEVICE
	jnz ee9			;; jmp if it's a tty
	push SI
	mov SI, [bufnext]
	cmp SI, [bufend]
	jb @F			;; if there's a character already
	call fillbuf		;; fill buffer with a new line; init SI
	mov AL, CR
	jc ee8			;; if eof
@@:
	lodsb			;; get the character
ee8:
	mov [bufnext], SI
	pop SI
	jmp ee10
endif
ee9:
	call InDos	;; v1.27: use BIOS if InDOS
	jnz @F
	mov AH, 8	;; console input without echo
;;	int 21h		;; v1.29: don't use int instruction;
	call doscall	;; might make debuggee run if int 21h is intercepted
	jmp ee10
@@:
	mov AH, 0h
if RING0
	.386
	call CS:[int16vec]
	.8086
else
	int 16h
endif

ee10:
	cmp AL, ' '
	je ee13			;; if done with this byte
	cmp AL, CR
	je ee13			;; ditto
	cmp AL, BS
	je ee11			;; if backspace
	cmp AL, '-'
	je ee112		;; if '-'
	cmp CX, 2		;; otherwise, it should be a hex character
	jae ee4			;; if we have a full byte already
	mov [SI], AL
	call getnyb
	jc ee4			;; if it's not a hex character
	inc CX
	lodsb			;; get the character back
	jmp ee12
ee112:
	call stdoutal
if ?PM
	cmp [bAddr32], 0
	jz @F
	db 66h			;; dec EDX
@@:
endif
	dec DX			;; decrement offset part
	mov DI, offset line_out
	jmp ee15
ee11:
	jcxz ee4		;; if nothing to backspace over
	dec CX
	dec SI
	call fullbsout
	jmp ee4
ee12:
	call stdoutal
	jmp ee4			;; back for more

;; --- We have a byte (if CX != 0).
ee13:
	jcxz ee14		;; if no change for this byte
	mov [SI], AL		;; terminate the string
	sub SI, CX		;; point to beginning
	push AX			;; v1.29: save/restore value of AL to avoid stop if 'D' is entered
	push CX
	push DX
	lodsb
	call getbyte		;; convert byte to binary (DL)
	mov AL, DL
	pop DX
	pop CX
	call dohack		;; set debuggee's int 23/24
	call writemem		;; write AL at BX:(E)DX
	pop AX
if INT2324
	mov DI, offset run2324	;; debuggee's int 23/24
	call prehak1		;; copy IVT 23/24 to DI (real-mode only)
	call unhack		;; set debugger's int 23/24
endif

;; --- End the loop over bytes.
ee14:
if ?PM
	cmp [bAddr32], 0
	jz @F
	db 66h			;; inc EDX
@@:
endif
	inc DX			;; increment offset
	mov DI, offset line_out
	cmp AL, CR
	je ee16			;; if done
	test DL, 7
	jz ee15			;; if new line
	not CX
	add CX, 4		;; compute 3 - CX
	mov AL, ' '
	rep stosb		;; store that many spaces
	jmp ee3			;; back for more

ee15:
	mov AX, LF*256 + CR	;; terminate this line
	stosw
	jmp ee2			;; back for a new line

ee16:
	jmp putsline		;; call putsline and return
e_cmd endp

;; --- F command - fill memory

f_cmd proc
	sizeprfX		;; xor ECX, ECX
	xor CX, CX		;; get address range (no default length)
	mov BX, [regs.rDS]
;; --- v2.0: getRange must now be followed by a IsWriteableBX() in pm
	call getrange		;; get address range into BX:(E)DX/(E)CX
if ?PM
	cmp [bAddr32], 0
	jz @F
	.386
	sub ECX, EDX
	inc ECX
	push ECX
	push EDX
	.8086
	jmp ff_01
@@:
endif
	sub CX, DX
	inc CX			;; CX = number of bytes
	push CX			;; save it
	push DX			;; save start address
ff_01:
	call skipcomm0
	call getstr		;; get string of bytes
	mov CX, DI
	sub CX, offset line_out
if ?PM
	call IsWriteableBX	;; ensure BX is writeable
endif
	mov ES, BX
if ?PM
	cmp [bAddr32], 0
	jz fill_16
	.386
	movzx ECX, CX
	pop EDI
	cmp ECX, 1
	je onebyte32
	pop EAX			;; EAX=size (of mem block)
;;	@dprintf "f_cmd: EAX=%lX, ECX=%lX, ES:EDI=%X:%lX", EAX, ECX, ES, EDI
	cdq
	div ECX			;; ECX=size of hex-string entered
	mov ESI, offset line_out
	or EAX, EAX
	jz partial32
nextcopy32:
	push ECX
	push ESI
	rep movsb ES:[EDI], DS:[ESI]
	pop ESI
	pop ECX
	dec EAX
	jnz nextcopy32
partial32:
	mov ECX, EDX
;;	jecxz exit		;; rep with ECX=0 is a nop
	rep movsb ES:[EDI], DS:[ESI]
	jmp exit
onebyte32:
	pop ECX
	mov AL, byte ptr [line_out]
	rep stosb ES:[EDI]
	jmp exit
fill_16:
	.8086
endif
	pop DI
	cmp CX, 1
	je onebyte16	;; a common optimization
	pop AX		;; get size
	xor DX, DX	;; now size in DX:AX
	cmp AX, 1
	adc DX, 0	;; convert 0000:0000 to 0001:0000
	div CX		;; compute number of whole repetitions
	mov SI, offset line_out
	or AX, AX
	jz partial16	;; if less than one whole rep
nextcopy16:
	push CX
	push SI
	rep movsb
	pop SI
	pop CX
	dec AX
	jnz nextcopy16	;; if more to go
partial16:
	mov CX, DX
;;	jcxz exit	;; rep with CX=0 is a nop
	rep movsb
	jmp exit
onebyte16:
	pop CX
	mov AL, byte ptr [line_out]
	stosb		;; CX=0 -> 64 kB
	dec CX
	rep stosb
exit:
	push DS
	pop ES
	ret
f_cmd endp

;; --- breakpoints are stored in line_out, with this format
;; --- word cnt
;; --- array:
;; --- dword/word offset of BP
;; --- word segment of BP
;; --- byte old value
resetbps:
	mov DI, offset resetbp1
setbps proc
	mov SI, offset line_out
	lodsw
	xchg CX, AX	;; mov CX, AX
@@:
	jcxz @F
	sizeprfX	;; lodsd
	lodsw
	sizeprfX	;; xchg EDX, EAX
	xchg DX, AX	;; mov DX, AX
	lodsw
	xchg BX, AX	;; mov BX, AX
	call DI		;; call setbp1/resetbp1
	inc SI
	loop @B		;; next BP
@@:
	ret
setbp1::
	mov AL, 0cch
	call writemem	;; write byte at BX:E/DX
	mov [SI], AH	;; save the current contents
	jc @F
	retn
@@:
	call BP		;; either ignore error (g cmd) or abort with msg (p cmd)
	retn
resetbp1::
	mov AL, [SI]
	cmp AL, 0cch
	jz @F
	call writemem	;; write byte at BX:E/DX
@@:
	retn
setbps endp

if _PM
;; --- with DebugX: when a mode switch did occur in the debuggee,
;; --- the segment parts of the breakpoint addresses are no longer valid in the new mode.
;; --- To enable the debugger to reset the breakpoints, it has to switch temporarily to the previous mode.
;; --- in: DX=old value of regs.msw
resetbpsEx proc
	cmp DX, [regs.msw]
	jz resetbps			;; mode didn't change, use normal reset routine
if INT22
	cmp [run_int], INT22MSG	;; skip reseting bps if debuggee terminated
	jz @F
endif
	cmp byte ptr [line_out], 0	;; any breakpoints defined?
	jz @F
	mov CX, [dpmi_size]	;; don't call save state if buffer size is zero.
	jcxz do_switch		;; this avoids a CWSDPMI bug
	sub SP, CX
	mov AL, 0			;; AL=0 is "save state"
	call sr_state
	call do_switch
	mov AL, 1			;; AL=1 is "restore state"
	call sr_state
	add SP, [dpmi_size]
@@:
	ret
do_switch:
	call switchmode		;; switch to old mode
	call resetbps
	jmp switchmode		;; switch back to new mode

switchmode::
;; --- raw switch:
;; --- SI:E/DI:	new CS:E/IP
;; --- DX:E/BX:	new SS:E/SP
;; --- AX:	new DS
;; --- CX:	new ES
	sizeprf		;; xor EBX, EBX
	xor BX, BX	;; clears hiword EBX if cpu >= 386
	mov BX, SP
	sizeprf		;; xor EDI, EDI
	xor DI, DI	;; clears hiword EDI if cpu >= 386
	mov DI, back_after_switch
	call ispm_dbg
	jnz is_pm
	mov AX, [dssel]	;; switch rm -> pm
	mov SI, [cssel]
	mov DX, AX
	mov CX, AX
	jmp [dpmi_rm2pm]
is_pm:
	mov AX, [pspdbg]	;; switch pm -> rm
	mov SI, AX
	mov DX, AX
	mov CX, AX
	cmp dpmi32, 0
	jz @F
	db 66h		;; jmp fword ptr [dpmi_pm2rm]
@@:
	jmp dword ptr [dpmi_pm2rm]
back_after_switch:
	xor [regs.msw], -1
	retn

;; --- save/restore task state in ES:(E)DI
sr_state::
	sizeprf		;; xor EDI, EDI
	xor DI, DI	;; clears hiword EDI if cpu >= 386
	mov DI, SP
	add DI, 2	;; the save space starts at [SP+2]
	call ispm_dbg
	jnz is_pm2
	call [dpmi_rmsav]
	retn
is_pm2:
	cmp dpmi32, 0
	jz @F
	db 66h		;; call fword ptr [dpmi_pmsav]
@@:
	call dword ptr [dpmi_pmsav]
	retn
resetbpsEx endp
endif

;; --- G command - go.
g_cmd proc
	call parseql	;; get optional <=addr> argument; always writes [eqladdr+4]

;; --- Parse the rest of the line for breakpoints
	mov DI, offset line_out
	xor AX, AX
	stosw
@@:
	dec SI
	call skipcomma
	cmp AL, CR		;; end of line?
	je @F

;; --- calling getaddr was a bug in protected-mode up to v1.29.
;; --- (it was a different getaddr than now, one that ensured the segment part is a writeable selector in pm;
;; --- with 2.0, getaddr does this no longer).
;; --- Anyway, multiple BPs with different segment parts all used the very same "scratch" selector,
;; --- resulting in "random" mem writes.
	mov BX, [eqladdr+4]	;; default segment (either CS or segm of '=')
	call getaddr		;; get address into BX:(E)DX
	@dprintf "g_cmd: BP=%X:%lX", BX, EDX
	sizeprfX		;; xchg EAX, EDX
	xchg AX, DX		;; mov AX, DX
	sizeprfX		;; stosd
	stosw
	xchg AX, BX		;; mov AX, BX
	stosw
	inc DI			;; reserve to store byte at BP location
	inc byte ptr line_out	;; use [line_out+0] to count bps
	jmp @B			;; next BP
@@:
;; --- Store breakpoint bytes in the given locations.
	mov BP, offset _ret	;; ignore write errors for g
gg_1::		;; <--- called by p (run an int/call/... - set 1 BP)
	mov DI, offset setbp1
	call setbps
	@dprintf "g_cmd: calling run"

if _PM
	push [regs.msw]	;; save old MSW
endif
	call run		;; run the program
if _PM
	pop DX			;; get old MSW
endif

ife RING0
	@dprintf "g_cmd: run returned, [spadjust]=%X, [spsav]=%lX", [spadjust], dword ptr DS:[SPSAV]
endif

if ?PM
	call getcsattr
	mov [bCSAttr], AL	;; must be set for getcseipbyte()
endif

if 0	;; v2.0: not needed for soft/hard BP detection
	mov CX, -1
	call getcseipbyte	;; get byte at [CS:EIP-1], set E/BX to E/IP-1
	push AX
endif

;; --- Restore breakpoint bytes.
if _PM
;; --- if debuggee has terminated ([run_int] == INT22MSG),
;; --- nothing will be done if mode has changed (see resetbpsEx()).
	call resetbpsEx		;; reset BPs (expects DX=old msw), may switch tmp. to previous mode
else
	call resetbps
endif
	@dprintf "g_cmd: resetbps done"

;; --- Finish up.
;; --- Check if it was one of _our_ breakpoints.
;; --- if yes, decrement (E)IP
if 0	;; v2.0: not needed for soft/hard BP detection
	pop AX
	cmp AL, 0cch		;; was a cc at CS:[EIP-1]?
	jnz gg_exit
endif
	cmp [run_int], EXC03MSG
	jnz gg_exit
	mov CX, -1
	call getcseipbyte	;; modifies (E)BX
	cmp AL, 0cch		;; still a INT3 at [CS:EIP-1] ?
	jz gg_exit
if ?PM
	test [bCSAttr], CS32ATTR
	jz $+3
	db 66h	;; mov [regs.rIP], EBX
endif
	mov [regs.rIP], BX	;; decrement (E)IP
if RING0
	mov [run_int], -1	;; v2.0: reset entry (so SK cmd won't accept soft bps)
endif
	call dumpregs	;; then just display register dump
_ret:
	ret				;; and done (no "unexpected breakpoint" msg)
gg_exit:
	jmp ue_int		;; print messages and quit.
g_cmd endp

;; --- H command - hex addition and subtraction.
h_cmd proc
	call getdword		;; get dword in BX:DX
	push BX
	push DX
	call skipcomm0
	call getdword
	call chkeol		;; expect end of line here
	pop CX
	pop AX			;; first value in AX:CX, second in BX:DX
if 0
	mov SI, AX
	or SI, BX
	jnz hh32		;; 32bit values
	mov AX, CX
	add AX, DX
	push CX
	call hexword
	pop CX
	mov AX, '  '
	stosw
	mov AX, CX
	sub AX, DX
	call hexword
	call putsline
	ret
endif
hh32:
	mov SI, AX
	mov BP, CX			;; first value in SI:BP now
	mov AX, CX
	add AX, DX
	push AX
	mov AX, SI
	adc AX, BX
	jz @F
	call hexword
@@:
	pop AX
	call hexword
	mov AX, '  '
	stosw
	mov AX, BP
	sub AX, DX
	push AX
	mov AX, SI
	sbb AX, BX
	jz @F
	or SI, BX
	jz @F
	call hexword
@@:
	pop AX
	call hexword
	call putsline
	ret
h_cmd endp

;; --- I command - input from I/O port.
i_cmd proc
	mov BL, 0
	mov AH, AL
	and AH, TOUPPER
	cmp AH, 'W'
	je ii_1
	cmp [machine], 3
	jb ii_2
	cmp AH, 'D'
	jne ii_2
if 1
	mov AH, [SI-2]		;; distiguish 'id' and 'i d'
	and AH, TOUPPER
	cmp AH, 'I'
	jnz ii_2
endif
	inc BX
ii_1:
	inc BX
	call skipwhite
ii_2:
	call getword		;; get word into DX
	call chkeol		;; expect end of line here
	cmp BL, 1
	jz ii_3
	cmp BL, 2
	jz ii_4
	in AL, DX
	call hexbyte
	jmp ii_5
ii_3:
	in AX, DX
	call hexword
	jmp ii_5
ii_4:
	.386
	in EAX, DX
	.8086
	call hexdword
ii_5:
	call putsline
	ret
i_cmd endp

if _PM
LoadSDA:
	call ispm_dbg
	mov SI, word ptr [pSDA+0]
	mov DS, [SDASel]
	jnz @F
	mov DS, word ptr CS:[pSDA+2]
@@:
	ret

ispm_dbg:	;; debugger in protected-mode
ispm_dbe:	;; debuggee in protected-mode?
	cmp CS:[regs.msw], 0	;; returns: Z=real-mode, NZ=prot-mode
	ret
elseif 0	;; RING0
ispm_dbe:	;; debuggee in protected-mode?
	push AX
	mov AX, CS:[regs.efl+2]
	and AL, 2	;; VM bit
	xor AL, 2
	pop AX
	ret
endif

if LCMDFILE
;; --- set debugger's PSP
setpspdbg:
	mov BX, CS	;; if format is changed to MZ, this must be changed as well!
setpsp proc
	mov AH, 50h
 if _PM
	call ispm_dbg
	jz setpsp_rm
  if NOEXTENDER
	.286
	push CX
	push DX
	push BX
	push AX
	mov AX, 6
	int 31h
	pop AX
	shl CX, 12
	shr DX, 4
	or DX, CX
	mov BX, DX
	call doscallx
	pop BX
	pop DX
	pop CX
	ret
	.8086
  else
	jmp doscall_rm
  endif
setpsp_rm:
 endif

 if USESDA
  if _PM
	cmp word ptr [pSDA+2], 0
	jz doscall_rm
  endif
	push DS
	push SI
  if _PM
	call LoadSDA
  else
	lds SI, [pSDA]
  endif
	mov [SI+10h], BX
	pop SI
	pop DS
	ret
 else
	jmp doscall_rm
 endif
setpsp endp
endif

ife (BOOTDBG or RING0)
getpsp proc
	mov AH, 51h
if _PM
	call ispm_dbg
	jz getpsp_rm
 if NOEXTENDER
	call doscallx
	mov AX, 2
	int 31h
	mov BX, AX
	ret
 else
	jmp doscall_rm
 endif
getpsp_rm:
endif

if USESDA
 if _PM
	cmp word ptr [pSDA+2], 0
	jz doscall_rm
 endif
	push DS
	push SI
 if _PM
	call LoadSDA
 else
	lds SI, [pSDA]
 endif
	mov BX, [SI+10h]
	pop SI
	pop DS
	ret
else
	jmp doscall_rm
endif
getpsp endp
endif

doscall:
if NOEXTENDER
	call ispm_dbg
	jz doscall_rm
	.286
doscallx:
	invoke intcall, 21h, CS:[pspdbg]
	ret
	.8086
endif
doscall_rm:
	int 21h
	ret

if _PM
RMCS struc		;; the DPMI "real-mode call structure"
rDI	dw ?, ?	;; +0
rSI	dw ?, ?	;; +4
rBP	dw ?, ?	;; +8
	dw ?, ?	;; +12
rBX	dw ?, ?	;; +16
rDX	dw ?, ?	;; +20
rCX	dw ?, ?	;; +24
rAX	dw ?, ?	;; +28
rFlags	dw ?	;; +32
rES	dw ?	;; +34
rDS	dw ?	;; +36
rFS	dw ?	;; +38
rGS	dw ?	;; +40
rIP	dw ?	;; +42
rCS	dw ?	;; +44
rSP	dw ?	;; +46
rSS	dw ?	;; +48
RMCS ends

	.286
intcall proc stdcall uses ES intno:word, dataseg:word
local rmcs:RMCS
	push SS
	pop ES
	mov rmcs.rDI, DI
	mov rmcs.rSI, SI
	mov rmcs.rBX, BX
	mov rmcs.rDX, DX
	mov rmcs.rCX, CX
	mov rmcs.rAX, AX
	mov AX, [BP+0]
	mov rmcs.rBP, AX
	xor CX, CX
	mov rmcs.rFlags, CX
	mov rmcs.rSP, CX
	mov rmcs.rSS, CX
	mov AX, dataseg
	mov rmcs.rES, AX
	mov rmcs.rDS, AX
	sizeprf	;; lea EDI, rmcs
	lea DI, rmcs
	mov BX, intno
	mov AX, 0300h
	int 31h
	mov AH, byte ptr rmcs.rFlags
	lahf
	mov DI, rmcs.rDI
	mov SI, rmcs.rSI
	mov BX, rmcs.rBX
	mov DX, rmcs.rDX
	mov CX, rmcs.rCX
	mov AX, rmcs.rAX
	ret
intcall endp
	.8086
endif

if _PM
;; --- this proc is called in pmode only
;; --- DS is unknown!
isextenderavailable proc
	.286
	push DS
	push ES
	pusha
	push SS
	pop DS
	sizeprf		;; lea ESI, szMSDOS
	lea SI, szMSDOS	;; must be LEA, don't change to "mov SI, offset szMSDOS"!
	mov AX, 168ah
	int 2fh
	cmp AL, 1
	cmc
	popa
	pop ES
	pop DS
	ret
	.8086

CONST segment
szMSDOS	db "MS-DOS", 0
CONST ends
isextenderavailable endp

nodosextinst:
	push SS
	pop DS
	mov DX, offset nodosext
	jmp int21ah9
endif

if LCMDFILE
isdebuggeeloaded:
	mov AX, [pspdbe]
	cmp AX, [pspdbg]
	ret
endif

;; --- ensure a debuggee is loaded
;; --- set SI:DI to CS:IP, preserve AX, BX, DX
ensuredebuggeeloaded proc
if LCMDFILE
	push AX
	call isdebuggeeloaded
	jnz @F
	push BX
	push DX
	call createdummytask
	mov SI, [regs.rCS]
	mov DI, [regs.rIP]
	pop DX
	pop BX
@@:
	pop AX
endif
	ret
ensuredebuggeeloaded endp

if BOOTDBG or DPCMD
;; --- abs disk read, arguments in [packet]
;; --- AL = disk
;; --- out: C=error
;; --- modifies all std regs except SP, BP
	.errnz RING0, <int 13h not yet supported>

readsect proc
	@dprintf "readsect: disk=%X", AX
	mov DL, AL
	and AL, AL
	jns nolba
	mov BX, 055aah
	mov AH, 41h
	int 13h
	jc nolba
	cmp BX, 0aa55h
	jnz nolba
	test CL, 1
	jz nolba
	xor CX, CX
	mov BX, offset packet
	@dprintf "readsect: lba access, DX=%X, secno=%lX", DX, [BX].PACKET.secno
	push CX
	push CX
	push word ptr [BX].PACKET.secno+2
	push word ptr [BX].PACKET.secno+0
	push [BX].PACKET.dstseg
	push [BX].PACKET.dstofs
	push [BX].PACKET.numsecs
	mov CL, 16
	push CX
	mov SI, SP
	mov AH, 42h
	int 13h
	lea SP, [SI+8*2]
	jc disk_err
done:
	ret
nolba:
	push DX
	mov AH, 8
	int 13h
	pop AX
	jc disk_inval
	mov BX, offset packet
	push AX
	call lba2chs
	pop AX
	mov DL, AL
	@dprintf "l: chs access, DX=X, CX=%X", DX, CX
	mov AH, 2
	mov AL, byte ptr [BX].PACKET.numsecs
	push ES
	les BX, dword ptr [BX].PACKET.dstofs
	int 13h
	pop ES
	jc disk_err
	ret
disk_err:
	mov DX, offset dskerrb
	jmp @F
disk_inval:
	mov DX, offset dskerr1
@@:
	stc
	ret
lba2chs:
	mov SI, CX
	and SI, 3fh
	mov AL, DH
	inc AL
	mov AH, 0
	mov DI, AX
	mov CX, word ptr [BX].PACKET.secno+0
	mov AX, word ptr [BX].PACKET.secno+2
	xor DX, DX
	div SI
	xchg AX, CX
	div SI
	inc DX
	xchg CX, DX
	div DI
	mov DH, DL
	mov CH, AL
	ror AH, 1
	ror AH, 1
	or CL, AH
	retn
readsect endp
endif

if BOOTDBG
;; --- L command - absolute disk read.
l_cmd proc
	call parselw	;; returns AL=drive, BX=packet
	jz cmd_error	;; must be a full command
	call readsect
	jnc @F
	call int21ah9
@@:
	ret
l_cmd endp

elseife RING0
;; --- L command - read a program, or disk sectors, from disk.
l_cmd proc
	call parselw	;; parse it, addr in BX:(E)DX
 if LCMDFILE
	jz ll1		;; if request to read program
 else
	jz cmd_error
 endif
 if NOEXTENDER
	call ispm_dbg
	jz @F
	call isextenderavailable
	jc nodosextinst
@@:
 endif
	cmp CS:[usepacket], 2
	jb ll0_1
	mov DL, AL	;; A=0, B=1, C=2, ...
	xor SI, SI	;; read drive
 if VDD
	mov AX, [hVdd]
	cmp AX, -1
	jnz callvddread
 endif
	inc DL		;; A=1, B=2, C=3, ...
	mov AX, 7305h	;; DS:(E)BX -> packet
	stc
	int 21h		;; use int 21h here, not doscall!
	jmp ll0_2
 if VDD
callvddread:
	mov CX, 5
	add CL, [dpmi32]
	DispatchCall
	jmp ll0_2
 endif
ll0_1:
	int 25h
ll0_2:
	mov CX, "er"		;; CX:DX="read"
	mov DX, "da"
	jmp disp_diskresult

 if LCMDFILE
;; --- For .com or .exe files, we can only load at CS:100.
;; --- Check that first.
ll1:
	test [fileext], EXT_COM or EXT_EXE
	jz loadfile		;; if not .com or .exe file
	cmp BX, [regs.rCS]
	jne ll2			;; if segment is wrong
	cmp DX, 100h
	je loadfile		;; if address is OK (or not given)
ll2:
	jmp cmd_error	;; can only load .com or .exe at CS:100
 endif
l_cmd endp

endif

if LCMDFILE
;; --- load (any) file (if not .EXE or .COM, load at BX:DX)
;; --- open file and get length
loadfile proc
	mov SI, BX	;; save destination address, segment
	mov DI, DX	;; and offset
	mov AX, 3d00h	;; open file for reading
	mov DX, DTA
	call doscall
	jnc @F		;; if no error
	jmp io_error	;; print error message
@@:
	xchg AX, BX	;; mov BX, AX
	mov AX, 4202h	;; lseek EOF
	xor CX, CX
	xor DX, DX
	int 21h

;; Split off file types
;; At this point:
;;	BX	file handle
;;	DX:AX	file length
;;	SI:DI	load address (CS:100h for .EXE or .COM)
	test [fileext], EXT_COM or EXT_EXE
	jnz loadpgm		;; if .com or .exe file

 if _PM
;; --- dont load a file in protected mode,
;; --- the read loop makes some segment register arithmetic
	call ispm_dbg
	jz @F
	mov DX, offset nopmsupp
	call int21ah9
	jmp ll12
@@:
 endif

;; --- Load it ourselves.
;; --- For non-.com/.exe files, we just do a read, and set BX:CX to the number of bytes read.
	call ensuredebuggeeloaded	;; make sure a debuggee is loaded
	mov ES, [pspdbe]

;; --- Check the size against available space.
	push SI
	push BX

	cmp SI, ES:[ALASAP]
	pushf
	neg SI
	popf
	jae ll6			;; if loading past end of mem, allow through ffff
	add SI, ES:[ALASAP]	;; SI = number of paragraphs available
ll6:
	mov CX, 4
	xor BX, BX
ll7:
	shl SI, 1
	rcl BX, 1
	loop ll7
	sub SI, DI
	sbb BX, CX		;; BX:SI = number of words left
	jb ll9			;; if already we're out of space
	cmp BX, DX
	jne @F
	cmp SI, AX
@@:
	jae ll10		;; if not out of space
ll9:
	pop BX			;; out of space
	pop SI
	mov DX, offset doserr8	;; not enough memory
	call int21ah9		;; print string
	jmp ll12

ll10:
	pop BX
	pop SI

;; --- Store length in registers
;; --- seems a bit unwise to modify registers if a debuggee is running but MS DEBUG does it as well
 if 0
	mov CX, [regs.rCS]
	cmp CX, [pspdbe]
	jnz noregmodify
	cmp [regs.rIP], 100h
	jnz noregmodify
 endif
	mov [regs.rBX], DX
	mov [regs.rCX], AX
noregmodify:
;; --- Rewind the file
	mov AX, 4200h	;; lseek
	xor CX, CX
	xor DX, DX
	int 21h

	mov DX, 0fh
	and DX, DI
	mov CL, 4
	shr DI, CL
	add SI, DI	;; SI:DX is the address to read to

;; --- Begin loop over chunks to read
ll11:
	mov AH, 3fh	;; read from file into DS:(E)DX
	mov CX, 0fe00h	;; read up to this many bytes
	mov DS, SI
	int 21h

	add SI, 0fe0h	;; wont work in protected-mode!
	cmp AX, CX
	je ll11		;; if end of file reached

;; --- Close the file and finish up.
ll12:
	mov AH, 3eh	;; close file
	int 21h
	push SS		;; restore DS
	pop DS
	ret		;; done
loadfile endp
endif

if LCMDFILE
setespefl proc
	sizeprf			;; pushfd
	pushf
	sizeprf			;; pop dword ptr [regs.rFL]
	pop [regs.rFL]
	sizeprf			;; mov dword ptr [regs.rSP], ESP
	mov [regs.rSP], SP	;; low 16bit of ESP will be overwritten
	ret
setespefl endp

loadpgm proc
;; --- file is .EXE or .COM
;; --- Close the file
	push AX
	mov AH, 3eh		;; close file
	int 21h
	pop BX			;; DX:BX is the file length

 if 1
;; --- adjust .exe size by 200h (who knows why)
	test [fileext], EXT_EXE
	jz @F		;; if not .exe
	sub BX, 200h
	sbb DX, 0
@@:
 endif

	push BX
	push DX

;; --- cancel current process (unless there is none)
;; --- this will also put cpu back in real-mode!!!
	call isdebuggeeloaded
	jz @F
	call freemem
@@:
;; --- Clear registers
	mov DI, offset regs
	mov CX, sizeof regs/2
	xor AX, AX
	rep stosw

	pop word ptr [regs.rBX]
	pop word ptr [regs.rCX]

;; --- Fix up interrupt vectors in PSP
if INT2324
	mov SI, CCIV		;; address of original int 23 and 24 (in PSP)
	mov DI, offset run2324
	movsw
	movsw
	movsw
	movsw
endif

;; --- Actual program loading.
;; --- Use the DOS interrupt.
	mov AX, 4b01h		;; load program
	mov DX, DTA		;; offset of file to load
	mov BX, offset execblk	;; parameter block
	int 21h			;; load it
	jnc @F
	jmp io_error	;; if error
@@:
	call setespefl

;; --- we calculate the stack space used by previous dos call (AX=4b01)
;; --- and use the result (in spadjust) to adjust the field PSP:[2eh]
;; --- in the debugger's PSP whenever the debuggee is to be executed ("run").
	mov AX, SP
	sub AX, DS:[SPSAV]
	cmp AX, 80h
	jb @F			;; if in range
	mov AX, 80h
@@:
	mov [spadjust], AX

;; --- use the values for CS:IP SS:SP returned by the loader
	les SI, dword ptr [execblk.sssp]
	lodsw ES:[SI]	;; recover AX
	mov [regs.rAX], AX
	mov [regs.rSP], SI
	mov [regs.rSS], ES
	les SI, dword ptr [execblk.csip]
	mov [regs.rIP], SI
	mov [regs.rCS], ES
	mov [bInit], 0
	push SS
	pop ES
	clc

;; --- get the debuggee's PSP and store it in debuggee's DS, ES
	call getpsp
	xchg AX, BX		;; mov AX, BX
	mov [pspdbe], AX
	mov DI, offset regs.rDS
	stosw
	stosw			;; regs.rES

	call setpspdbg	;; switch back to debugger's PSP

;; --- Finish up.
;; --- Set termination address.
	mov AX, 2522h	;; set interrupt vector 22
	mov DX, offset intr22
	int 21h
	mov DS, [pspdbe]
	mov word ptr DS:[TPIV+0], DX
	mov word ptr DS:[TPIV+2], CS
	push SS
	pop DS

;; --- Set up initial addresses for 'a', 'd', and 'u' commands.
setup_adu::
	mov DI, offset a_addr
	mov SI, offset regs.rIP
	push DI
	movsw
	movsw
	mov AX, [regs.rCS]
	stosw
	pop SI
	mov CX, 3*2
	rep movsw
	ret
loadpgm endp
endif

;; --- 'm'achine command: set machine type.
mach proc
;;	dec SI
;;	call skipwhite
;;	cmp AL, CR
;;	je mach_query		;; if just an 'm' (query machine type)
	mov AL, [SI-1]
	call getbyte
	mov AL, DL
	cmp AL, 6
	ja errorj3			;; DL must be 0-6
	mov [machine], AL	;; set machine type
	mov [mach_87], AL	;; coprocessor type, too
	cmp AL, 3
	jnc @F
	and [rmode], not RM_386REGS	;; reset 386 register display
@@:
	ret
mach endp

errorj3:
	jmp cmd_error

;; --- 'mc' command: set coprocessor.
;; --- optional arguments:
;; --- N: no coprocessor
;; --- 2: 80287 with 80386
mc_cmd proc
	call skipwhite	;; get next nonblank character
	mov AH, [machine]
	cmp AL, CR
	jz set_mpc
	or AL, TOLOWER
	push AX
	lodsb
	call chkeol
	pop AX
	cmp AL, 'n'
	jne @F			;; if something else
	mov [has_87], 0	;; clear coprocessor flag
	ret				;; done
@@:
	cmp AL, '2'
	jne errorj3		;; if not '2'
	cmp [machine], 3
	jnz errorj3		;; if not a 386
	mov AH, 2
set_mpc:
	mov [has_87], 1	;; set coprocessor flag
	mov [mach_87], AH
	ret
mc_cmd endp

;; --- M command - move/copy memory.
;; --- 1. check if there's no argument at all: mach_query, display cpu
;; --- 2. check for MC cmd: mc_cmd, set/reset coprocessor
;; --- 3. check if there's just 1 argument: mach, set cpu
m_cmd proc
	cmp AL, CR
	jz mach_query
	mov AH, [SI-2]
	or AX, TOLOWER or (TOLOWER shl 8)
	cmp AX, 'mc'		;; mc cmd?
	jz mc_cmd
if ?PM
	cmp AL, '0'		;; is there a '$' or '%' modifier?
	jb ismove		;; (would throw an error in getdword)
endif
	push SI
	call getdword
	cmp AL, CR
	jz @F
	call skipwhite
@@:
	pop SI
	cmp AL, CR
	je mach			;; jump if 1 argument only
ismove:
	dec SI
	lodsb
	call parsecm		;; parse arguments: src=DS:(E)SI, dst=ES:(E)DI, length-1=(E)CX
;; --- note: DS unknown here
	push CX
if ?PM
 if _PM
	call ispm_dbg
	jz @F
 endif
;; --- TODO: do overlapping check in protected-mode
	@dprintf "m_cmd: DS:ESI=%X:%lX, ES:EDI=%X:%lX, ECX=%lX", DS, ESI, ES, EDI, ECX
	clc
	jmp m3
@@:
endif
	mov CL, 4
	shr DX, CL	;; BX:DX=dst seg:ofs
	add DX, BX	;; upper 16 bits of destination
	mov AX, SI
	shr AX, CL
	mov BX, DS
	add AX, BX
	cmp AX, DX
	jne m3		;; if we know which is larger
	mov AX, SI
	and AL, 0fh
	mov BX, DI
	and BL, 0fh
	cmp AL, BL
m3:
	pop CX
	lahf
if INT2324
	push DS
	push SS		;; DS = dgroup
	pop DS
	call dohack	;; set debuggee's int 23/24
	pop DS
endif
if ?PM
;; --- v2.0: ensure ES is writeable (parsecm does that no longer)
	mov BX, ES
	push DS
	@RestoreSeg DS
 if _PM
	push DS
	pop ES
 endif
	call IsWriteableBX	;; expects DS(, ES) = dgroup
	cmp [bAddr32], 0
	pop DS
	mov ES, BX
	jz m3_1
	.386
	sahf
	jae @F
	add ESI, ECX
	add EDI, ECX
	std
@@:
	rep movsb ES:[EDI], DS:[ESI]
	movsb ES:[EDI], DS:[ESI]
	cld
	jmp ee0a
	.8086
m3_1:
endif
	sahf
	jae @F			;; if forward copy is OK
	add SI, CX
	add DI, CX
	std
@@:
	rep movsb		;; do the move
	movsb			;; one more byte
	cld			;; restore flag
	jmp ee0a		;; restore DS and ES and undo the int2324 pointer hack
m_cmd endp

;; --- M without argument - display machine type.

mach_query proc
	mov SI, offset msg8088
	mov AL, [machine]
	cmp AL, 0
	je @F			;; if 8088
	mov SI, offset msgx86
	add AL, '0'
	mov [SI], AL
@@:
	call copystring		;; SI->DI
	mov SI, offset no_copr
	cmp [has_87], 0
	je @F			;; if no coprocessor
	mov SI, offset has_copr
	mov AL, [mach_87]
	cmp AL, [machine]
	je @F			;; if has coprocessor same as processor
	mov SI, offset has_287
@@:
	call copystring		;; SI->DI
	jmp putsline		;; call puts and quit
mach_query endp

if LCMDFILE or WCMDFILE

;; --- N command - change the name of the program being debugged.

CONST segment
exts label byte
	db ".HEX", EXT_HEX
	db ".EXE", EXT_EXE
	db ".COM", EXT_COM
CONST ends

n_cmd proc
	mov DI, DTA		;; destination address

;; --- Copy and canonicalize file name.
nn1:
	cmp AL, CR
	je nn3		;; if end of line
	call ifsep	;; check for separators space, TAB, comma, ;, =
	je nn3		;; if end of file name
	cmp AL, [swch1]
	je nn3		;; if '/' (and '/' is the switch character)
	cmp AL, 'a'
	jb @F		;; if not lower case
	cmp AL, 'z'
	ja @F		;; ditto
	and AL, TOUPPER	;; convert to upper case
@@:
	stosb
	lodsb
	jmp nn1		;; back for more

nn3:
	mov AL, 0		;; null terminate the file name string
	stosb
	mov word ptr [execblk.cmdtail], DI	;; save start of command tail

;; --- Determine file extension
	push DI
	push SI
	cmp DI, DTA+1
	je nn3d			;; if no file name at all
	cmp DI, DTA+5
	jb nn3c			;; if no extension (name too short)
	lea DX, [DI-5]
	mov BX, offset exts	;; check for .EXE, .COM and .HEX
	mov CX, 3
@@:
	push CX
	mov SI, BX
	mov DI, DX
	add BX, 5
	mov CL, 4
	repz cmpsb
	mov AL, [SI]
	pop CX
	jz nn3d
	loop @B
nn3c:
	mov AL, EXT_OTHER
nn3d:
	mov [fileext], AL
	pop SI

;; --- Finish the N command
	mov DI, offset line_out
	push DI
	dec SI
@@:
	lodsb			;; copy the remainder to line_out
	stosb
	cmp AL, CR
	jne @B
	pop SI

;; --- Set up FCBs.
	mov DI, 5ch
	call DoFCB		;; do first FCB
	mov byte ptr [regs.rAX+0], AL
	mov DI, 6ch
	call DoFCB		;; second FCB
	mov byte ptr [regs.rAX+1], AL

;; --- Copy command tail.
	mov SI, offset line_out
	pop DI
	push DI
	inc DI
@@:
	lodsb
	stosb
	cmp AL, CR
	jne @B		;; if not end of string
	pop AX		;; recover old DI
	xchg AX, DI
	sub AX, DI	;; compute length of tail
	dec AX
	dec AX
	stosb
	ret
n_cmd endp

;; --- Subroutine to process an FCB.
;; --- DI->FCB
DoFCB proc
@@:
	lodsb
	cmp AL, CR
	je nn7		;; if end
	call ifsep
	je @B		;; if separator
	cmp AL, [swchar]
	je nn10		;; if switch character
nn7:
	dec SI
	mov AX, 2901h	;; parse filename
	call doscall
	push AX		;; save AL
@@:
	lodsb		;; skip till separator
	cmp AL, CR
	je @F		;; if end
	call ifsep
	je @F		;; if separator character
	cmp AL, [swch1]
	jne @B		;; if not swchar (sort of)
@@:
	dec SI
	pop AX		;; recover AL
	cmp AL, 1
	jne @F		;; if not 1
	dec AX
@@:
	ret

;; --- Handle a switch (differently).
nn10:
	lodsb
	cmp AL, CR
	je nn7		;; if end of string
	call ifsep
	je nn10		;; if another separator
	mov AL, 0
	stosb
	dec SI
	lodsb
	cmp AL, 'a'
	jb @F		;; if not a lower case letter
	cmp AL, 'z'
	ja @F
	and AL, TOUPPER	;; convert to upper case
@@:
	stosb
	mov AX, '  '
	stosw
	stosw
	stosw
	stosw
	stosw
	xor AX, AX
	stosw
	stosw
	stosw
	stosw
	ret		;; return with AL=0
DoFCB endp
endif

;; --- O command - output to I/O port.
o_cmd proc
	mov BL, 0
	mov AH, AL
	and AH, TOUPPER
	cmp AH, 'W'
	je oo_1
	cmp [machine], 3
	jb oo_2
	cmp AH, 'D'
	jne oo_2
if 1
	mov AH, [SI-2]		;; distiguish 'od' and 'o d'
	and AH, TOUPPER
	cmp AH, 'O'
	jnz oo_2
endif
	inc BX
oo_1:
	inc BX
	call skipwhite
oo_2:
	call getword
	push DX
	call skipcomm0
	cmp BL, 1
	jz oo_4
	cmp BL, 2
	jz oo_5
	call getbyte	;; DL=byte
	call chkeol	;; expect end of line here
	xchg AX, DX	;; AL = byte
	pop DX		;; recover port number
	out DX, AL
	ret
oo_4:
	call getword	;; DX=word
	call chkeol	;; expect end of line here
	xchg AX, DX	;; AX = word
	pop DX
	out DX, AX
	ret
oo_5:
	.386
	call getdword	;; BX:DX=dword
	call chkeol	;; expect end of line here
	push BX
	push DX
	pop EAX
	pop DX
	out DX, EAX
	ret
	.8086
o_cmd endp

if ?PM
;; --- ensure that segment in BX is writeable.
;; --- if it isn't, BX may be set to an alias (scratchsel)
;; --- expects DS, SS = dgroup (for _PM, also ES=dgroup)
;; --- out: Carry=1 if segment not writeable
;; --- called by:
;; ---	setcseipbyte(); write at regs.CS:E/IP + CX
;; ---	writemem(): write byte at BX:E/DX
;; ---	e, f, m cmds
;; ---	parselw()
IsWriteableBX proc
 if _PM
	call ispm_dbg
	jz is_rm
	.286
	push AX
	sizeprf				;; push EDI
	push DI
	sub SP, 8
	mov DI, SP
	sizeprf				;; lea EDI, [DI] (synonym for movzx EDI, DI), 3 bytes long
	lea DI, [DI]
	mov AX, 000bh			;; get descriptor
	int 31h
	jc @F
	test byte ptr [DI+5], 8		;; code segment?
	jz @F
	and byte ptr [DI+5], 0f3h	;; reset CODE+conforming attr
	or byte ptr [DI+5], 2		;; set writable
	mov BX, [scratchsel]
	mov AX, 000ch
	int 31h
@@:
	lea SP, [DI+8]
	sizeprf				;; pop EDI
	pop DI
	pop AX
	.8086
is_rm:
 elseif RING0
	.386
	verw BX
	jz isok
	pushad
	call getlinearbase
	jc error
	cmp BX, DX
	ja error
	mov ESI, EAX
  if FLATSS
	sub ESP, 6
	sgdt [ESP]
  else
	mov BP, SP
	sub SP, 6
	sgdt [BP-6]
  endif
	pop DI
	pop EDI
	and BL, 0f8h
	movzx EBX, BX
	lea ESI, [ESI+EBX]
	movzx EAX, [scratchsel]
	add EDI, EAX
	@dprintf "IsWriteableBX: ESI=%lX, EDI=%lX", ESI, EDI
	push DS
	mov DS, [wFlat]
	lodsd DS:[ESI]
	mov DS:[EDI+0], EAX
	lodsd DS:[ESI]
	and AH, 0f7h	;; data
	or AH, 2		;; writable
	mov DS:[EDI+4], EAX
	pop DS
	popad
	mov BX, [scratchsel]
isok:
 else
    clc
 endif
	ret

 if RING0
error:
	popad
	stc
	ret
 endif
IsWriteableBX endp

 if RING0
;; --- hack to make 'u' work with a real-mode segment
setscratchsel proc
	pushad
  if FLATSS
	sub ESP, 6
	sgdt [ESP]
  else
	mov BP, SP
	sub SP, 6
	sgdt [BP-6]
  endif
	pop AX
	pop EAX
	movzx EBX, [scratchsel]
	add EBX, EAX
  if FLATSS
	movzx EAX, word ptr [EBP+5*4]	;; get DX
  else
	movzx EAX, word ptr [BP+5*4]	;; get DX
  endif
	shl EAX, 4
	push DS
	mov DS, [wFlat]
	mov word ptr [EBX+0], -1
	mov word ptr [EBX+2], AX
	shr EAX, 16
	mov byte ptr [EBX+4], AL
	mov word ptr [EBX+5], 9bh
	mov byte ptr [EBX+7], AH
	pop DS
	popad
	mov BX, [scratchsel]
	ret
setscratchsel endp
 endif

 if _PM
setrmsegm:
	.286
	mov BX, CS:[scratchsel]
setrmaddr:		;; <--- set selector in BX to segment address in DX
	mov CX, DX
	shl DX, 4
	shr CX, 12
	mov AX, 7
	int 31h
	ret
	.8086
 endif

;; --- out: AL= HiByte of attributes of current CS
;; --- out: ZF=1 if descriptor's default-size is 16bit
;; --- called by P, T, U
;; --- modifies EAX, BX
getcsattr proc
	mov BX, [regs.rCS]
getseldefsize::		;; <--- any selector in BX
 if _PM
	mov AL, 00
	cmp [machine], 3
	jb @F
	call ispm_dbe
	jz @F
 endif
	.386
	lar EAX, EBX
	shr EAX, 16
	.8086
@@:
	test AL, 40h
	ret
getcsattr endp

;; --- in: segment/selector in BX
;; --- out: ZF=1 if in real-mode or segment limit is <= 64 kB
getseglimit proc
	push AX
 if _PM
	xor AX, AX
	cmp [machine], 3
	jb is16
	call ispm_dbg
	jz is16
 endif
	.386
	lar EAX, EBX		;; v2.0: first check if expand down
	and AH, 0ch
	cmp AH, 4
	jnz @F
	bt EAX, 22		;; if yes, is default bit set?
	jc is32ed
@@:
	lsl EAX, EBX
	shr EAX, 16
	.8086
is32ed:
is16:
	and AX, AX
	pop AX
	ret
getseglimit endp
endif	;; ?PM

;; --- read [EIP+x] value
;; ---	in:	CX=x
;; ---		[regs.rCS]=CS
;; ---		[regh_(E)IP]=EIP
;; ---	out:	AL=[CS:(E)IP]
;; ---		[E]BX=[E]IP+x
;; --- called by T and G
getcseipbyte proc
	push ES
	mov ES, [regs.rCS]
	sizeprfX		;; mov EBX, [regs.rIP]
	mov BX, [regs.rIP]
if ?PM
	test [bCSAttr], CS32ATTR
	jz @F
	.386
	movsx ECX, CX
	add EBX, ECX
	mov AL, ES:[EBX]
	pop ES
	ret
	.8086
@@:
endif
	add BX, CX
	mov AL, ES:[BX]
	pop ES
	ret
getcseipbyte endp

;; --- set [EIP+x] value
;; --- in: CX=x
;; --- AL=byte to write
;; --- [regs.rCS]=CS
;; --- [regs.rIP]=EIP
;; --- modifies [E]BX
setcseipbyte proc
	push ES
	mov BX, [regs.rCS]
if ?PM
	call IsWriteableBX	;; checks descriptor only, can't detect r/o pages
	jc scib_1
endif
	mov ES, BX
	sizeprfX
	mov BX, [regs.rIP]
if ?PM
	test [bCSAttr], CS32ATTR
	jz is_ip16
	.386
	movsx ECX, CX
	mov ES:[EBX+ECX], AL
scib_1:
	pop ES
	ret
	.8086
is_ip16:
endif
	add BX, CX
	mov ES:[BX], AL
	pop ES
	ret
setcseipbyte endp

;; --- write a byte (AL) at BX:E/DX
;; --- out: AH=old value at that location
;; --- C if byte couldn't be written
;; --- used by A, E, G (breakpoints)
writemem proc
if ?PM
 if _PM
	call ispm_dbg
	jz weip16
 endif
	call IsWriteableBX		;; ensure that BX has a writeable selector
;;	jc err					;; v2.0: don't exit silently, better to cause a GPF
	call getseglimit
	jz weip16
	@dprintf "writemem: BX:EDX=%X:%lX", BX, EDX
	.386
	push DS
	mov DS, BX
	mov AH, [EDX]
	mov [EDX], AL
	cmp AL, [EDX]
	jmp done
	.8086
weip16:
endif
	@dprintf "writemem: BX:DX=%X:%X", BX, DX
	push DS
	mov DS, BX
	push BX
	mov BX, DX
	mov AH, [BX]
	mov [BX], AL
	cmp AL, [BX]
	pop BX
done:
	pop DS
	jnz err
	ret
err:
	stc
	ret
writemem endp

;; --- read byte from memory
;; ---	in:	BX:(E)DX=address
;; ---	out:	AL=byte
;; --- used by e_cmd prompt mode
readmem proc
if ?PM
;;	cmp [bAddr32], 0
	call getseglimit	;; attribute of selector in BX, Z if limit is <= 0ffffh
endif
	push DS
	mov DS, BX
;; --- 14.2.2021: the assumption that the address prefix 67h
;; --- will change "mov AL, [BX]" to "mov AL, [EBX]" was somewhat "obvious",
;; --- but nevertheless WRONG; the first is encoded 8a 07, the latter 67 8a 03!
;;	sizeprfX	;; mov EBX, EDX
;;	mov BX, DX
if ?PM
;;	jz $+3
;;	db 67h		;; mov AL, [EBX]
	jz @F
	.386
	mov AL, [EDX]
	.8086
	jmp readmem_1
@@:
endif
	xchg BX, DX
	mov AL, [BX]
	xchg BX, DX
readmem_1:
	pop DS
	ret
readmem endp

;; --- P command - proceed (i.e., skip over call/int/loop/string instruction).
p_cmd proc
	call parse_pt	;; process arguments

;; --- Do it <CX=count> times.
;; --- First check the type of instruction.
instrloop:
	push CX		;; save CX
	mov DX, 15	;; DL = number of bytes to go; DH = prefix flags.
if ?PM
	call getcsattr
	mov [bCSAttr], AL
	jz @F
	mov DH, PP_ADRSIZ + PP_OPSIZ
	db 66h			;; mov ESI, [regs.rIP]
@@:
endif
	mov SI, [regs.rIP]
pp2:
	call getnextb		;; AL=[CS:(E)IP], EIP++
	mov DI, offset ppbytes
	mov CX, PPLEN
	repne scasb
	jne pp5			;; if not one of these

	mov AL, [DI+PPLEN-1]	;; get corresponding byte in ppinfo
	test AL, PP_PREFIX
	jz @F			;; if not a prefix
	xor DH, AL		;; update the flags
	dec DL
	jnz pp2			;; if not out of bytes
	jmp dotrace		;; more than 15 prefixes will cause a GPF
@@:
	test AL, 40h
	jz @F			;; if no size dependency
	and AL, 3fh
	and DH, PP_OPSIZ	;; for call, operand size 2->4, 4->6
	add AL, DH
@@:
	cbw
	call addeip	;; add AX to instruction pointer in (E)SI
	jmp proceed0	;; we have a skippable instruction here

pp5:
	cmp AL, 0ffh	;; indirect call?
if 0
	jz @F
	jmp dotrace	;; just an ordinary instruction
@@:
else
	jnz dotrace
endif
	call getnextb	;; get MOD REG R/M byte
	and AL, not 8	;; clear lowest bit of REG field (/3 --> /2)
	xor AL, 10h	;; /2 --> /0
	test AL, 38h
if 0
	jz @F
	jmp dotrace	;; if not ff/2 or ff/3
@@:
else
	jnz dotrace	;; if not ff/2 or ff/3
endif
	cmp AL, 0c0h
	jae proceed0	;; if just a register
	test DH, PP_ADRSIZ
	jnz pp6		;; if 32 bit addressing
	cmp AL, 6
	je proceed2	;; if just plain disp16
	cmp AL, 40h
	jb proceed0	;; if indirect register
	cmp AL, 80h
	jb proceed1	;; if disp8[reg(s)]
	jmp proceed2	;; it's disp16[reg(s)]
back2top:
	jmp instrloop	;; back for more

pp6:
	cmp AL, 5
	je proceed4	;; if just plain disp32
	xor AL, 4
	test AL, 7
	jnz @F		;; if no SIB byte
	call inceip
@@:
	cmp AL, 40h
	jb proceed0	;; if indirect register
	cmp AL, 80h
	jb proceed1	;; if disp8[reg(s)]
			;; otherwise, it's disp32[reg(s)]
proceed4:
	call inceip
	call inceip
proceed2:
	call inceip
proceed1:
	call inceip
proceed0:
	call doproceed2
	jmp pp13

;; --- Ordinary instruction.
;; --- Just do a trace.
dotrace:
	or byte ptr [regs.rFL+1], 1	;; set single-step mode
	call run
	cmp [run_int], EXC01MSG
	jne pp15		;; stop if some other interrupt
	call dumpregs
pp13:		;; <--- Common part to finish up.
	pop CX
	loop back2top		;; back for more
	ret
pp15:
	jmp ue_int		;; print message about unexpected interrupt and quit

inceip:
if ?PM
	test [bCSAttr], CS32ATTR
	jz $+3
	db 66h		;; inc ESI
endif
	inc SI
	retn

addeip:
if ?PM
	test [bCSAttr], CS32ATTR
	jz @F
	.386
	movzx EAX, AX
	.8086
	db 66h		;; add ESI, EAX
@@:
endif
	add SI, AX
	retn

;; --- getnextb - Get next byte in instruction stream.
;; --- [E]SI = EIP
getnextb:
	push DS
	mov DS, [regs.rCS]
if ?PM
	test CS:[bCSAttr], CS32ATTR
	jz $+3
	db 67h		;; lodsb [ESI]
endif
	lodsb
	pop DS
	retn

doproceed2:
	mov BX, [regs.rCS]

;; --- Special instruction.
;; --- Set a breakpoint and run until we hit it.
;; --- BX:(E)SI == address where a breakpoint is to be set.
doproceed1::		;; <--- used by T if an int is to be processed
	@dprintf "doproceed1: BX:ESI=%X:%lX", BX, ESI
	mov DI, offset line_out	;; use the same breakpoint structure as in G
	mov AX, 1	;; BP cnt
	stosw
	sizeprfX	;; xchg EAX, ESI
	xchg AX, SI
	sizeprfX	;; stosd
	stosw
	mov AX, BX
	stosw
	mov BP, offset pp_err1	;; abort if BP couldn't be written
	call gg_1	;; use g_cmd to write BP, run program, reset BP
	retn
pp_err1:
	mov DX, offset cantwritebp
	call int21ah9
	jmp cmdloop
p_cmd endp

if _PM
exitdpmi proc
	push AX
if LPMINTS
	mov BP, 2
	cmp dpmi32, 0
	jz @F
	add BP, 2
@@:
	mov SI, offset pmvectors
	mov DI, offset pmints
	mov CX, LPMINTS
nextpmint:
	push CX
	mov BL, [DI]
	sizeprf	;; mov EDX, [SI]
	mov DX, [SI]
	mov CX, DS:[SI+BP]
	mov AX, 205h
	int 31h
	add DI, 3
	add SI, sizeof fword
	pop CX
	loop nextpmint
endif
	pop AX
	ret
exitdpmi endp
endif

if QCMD
;; --- Q command - quit.
q_cmd proc
if _PM
	mov byte ptr [dpmidisable+1], 0	;; disble DPMI hook
	inc [bNoHook2F]			;; avoid a new hook while terminating
endif

;; --- cancel child's process if any
;; --- this will drop to real-mode if debuggee is in pmode
if _PM
;; --- v1.29: DebugX: if debuggee is in pm, 'q' will try to terminate it - else it really quits
	call ispm_dbe
	jz realquit
	and AL, TOUPPER
	cmp AL, 'Q'		;; "QQ" entered?
	jnz @F
	call exitdpmi
@@:
	call freemem
	jmp ue_int
realquit:
endif
	call freemem

if VDD
	mov AX, [hVdd]
	cmp AX, -1
	jz @F
	UnRegisterModule
@@:
endif

if VXCHG
 ifndef VXCHGFLIP
	mov DX, [xmsmove.dsthdl]
	and DX, DX
	jz @F
	push DX
 endif
	mov AL, 0	;; restore debuggee screen
	call swapscreen
 ifndef VXCHGFLIP
	pop DX
	mov AH, 0ah	;; and free XMS handle
	call [xmsdrv]
@@:
 endif
endif
if ALTVID
	call setscreen
endif

;; --- Restore interrupt vectors.
	mov DI, offset intsave
	mov SI, offset inttab
if _PM
	mov CX, NUMINTS+1
else
	mov CX, NUMINTS
endif
nextint:
	lodsb
	push DS
	add SI, 2	;; skip rest of INTITEM
	lds DX, [DI]
	add DI, 4
	cmp AL, 22h
	jz norestore
	mov BX, DS
	and BX, BX
	jz norestore
	mov AH, 25h
	int 21h
norestore:
	pop DS
	loop nextint

if INT22
;; --- Restore termination address.
	mov SI, offset psp22	;; restore termination address
	mov DI, TPIV
	movsw
	movsw
	mov DI, PARENT		;; restore PSP of parent
	movsw
endif

;; --- Really done.

;; --- int 20h sets error code to 0.
;; --- might be better to use int 21h, AX=4cxxh
;; --- and load the error code returned by the debuggee
;; --- into AL.
	int 20h			;; won't work if format == MZ!
	jmp cmdloop		;; returned? then something is terribly wrong.
q_cmd endp
endif

if MMXSUPP
rm_cmd proc
	cmp [has_mmx], 1
	jnz @F
	jmp dumpregsMMX
@@:
	ret
rm_cmd endp
endif

;; --- RX command: toggle mode of R command (16 - 32 bit registers)
rx_cmd proc
	call skipwhite
	cmp AL, CR
	je @F
	jmp rr_err
@@:
	cmp [machine], 3
	jb rx_exit
;;	mov DI, offset line_out
	mov SI, offset regs386
	call copystring	;; SI->DI
	xor [rmode], RM_386REGS
	mov AX, " n"	;; "on"
	jnz @F
	mov AX, "ff"	;; "off"
@@:
	stosw
;;	mov AL, 0	;; v2.0: removed
;;	stosb
	call putsline
rx_exit:
	ret
rx_cmd endp

;; --- RN command: display FPU status
rn_cmd proc
	call skipwhite
	cmp AL, CR
	je @F
	jmp rr_err
@@:
	cmp [has_87], 0
	jz @F
	call dumpregsFPU
@@:
	ret
rn_cmd endp

;; --- R command - manipulate registers.
r_cmd proc
	cmp AL, CR
	jne @F		;; if there's an argument
	jmp dumpregs
@@:
	cmp AH, 'r'
	jnz @F
	and AL, TOUPPER
	cmp AL, 'X'
	je rx_cmd
if MMXSUPP
	cmp AL, 'M'
	je rm_cmd
endif
	cmp AL, 'N'
	je rn_cmd
@@:
;; --- an additional register parameter was given
	dec SI
	lodsw
	and AX, TOUPPER_W
	mov DI, offset regnames
	mov CX, NUMREGNAMES
	repne scasw
	mov BX, DI
	mov DI, offset line_out
	jne rr2			;; if not found in standard register names
	cmp byte ptr [SI], 20h	;; avoid "ES" to be found for "ESI" or "ESP"
	ja rr2
	stosw			;; print register name
	mov AL, ' '
	stosb
	mov BX, [BX+NUMREGNAMES*2-2]
	call skipcomma		;; skip white spaces
	cmp AL, CR
	jne rr1a		;; if not end of line
	push BX			;; save BX for later
	mov AX, [BX]
	call hexword
	call getline0		;; prompt for new value
	pop BX
	cmp AL, CR
	je rr1b			;; if no change required
rr1a:
	call getword
	call chkeol		;; expect end of line here
	mov [BX], DX		;; save new value
rr1b:
	ret

;; --- is it the F(LAGS) register?
rr2:
	cmp AL, 'F'
	jne rr6			;; if not 'f'
	dec SI
	lodsb
	cmp AL, CR
	je rr2b			;; if end of line
	cmp AL, ' '
	je rr2a			;; if white space
	cmp AL, TAB
	je rr2a			;; ditto
	cmp AL, ','
	je rr2a
	jmp errorj9		;; if not, then it's an error
rr2a:
	call skipcomm0
	cmp AL, CR
	jne rr3			;; if not end of line
rr2b:
	call dmpflags
	call getline0		;; get input line (using line_out as prompt)
rr3:
	cmp AL, CR
	je rr1b			;; return if done
	dec SI
	lodsw
	and AX, TOUPPER_W	;; here's the mnemonic
	mov DI, offset flgnams
	mov CX, 16
	repne scasw
	jne rr6			;; if no match
	cmp DI, offset flgnons
	ja rr4			;; if we're clearing
	mov AX, [DI-16-2]
	not AX
	and [regs.rFL], AX
	jmp rr5

rr4:
	mov AX, [DI-32-2]
	or [regs.rFL], AX

rr5:
	call skipcomma
	jmp rr3			;; check if more

;; --- it is neither 16bit register nor the F(LAGS) register.
;; --- check for valid 32bit register name!
rr6:
	cmp [machine], 3
	jb rr_err
	cmp AL, 'E'
	jnz rr_err
	lodsb
	and AL, TOUPPER
	cmp AL, 'S'		;; avoid EDS, ECS, ESS, ... to be accepted!
	jz rr_err
	xchg AL, AH
	mov CX, NUMREGNAMES
	mov DI, offset regnames
	repne scasw
	jne rr_err

;; --- it is a valid 32bit register name
	mov BX, DI
	mov DI, offset line_out
	mov byte ptr [DI], 'E'
	inc DI
	stosw
	mov AL, ' '
	stosb
	mov BX, [BX+NUMREGNAMES*2-2]
	call skipcomma	;; skip white spaces
	cmp AL, CR
	jne rr1aX	;; if not end of line
	push BX
	.386
	mov EAX, [BX+0]
	.8086
	call hexdword
	call getline0	;; prompt for new value
	pop BX
	cmp AL, CR
	je rr1bX	;; if no change required
rr1aX:
	push BX
	call getdword
	mov CX, BX
	pop BX
	call chkeol	;; expect end of line here
	mov [BX+0], DX	;; save new value
	mov [BX+2], CX	;; save new value
rr1bX:
	ret
r_cmd endp

rr_err:
	dec SI		;; back up one before flagging an error
errorj9:
	jmp cmd_error

if RING0
CONST segment
exctab label byte	;; ring 0 exc table used by SK, VC, VT
	db 0, 1, 3
 if CATCHINT06
	db 6
 endif
 if CATCHINT07
	db 7
 endif
 if CATCHINT0C
	db 0ch
 endif
 if CATCHINT0D
	db 0dh
 endif
	db 0eh
SIZEEXCTAB equ $ - offset exctab

noskip db "No exception to skip", 13, 10, '$'
yesskip db "Exception skipped", 13, 10, '$'
CONST ends

;; --- skip exception
;; --- actually, the only exceptions that cannot be skipped are breakpoints set by the debugger itself.
sk_cmd proc
	.386
	mov DL, [run_int+1]
	and DL, 1fh
	mov CX, SIZEEXCTAB
	mov SI, offset exctab
	mov BX, offset intsave
@@:
	lodsb
	cmp DL, AL
	jz found
	add BX, sizeof INTVEC
	loop @B
	mov DX, offset noskip
	jmp int21ah9
found:
	xchg SI, BX
	mov EBX, dword ptr [regs.rSP]
	mov DX, [regs.rSS]
	lar AX, [regs.rCS]
	and AH, 60h				;; exception occured in ring 0?
	jz @F
	mov EBX, [regs.r0Esp]	;; no, use saved r0 stack
	mov DX, [regs.r0SS]
	@dprintf "sk: r3 exc, old r0 SS:ESP=%X:%lX, vec=%X", DX, EBX, SI
	sub EBX, 2*4			;; and correct ESP for saved r3 SS:ESP
@@:
	bt [run_intw], 15	;; exc with error code?
	jnc @F
	sub EBX, 1*4	;; correct error code
@@:
	sub EBX, 3*4	;; correct CS:EIP & efl
	mov dword ptr [regs.rSP], EBX
	mov [regs.rSS], DX
	lodsd
	mov dword ptr [regs.rIP], EAX
	mov dword ptr [u_addr], EAX
	lodsw
	mov [regs.rCS], AX
	mov [u_addr+4], AX

	pushf
	pop AX
	mov byte ptr [regs.rFL+1], AH

	mov [run_int+1], -1		;; reset run_int, so skip is "deactivated" for this time
	mov DX, offset yesskip
	jmp int21ah9
sk_cmd endp
endif

;; --- S command - search for a string of bytes.
s_cmd proc
if RING0
	cmp AH, 's'
	jnz @F
	or AL, TOLOWER
	cmp AL, 'k'
	jz sk_cmd
@@:
endif
	mov BX, [regs.rDS]	;; get search range
	xor CX, CX
	call getrange		;; get address range into BX:(E)DX..BX:(E)CX
	call skipcomm0
	push CX
	push DX
	call getstr		;; get string of bytes, size: DI - (lineout+1)
	pop DX
	pop CX

	sub DI, offset line_out	;; DI = number of bytes to look for ...
	dec DI			;; ... minus one
if ?PM
	cmp [bAddr32], 0
	jz @F
	.386
	@dprintf "s_cmd: BX:EDX=%X:%lX, ECX=%lX, DI=%X", BX, EDX, ECX, DI
	sub ECX, EDX
	movzx EDI, DI
	sub ECX, EDI
	jb errorj9		;; if none
	.8086
	jmp s_cont
@@:
	@dprintf "s_cmd: BX:DX=%X:%X, CX=%X, DI=%X", BX, DX, CX, DI
endif
	sub CX, DX		;; CX = number of bytes in search range minus one
	sub CX, DI		;; number of possible positions of string minus 1
	jb errorj9		;; if none
s_cont:
	call prephack
;;	inc CX			;; CX = number of possible positions of string
	sizeprfX		;; xchg EDX, EDI
	xchg DX, DI		;; set (E)DI to offset
	call dohack		;; set debuggee's int 23/24

sss1:		;; <---- search next occurance
	mov ES, BX		;; set the segment
	mov SI, offset line_out	;; SI = address of search string
	lodsb			;; first character in AL
if ?PM
	cmp [bAddr32], 0
	jz sss1_16
;;	@dprintf "s_cmd scasb: ES:EDI=%X:%lX, ECX=%lX AX=%X", ES, EDI, ECX, AX
	.386
	repne scasb ES:[EDI]
	je @F
	scasb ES:[EDI]
	jnz sss3
@@:
	push ECX
	push EDI
	movzx ECX, DX
	movzx ESI, SI
;;	@dprintf "s_cmd cmpsb: ES:EDI=%X:%lX, ECX=%lX, DS:ESI=%X:%lX", ES, EDI, ECX, DS, ESI
	repe cmpsb DS:[ESI], ES:[EDI]
	pop EDI
	jne @F			;; if not equal
	call displaypos
@@:
	pop ECX
	inc ECX
	loop sss1
	jmp unhack
	.8086
sss1_16:
endif
	repne scasb		;; look for first byte
	je @F
	scasb			;; count in CX was cnt-1
	jne sss3		;; if we're done
@@:
	push CX
	push DI
	mov CX, DX
	repe cmpsb
	pop DI
	jne @F			;; if not equal
	call displaypos
@@:
	pop CX
	inc CX
	loop sss1		;; go back for more
sss3:
	jmp unhack		;; set debugger's int 23/24

;; --- display position
;; --- the search string is in line_out.
;; --- so we have to write to [SI] (which here points just behind search string)
displaypos:
	call unhack		;; set debugger's int 23/24
	push DX
	sizeprfX		;; xchg ESI, EDI
	xchg SI, DI		;; render position right after search string
	mov CX, DI		;; save pos in CX
	mov AX, BX
	call hexword
	mov AL, ':'
	stosb
if ?PM
	cmp [bAddr32], 0
	jz @F
	.386
	lea EAX, [ESI-1]
	.8086
	call hexdword
	jmp s_cont3
@@:
endif
	lea AX, [SI-1]
	call hexword
s_cont3:
	mov AX, (LF shl 8) or CR
	stosw
	mov DX, CX
	mov CX, DI
	sub CX, DX
	call stdout
	pop DX
	sizeprfX		;; mov EDI, ESI
	mov DI, SI
	jmp dohack		;; set debuggee's int 23/24
s_cmd endp

tm_cmd proc
	call skipcomma
	cmp AL, CR
	jz ismodeget
	call getword
	cmp DX, 1
	jna @F
	jmp cmd_error
@@:
	call chkeol		;; expect end of line here
	mov [tmode], DL
;;	ret
ismodeget:
	mov SI, offset tmode0
	mov AL, [tmode]
	and AL, 1
	jz @F
	mov SI, offset tmode1
@@:
	push SI
	add AL, '0'
	mov [tmodes2], AL
	mov SI, offset tmodes
	call copystring
	pop SI
	call copystring
	call putsline
	ret
tm_cmd endp

;; --- T command - Trace.
t_cmd proc
	cmp AL, CR
	jz tt0
	or AL, TOLOWER
	cmp AX, 'tm'
	jz tm_cmd
tt0:
;;	mov [lastcmd], offset tt0
	mov [lastcmd], offset t_cmd
	call parse_pt	;; process arguments
@@:
	push CX
	call trace1
	pop CX
	loop @B
	ret
t_cmd endp

;; --- trace one instruction
trace1 proc
if ?PM
	call getcsattr
	mov [bCSAttr], AL
endif
if _PM
	mov BX, [regs.rIP]
	mov AX, [regs.rCS]
	cmp BX, word ptr [dpmiwatch+0]	;; catch the initial switch to protected mode
	jnz trace1_1
	cmp AX, word ptr [dpmiwatch+2]
	jnz trace1_1
	cmp [bNoHook2F], 0		;; current CS:IP is dpmi entry
	jz @F
	;; if int 2fh is *not* hooked (win3x, win9x, dosemu)
	mov [regs.rIP], offset mydpmientry
	mov [regs.rCS], CS
@@:
	push SS
	pop ES			;; run code until retf
	push DS
	mov BX, [regs.rSP]
	mov DS, [regs.rSS]
	mov SI, [BX+0]
	mov BX, [BX+2]
	pop DS
	call doproceed1
	ret
trace1_1:
endif
	xor CX, CX
	call getcseipbyte
	cmp AL, 0cdh
	jnz isstdtrace
	inc CX
	call getcseipbyte
	cmp AL, 3
	jz isstdtrace
	test byte ptr [tmode], 1	;; TM=1?
	jz trace_int
	cmp AL, 1
	jnz step_int
isstdtrace:
	or byte ptr [regs.rFL+1], 1h	;; set single-step mode
	xor CX, CX
	call getcseipbyte
	push AX
	call run
	pop AX
	cmp AL, 9ch			;; was opcode "pushf"?
	jnz @F
	call clear_tf_onstack
@@:
	cmp [run_int], EXC01MSG
	je tt1_1
	jmp ue_int		;; if some other interrupt (is always "unexpected")
tt1_1:
	call dumpregs
	ret

;; an int is to be processed (TM is 0) to avoid the nasty x86 bug
;; which makes iret cause a debug exception 1 instruction too late
;; a breakpoint is set behind the int

;; if the int will terminate the debuggee (int 21h, AH=4ch)
;; it is important that the breakpoint won't be restored!

trace_int:
	mov CX, 2
	call iswriteablecseip	;; is current CS:IP in ROM?
	jc isstdtrace		;; then do standard trace
	mov BX, [regs.rCS]
if ?PM
	test [bCSAttr], CS32ATTR
	jz $+3
	db 66h	;; mov ESI, dword ptr [regs.rIP]
endif
	mov SI, [regs.rIP]
if ?PM
	jz $+3
	db 66h	;; add ESI, 2
endif
	add SI, 2
	call doproceed1		;; set BP at BX:(E)SI and run debuggee
	ret

;; --- current instruction is int, TM is 1, single-step into the interrupt
;; --- AL=int#
step_int:
	mov BL, AL
if ?PM
 if _PM
	call ispm_dbg
	jz step_int_rm
	mov AX, 204h
	int 31h			;; get vector in CX:(E)DX
	mov BX, CX
	test BL, 4		;; is it a LDT selector?
	jnz @F
	jmp isstdtrace
@@:
	sizeprf		;; mov ESI, EDX
	mov SI, DX
 elseif RING0
	.386
  if FLATSS
	sub ESP, 6
	sidt [ESP]
  else
	push BP
	mov BP, SP
	sub SP, 6
	sidt [BP-6]
  endif
	pop AX
	pop EAX
  ife FLATSS
	pop BP
  endif
	push DS
	mov DS, [wFlat]
	movzx EBX, BL
  if LMODE
	shl BX, 4
  else
	shl BX, 3
  endif
	mov SI, DS:[EBX+EAX+6]
	shl ESI, 16
	mov SI, DS:[EBX+EAX+0]
	mov BX, DS:[EBX+EAX+2]
	pop DS
 endif
	call doproceed1	;; expects BP to be set at BX:(E)SI
	ret
endif
ife RING0
step_int_rm:
	mov BH, 0
	push DS
	xor AX, AX
	mov DS, AX
	shl BX, 1		;; stay 8086 compatible in real-mode!
	shl BX, 1
	cli
	lds SI, [BX+0]
	mov AL, [SI]
	xor byte ptr [SI], 0ffh
	cmp AL, [SI]
	mov [SI], AL
	sti
	jz isrom
	mov BX, DS
	pop DS
	call doproceed1
	ret
isrom:
	mov AX, DS
	pop DS
	xchg SI, [regs.rIP]
	xchg AX, [regs.rCS]
	mov CX, [regs.rFL]
	push DS
	mov BX, [regs.rSP]
	mov DS, [regs.rSS]		;; emulate an int
	sub BX, 6
	inc SI				;; skip int xx
	inc SI
	mov [BX+0], SI
	mov [BX+2], AX
	mov [BX+4], CX
	pop DS
	mov [regs.rSP], BX
	and byte ptr [regs.rFL+1], 0fch	;; clear IF + TF
	jmp tt1_1
endif
trace1 endp

;; --- test if memory at CS:E/IP can be written to.
;; --- return C if not
;; --- used by T cmd.
;; --- in: CX=offset for (E)IP
iswriteablecseip proc
	call getcseipbyte	;; get byte ptr at CS:EIP+CX
	mov AH, AL
	xor AL, 0ffh
	call setcseipbyte
	jc notwriteable
	call getcseipbyte
	cmp AH, AL		;; is it ROM?
	jz notwriteable
	mov AL, AH
	call setcseipbyte
	clc
	ret
notwriteable:
	stc
	ret
iswriteablecseip endp

;; --- clear TF in the copy of flags register onto the stack
clear_tf_onstack proc
	push ES
	mov ES, [regs.rSS]
if ?PM
	mov BX, ES
;;	call getseglimit	;; v1.29: segment limit doesn't matter,
	call getseldefsize	;; check defsize if ESP is to be used.
	jz @F
	.386
	mov EBX, dword ptr [regs.rSP]
	and byte ptr ES:[EBX+1], not 1
	jmp ctos_1
	.8086
@@:
endif
	mov BX, [regs.rSP]
	and byte ptr ES:[BX+1], not 1
ctos_1:
	pop ES
	ret
clear_tf_onstack endp

;; --- Print message about unexpected interrupt, dump registers, and end command.
;; --- This code is used by G, P and T cmds.
ue_int:
	mov DL, [run_int]
	mov DH, 0
	add DX, offset int0msg
	call int21ah9	;; print string
if INT22
	cmp DX, offset progtrm
	je @F			;; if it terminated, skip the registers
endif
	call dumpregs
@@:
	jmp cmdloop		;; back to the start

;; --- "unexpected" exception in real-mode inside debugger
ife RING0
 if CATCHINT07 or CATCHINT0C or CATCHINT0D
ue_intxx:
  if EXCCSIP
	pop CX
	pop DX
  endif
	push CS
	pop SS
	mov SP, CS:[top_sp]
	push CX	;; IP
	push DX	;; CS
	push AX	;; msg
;; --- fall thru
 endif
endif


if ?PM or CATCHINT07 or CATCHINT0C or CATCHINT0D
;; --- "unexpected" exception occured inside debugger
;; --- [SP] = msg, CS, [E]IP
ue_intx proc
	cld
	@RestoreSeg DS
	call unhack		;; set debugger's int 23/24
if ?PM
	test [disflags], DIS_I_MEMACC
	jz @F
	mov [disflags], 0
	mov DX, offset crlf
	call int21ah9
@@:
endif
	pop DX
	add DX, offset int0msg
	call int21ah9	;; print string
if EXCCSIP
	push DS
	pop ES
	mov DI, offset line_out
	mov SI, offset excloc	;; "CS:IP="
	call copystring
	pop AX
	call hexword
	mov AL, ':'
	stosb
 if EXCCSEIP
	pop EAX
	call hexdword
 else
	pop AX
	call hexword
 endif
	call putsline
endif
	jmp cmdloop
ue_intx endp
endif

;; --- U command - disassemble.
u_cmd proc
;;	mov [lastcmd], offset lastuu
	mov [lastcmd], offset u_cmd
	cmp AL, CR
	je lastuu		;; if no address was given
	sizeprfX		;; xor ECX, ECX
	xor CX, CX
	mov CL, 20h		;; default length
	mov BX, [regs.rCS]
	call getrange	;; get address range into BX:(E)DX
	call chkeol		;; expect end of line here
	sizeprfX		;; mov [u_addr+0], EDX
	mov [u_addr+0], DX
	mov [u_addr+4], BX
	@dprintf "u_cmd: u_addr=%X:%lX, ECX=%lX", BX, EDX, ECX
	jmp u_cxset

lastuu:
	sizeprfX	;; mov ECX, [u_addr]
	mov CX, [u_addr]
	sizeprfX	;; add ECX, 1fh
	add CX, 1fh
	jnc @F		;; if no overflow
	sizeprfX	;; or ECX, -1
	or CX, -1
@@:
;; --- At this point, E/CX holds the last address, and E/DX the address.
u_cxset:
	sizeprfX
	inc CX
if ?PM
	mov BX, [u_addr+4]
	call getseldefsize
 if LMODE
	test AL, 40h or 20h
 endif
	jz uu_16
	.386
uuloop32:
	push ECX
	push EDX
	call disasm1
	pop EBX
	pop ECX
	mov EAX, dword ptr [u_addr]
	mov EDX, EAX
	sub EAX, ECX		;; current position - end
	sub EBX, ECX		;; previous position - end
	cmp EAX, EBX
	jnb uuloop32		;; if we haven't reached the goal
	ret
	.8086
uu_16:
endif
uuloop16:
	push CX
	push DX
	call disasm1	;; do it
	pop BX
	pop CX
	mov AX, [u_addr]
	mov DX, AX
	sub AX, CX	;; current position - end
	sub BX, CX	;; previous position - end
	cmp AX, BX
	jnb uuloop16	;; if we haven't reached the goal
	ret
u_cmd endp

if WCMD
lockdrive:		;; lock logical volume
	push AX
	push BX
	push CX
	push DX
	mov BL, AL
	inc BL
	mov BH, 0	;; lock level (0 means what?)
	mov CX, 084ah	;; isn't this for non-FAT32 drives only?
	mov DX, 0001h	;; permission flags (1=allow writes)
	mov AX, 440dh
	int 21h
	pop DX
	pop CX
	pop BX
	pop AX
	ret
unlockdrive:
	push AX
	push BX
	push CX
	push DX
	mov BL, AL
	inc BL
;;	mov BH, 0	;; BH has no meaning for unlock
	mov CX, 086ah	;; isn't this for non-FAT32 drives only?
;;	mov DX, 0001h
	mov AX, 440dh
	int 21h
	pop DX
	pop CX
	pop BX
	pop AX
	ret

;; --- W command - write a program, or disk sectors, to disk.
w_cmd proc
	call parselw	;; parse L and W argument format (out: BX:(E)DX=address)
if WCMDFILE
	jz write_file	;; if request to write program
else
	jz cmd_error	;; no support to write program
endif
if NOEXTENDER
	call ispm_dbg
	jz @F
	call isextenderavailable	;; in protected-mode, DOS translation needed
	jnc @F
	mov DX, offset nodosext
	jmp int21ah9
@@:
endif
	cmp CS:[usepacket], 2
	jb ww0_1
	mov DL, AL	;; A=0, B=1, C=2, ...
	mov SI, 6001h	;; write, assume "file data"
if VDD
	mov AX, [hVdd]
	cmp AX, -1
	jnz callvddwrite
endif
	inc DL		;; A=1, B=2, C=3, ...
	call lockdrive
	mov AX, 7305h	;; DS:(E)BX->packet
	stc
	int 21h		;; use int 21h here, not doscall
	pushf
	call unlockdrive
	popf
	jmp ww0_2
if VDD
callvddwrite:
	mov CX, 5
	add CL, [dpmi32]
	DispatchCall
	jmp ww0_2
endif
ww0_1:
	int 26h
ww0_2:
	mov CX, "rw"		;; CX:DX="writ"
	mov DX, "ti"
;;	jmp disp_diskresult	;; fall thru to disp_diskresult
w_cmd endp

;; --- display disk access result (C if error)
;; --- CX:DX="read"/"writ"
disp_diskresult proc
	mov BX, SS		;; restore segment registers
	mov DS, BX
	mov SP, [top_sp]
	mov ES, BX
	jnc ww3		;; if no error
	mov word ptr [szDrive+1], CX
	mov word ptr [szDrive+3], DX
	add [driveno], 'A'
	cmp AL, 0ch
	jbe @F		;; if in range
	mov AL, 0ch
@@:
	cbw
;;	shl AX, 1	;; v2.0: removed - dskerrs is a byte offset table
	xchg SI, AX
	mov AL, [SI+dskerrs]
	mov SI, offset dskerr0
	add SI, AX
	mov DI, offset line_out
	call copystring
	mov SI, offset szDrive
	call copystring
	call putsline
ww3:
	jmp cmdloop		;; can't ret because stack is wrong
disp_diskresult endp
endif

if WCMDFILE
;; --- Write to file.
;; --- First check the file extension.
;; --- size of file is in client's BX:CX,
;; --- default start address is DS:100h
write_file proc
	mov AL, [fileext]	;; get flags of file extension
	test AL, EXT_EXE + EXT_HEX
	jz @F				;; if not EXE or HEX
	mov DX, offset nowhexe
	jmp ww6
@@:
	cmp AL, 0
	jnz ww7			;; if extension exists
	mov DX, offset nownull
ww6:
	jmp int21ah9

;; --- File extension is OK; write it.
;; --- First, create the file.
ww7:
if _PM
	call ispm_dbg
	jz @F
	mov DX, offset nopmsupp	;; cant write it in protected-mode
	jmp int21ah9
@@:
endif
	mov BP, offset line_out
	cmp DH, 0feh
	jb @F			;; if DX < fe00h
	sub DH, 0feh		;; DX -= 0xfe00
	add BX, 0fe0h
@@:
	mov [BP+10], DX		;; save lower part of address in line_out+10
	mov SI, BX		;; upper part goes into SI
	mov AH, 3ch		;; create file
	xor CX, CX		;; no attributes
	mov DX, DTA
	call doscall
	jc io_error		;; if error
	push AX			;; save file handle

;; --- Print message about writing.
	mov DX, offset wwmsg1
	call int21ah9		;; print string
	mov AX, [regs.rBX]
	cmp AX, 10h
	jb @F			;; if not too large
	xor AX, AX		;; too large: zero it out
@@:
	mov [BP+8], AX
	or AX, AX
	jz @F
	call hexnyb		;; convert to hex and print
@@:
	mov AX, [regs.rCX]
	mov [BP+6], AX
	call hexword
	call puts		;; print size
	mov DX, offset wwmsg2
	call int21ah9		;; print string

;; --- Now write the file.
;; --- Size remaining is in line_out+6.
	pop BX			;; recover file handle
	mov DX, [BP+10]		;; address to write from is SI:DX
ww11:
	mov AX, 0fe00h
	sub AX, DX
	cmp byte ptr [BP+8], 0
	jnz @F			;; if more than 0fe00h bytes remaining
	cmp AX, [BP+6]
	jb @F			;; ditto
	mov AX, [BP+6]
@@:
	xchg AX, CX		;; mov CX, AX
	mov DS, SI
	mov AH, 40h		;; write to file
	int 21h			;; use int, not doscall
	push SS			;; restore DS
	pop DS
	cmp AX, CX
	jne ww13		;; if disk full
	xor DX, DX		;; next time write from xxxx:0
	add SI, 0fe0h		;; update segment pointer
	sub [BP+6], CX
	lahf
	sbb byte ptr [BP+8], 0
	jnz ww11		;; if more to go
	sahf
	jnz ww11		;; ditto
	jmp ww14		;; done

ww13:
	mov DX, offset diskful
	call int21ah9		;; print string
	mov AH, 41h		;; unlink file
	mov DX, DTA
	call doscall

;; --- Close the file.
ww14:
	mov AH, 3eh		;; close file
	int 21h
	ret
write_file endp
endif

if LCMDFILE or WCMDFILE
;; --- Error opening file.
;; --- This is also called by the load command.
io_error:
	cmp AX, 2
	mov DX, offset doserr2	;; File not found
	je @F
	cmp AX, 3
	mov DX, offset doserr3	;; Path not found
	je @F
	cmp AX, 5
	mov DX, offset doserr5	;; Access denied
	je @F
	cmp AX, 8
	mov DX, offset doserr8	;; Insufficient memory
	je @F
	mov DI, offset openerr1
	call hexword
	mov DX, offset openerr	;; Error ____ opening file
@@:
;; --- fall thru
endif

int21ah9:
if 1	;; v2.0: check InDos, if set use stdout()
	call InDos
	jnz use_stdout
endif
	mov AH, 9
	call doscall
	ret
if 1	;; v2.0: get size of $-string DS:DX, then call stdout; SI, CX not modified
use_stdout:
	push SI
	push CX
	mov SI, DX
@@:
	lodsb
	cmp AL, '$'
	jnz @B
	dec SI
	sub SI, DX
	mov CX, SI
	call stdout
	pop CX
	pop SI
	ret
endif

if XCMDS
;; --- X commands - manipulate EMS memory.

;; --- XA - Allocate EMS.
;; --- DX = pages
xa proc
	call chkeol		;; expect end of line here
	mov BX, DX
	mov AH, 43h		;; allocate handle
	and BX, BX
	jnz @F
	mov AX, 5a00h		;; use the EMS 4.0 version to alloc 0 pages
@@:
	call emscall
	push DX
	mov SI, offset xaans	;; "Handle created: "
	call copystring
	pop AX
	call hexword
	jmp putsline		;; print string and return
xa endp

;; --- XD - Deallocate EMS handle.
;; --- DX = handle
xd proc
	call chkeol		;; expect end of line here
	mov AH, 45h		;; deallocate handle
	call emscall
	push DX
	mov SI, offset xdans	;; "Handle deallocated: "
	call copystring
	pop AX
	call hexword
	jmp putsline	;; print string and return
xd endp

;; --- x main dispatcher
x_cmd proc
	cmp AL, '?'
	je xhelp	;; if a call for help
	push AX
	call emschk
	pop AX
	or AL, TOLOWER
	cmp AL, 's'
	je xs		;; if XS command
	push AX
	call skipcomma
	call getword
	pop CX
	cmp CL, 'a'
	je xa		;; if XA command
	cmp CL, 'd'
	je xd		;; if XD command
	cmp CL, 'r'
	je xr		;; if XR command
	cmp CL, 'm'
	je xm		;; if XM command
	jmp cmd_error

xhelp:
	mov DX, offset xhelpmsg
	mov CX, size_xhelpmsg
	jmp stdout	;; print string and return
x_cmd endp

;; --- XR - Reallocate EMS handle.
;; --- DX = first argument (=handle)
xr proc
	mov BX, DX
	call skipcomma
	call getword		;; get count argument into DX
	call chkeol		;; expect end of line here
	xchg BX, DX
	mov AH, 51h		;; reallocate handle
	call emscall
	mov SI, offset xrans	;; "Handle reallocated: "
	call copystring
	jmp putsline		;; print string and return
xr endp

;; --- XM - Map EMS memory to physical page.
;; --- DX = first argument [=logical page (ffff means unmap)]
xm proc
	mov BX, DX	;; save it in BX
	call skipcomm0
	call getbyte	;; get physical page (DL)
	push DX
	call skipcomm0
	call getword	;; get handle into DX
	call chkeol	;; expect end of line
	pop AX		;; recover physical page into AL
	push AX
	mov AH, 44h	;; function 5 - map memory
	call emscall
	mov SI, offset xmans
	call copystring
	mov BP, DI
	mov DI, offset line_out + xmans_pos1
	xchg AX, BX	;; mov AX, BX
	call hexword
	mov DI, offset line_out + xmans_pos2
	pop AX
	call hexbyte
	mov DI, BP
	jmp putsline	;; print string and return
xm endp

;; --- XS - Print EMS status.
xs proc
	lodsb
	call chkeol		;; no arguments allowed

;; First print out the handles and handle sizes.
;; This can be done either by trying all possible handles or getting a handle table.
;; The latter is preferable, if it fits in memory.

	mov AH, 4bh		;; function 12 - get handle count
	call emscall
	cmp BX, (real_end - line_out)/4
	jbe xs3			;; if we can do it by getting the table

	xor DX, DX		;; start handle
nexthdl:
	mov AH, 4ch		;; function 13 - get handle pages
	int 67h
	cmp AH, 83h		;; error "invalid handle"?
	je xs2			;; if no such handle
	or AH, AH
	jz @F
	jmp ems_err		;; if other error
@@:
	xchg AX, BX		;; mov AX, BX
	call hndlshow
xs2:
	inc DL
	jnz nexthdl		;; if more to be done

	jmp xs5			;; done with this part

;; --- Get the information in tabular form.

xs3:
	mov AH, 4dh		;; function 14 - get all handle pages
	mov DI, offset line_out
	call emscall
	and BX, BX		;; has returned no of entries in BX
	jz xs5
	mov SI, DI
@@:
	lodsw
	xchg AX, DX
	lodsw
	call hndlshow
	dec BX
	jnz @B			;; if more to go

xs5:
	mov DX, offset crlf
	call int21ah9		;; print string

;; Next print the mappable physical address array.
;; The size of the array shouldn't be a problem.
	mov AX, 5800h		;; function 25 - get mappable phys. address array
	mov DI, offset line_out	;; address to put array
	call emscall
	mov DX, offset xsnopgs
	jcxz xs7		;; NO mappable pages!

	mov SI, DI
xs6:
	push CX
	lodsw
	mov DI, offset xsstr2b
	call hexword
	lodsw
	mov DI, offset xsstr2a
	call hexbyte
	mov DX, offset xsstr2
	mov CX, size_xsstr2
	call stdout		;; print string
	pop CX			;; end of loop
	test CL, 1
	jz @F
	mov DX, offset crlf	;; blank line
	call int21ah9		;; print string
@@:
	loop xs6
	mov DX, offset crlf	;; blank line
xs7:
	call int21ah9		;; print string

;; --- Finally, print the cumulative totals.
	mov AH, 42h		;; function 3 - get unallocated page count
	call emscall
	mov AX, DX		;; total pages available
	sub AX, BX		;; number of pages allocated
	mov BX, offset xsstrpg
	call sumshow		;; print the line
	mov AH, 4bh		;; function 12 - get handle count
	call emscall
	push BX

;; --- try EMS 4.0 function 5402h to get total number of handles
	mov AX, 5402h
	int 67h			;; don't use emscall, this function may fail!
	mov DX, BX
	cmp AH, 0
	jz @F
	mov DX, 0ffh		;; total number of handles
@@:
	pop AX			;; AX = number of handles allocated
	mov BX, offset xsstrhd
	call sumshow	;; print the line
	ret		;; done
xs endp

;; --- Call EMS
;; --- in case of error, return to cmd loop
emscall proc
if _PM
	call ispm_dbg
	jz ems_rm
	.286
	invoke intcall, 67h, CS:[pspdbg]
	jmp ems_call_done
	.8086
ems_rm:
endif
	int 67h
ems_call_done:
	and AH, AH	;; error?
	js ems_err
	ret		;; return if OK

emscall endp

;; --- ems error in AH

ems_err proc
	mov AL, AH
	cmp AL, 8bh
	jg ce2		;; if out of range
	cbw		;; 80->ff80 ... 8b->ff8b
	mov BX, AX
	shl BX, 1	;; ff80->ff00 ... ff8b->ff16
	mov SI, [emserrs+100h+BX]
	or SI, SI
	jnz ems_err3	;; if there's a word there
ce2:
	mov DI, offset emserrxa
	call hexbyte
	mov SI, offset emserrx
ems_err3::
	mov DI, offset line_out
	call copystring	;; SI->DI
	call putsline
	jmp cmdloop
ems_err endp

;; --- Check for EMS
emschk proc
if _PM
	call ispm_dbg
	jz emschk1
	mov BL, 67h
	mov AX, 0200h
	int 31h
	mov AX, CX
	or AX, DX
	jz echk2
	jmp emschk2
emschk1:
endif
	push ES
	mov AX, 3567h	;; get interrupt vector 67h
	int 21h
	mov AX, ES
	pop ES
	or AX, BX
	jz echk2
emschk2:
	mov AH, 46h	;; get version
;;	int 67h
	call emscall
	and AH, AH
	jnz echk2
	ret
echk2:
	mov SI, offset emsnot
	jmp ems_err3
emschk endp

;; HNDLSHOW - Print XS line giving the handle and pages allocated.
;;	Entry	DX	Handle
;;		AX	Number of pages
;;	Exit	Line printed
;;	Uses	AX, CL, DI.
hndlshow proc
	mov DI, offset xsstr1b
	call hexword
	mov AX, DX
	mov DI, offset xsstr1a
	call hexword
	push DX
	mov DX, offset xsstr1
	mov CX, size_xsstr1
	call stdout
	pop DX
	ret
hndlshow endp

;; SUMSHOW - Print summary line for XS command.
;;	Entry	AX	Number of xxxx's that have been used
;;		DX	Total number of xxxx's
;;		BX	Name of xxxx
;;	Exit	String printed
;;	Uses	AX, CX, DX, DI
sumshow proc
	mov DI, offset line_out
	call trimhex		;; AX (skip leading zeros)
	mov SI, offset xsstr3	;; " of a total "
	call copystring
	xchg AX, DX		;; mov AX, DX
	call trimhex
	mov SI, offset xsstr3a	;; " EMS "
	call copystring
	mov SI, BX		;; "pag"/"handl"
	call copystring
	mov SI, offset xsstr3b	;; "es have been allocated"
	call copystring
	jmp putsline
sumshow endp

;; TRIMHEX - Print word without leading zeroes.
;;	Entry	AX	Number to print
;;		DI	Where to print it
;;	Uses	AX, CX, DI.
trimhex proc
	call hexword
	push DI
	sub DI, 4		;; back up DI to start of word
	mov CX, 3
	mov AL, '0'
@@:
	scasb
	jne @F			;; return if not a '0'
	mov byte ptr [DI-1], ' '
	loop @B
@@:
	pop DI
	ret
trimhex endp
endif

;; --- syntax error handler.
;; --- in: SI->current char in line_in
cmd_error proc
	mov CX, SI
	sub CX, offset line_in+4
	add CX, [promptlen]
	mov DI, offset line_out
	mov DX, DI
	cmp CX, 127
	ja @F			;; if we're really messed up
	inc CX			;; number of spaces to skip
	mov AL, ' '
	rep stosb
@@:
	mov SI, offset errcarat
	mov CL, sizeof errcarat
	rep movsb
	call putsline		;; print string
	jmp [errret]
cmd_error endp

if LCMDFILE
;; --- FREEMEM - cancel child process
freemem proc

	mov [regs.rCS], CS
	mov [regs.rIP], offset fmem2
	mov [regs.rFL], 202h	;; v1.29: ensure TF is clear (TF=1 may cause "memory corrupt" error if returning to DOS)
 if _PM
	xor AX, AX
	mov [regs.rIP+2], AX
	mov [regs.rSP+2], AX
 endif
	mov [regs.rSS], SS
	push AX
	mov [regs.rSP], SP	;; save SP-2
	pop AX
	call run
	ret
fmem2:
 if _PM
	mov AX, 4cffh
 else
	mov AX, 4c00h		;; quit
 endif
	int 21h
freemem endp

 if INT2324
;; --- setint2324 is called by "run", to set debuggee's int 23/24.
;; --- Don't use int 21h here, DOS might be "in use".
;; --- Registers may be modified - will soon be set to debuggee's...
;; --- counterpart is getint2324().
setint2324 proc
	mov SI, offset run2324
  if _PM
	call ispm_dbg
	jnz si2324pm
  endif
	push ES

	xor DI, DI
	mov ES, DI
	mov DI, 23h*4
	movsw
	movsw
	movsw
	movsw

  if _PM
	call InDos
	jnz @F
	call hook2f
@@:
  endif

	pop ES
	ret
  if _PM
si2324pm:
	mov BX, 0223h
@@:
	sizeprf		;; mov EDX, [SI+0]
	mov DX, [SI+0]
	mov CX, [SI+4]
	mov AX, 205h
	int 31h
	add SI, 6
	inc BL
	dec BH
	jnz @B
	ret
  endif
setint2324 endp
 endif	;; INT2324
endif	;; LCMDFILE

if RING0
	.386
checksegm proc
	lar AX, [regs.rCS]
	jnz error
	test AH, 8
	jz error
	lar AX, [regs.rSS]
	jnz error
	test AH, 8
	jnz error

	mov CX, 4
	mov SI, offset regs.rDS
nextitem:
	lodsw
	and AX, 0fffch
	jz @F
	lar AX, AX
	jnz error
@@:
	loop nextitem
	ret
error:
	stc
	ret
checksegm endp
endif

;; --- This is the routine that starts up the running program.
run proc
if RING0
;; --- check segment values, since there's no stack switch if a GPF occurs.
	call checksegm
	mov DX, offset segerr
	jc int21ah9
	mov AL, 0
	call srscratch		;; restore scratch GDT entry
endif
	call seteq		;; set CS:E/IP to '=' address

;; --- set debuggee context
if VXCHG
	mov AL, 0		;; restore debuggee screen
	call swapscreen
endif
if ALTVID
	call setscreen
endif
if LCMDFILE
	mov BX, [pspdbe]
	call setpsp		;; set debuggee's PSP
 if INT2324
	call setint2324		;; set debuggee's int 23/24
 endif
endif
if _PM
	call setdbeexc0d0e
endif

if FLATSS
	mov [run_sp], ESP	;; save stack position
else
	mov [run_sp], SP	;; save stack position
endif
ife (DRIVER or BOOTDBG or RING0)
 if 1
	;; 16.2.2021: check if saved SS is debugger's SS. If no, don't adjust saved SP.
	;; SS may be != saved SS if debugger is stopped in protected-mode -
	;; then the current DPMI real-mode stack may be stored in SPSAV.
	mov AX, SS
	cmp AX, DS:[SPSAV+2]
	jnz @F
 endif
	sub SP, [spadjust]
	mov DS:[SPSAV], SP
@@:
endif
ife RING0
	cli
endif
if FLATSS
	push DS
	pop SS
endif
	mov SP, offset regs
ife RING0
	cmp [machine], 3
	jb @F
	.386
	popad
	pop ES		;; temporary load DS value into ES (to make sure it is valid)
	pop ES		;; now load the true value for ES
	pop FS
	pop GS
	jmp loadss
	.8086
@@:
	pop DI
	pop SI		;; skip hi EDI
	pop SI
	pop BP		;; skip hi ESI
	pop BP
	add SP, 6	;; skip hi EBP+reserved
	pop BX
	pop DX		;; skip hi EBX
	pop DX
	pop CX		;; skip hi EDX
	pop CX
	pop AX		;; skip hi ECX
	pop AX
	add SP, 2	;; skip hi EAX
	pop ES		;; that's DS
	pop ES
	add SP, 2*2	;; skip places for FS, GS
else
	.386
if 0	;; LMODE
;; --- FS and GS might be "unset" (still containing real-mode values)
;; --- so check if value has changed and if not, don't write the regs
	mov AX, FS
	cmp AX, [regs.rFS]
	jz @F
	mov FS, [regs.rFS]
@@:
	mov AX, GS
	cmp AX, [regs.rGS]
	jz @F
	mov GS, [regs.rGS]
@@:
endif
	lar AX, [regs.rCS]
	and AH, 60h
	popad
	pop ES
	pop ES
if 0	;; LMODE
	lea SP, [ESP+2+2]
else
	pop FS
	pop GS
endif
	jz @F
	lss ESP, [regs.r0SSEsp]		;; debuggee runs in non-privileged mode, so
	push dword ptr [regs.rSS]	;; create a full iretd stack frame with SS:ESP
	push dword ptr [regs.rSP]
	jmp r0exit
@@:
endif
loadss:
	pop SS
patch_movsp label byte		;; patch with 3eh (=DS:) if cpu < 386
	db 66h			;; mov ESP, [regs.rSP]
	mov SP, [regs.rSP]	;; restore program stack
r0exit:
	sizeprf			;; push dword ptr [regs.rFL]
	push [regs.rFL]
	sizeprf			;; push dword ptr [regs.rCS]
	push [regs.rCS]
	sizeprf			;; push dword ptr [regs.rIP]
	push [regs.rIP]
	mov [bInDbg], 0
if RING0
	mov DS, [regs.rDS]
else
	test byte ptr [regs.rFL+1], 2	;; IF set?
	mov DS, [regs.rDS]
	jz @F
	sti				;; required for ring3 protected mode if IOPL==0
@@:
patch_iret label byte	;; patch with cfh (=iret) if cpu < 386
endif
	.386
	iretd				;; jump to program
	.8086
run endp

;; --- debugger entries
if RING0
 if LMODE
	include <TrapPL.inc>
 else
	include <TrapP.inc>
 endif
else
	include <TrapR.inc>
endif

;; --- fall thru
;; --- also: entry DPMI protected-mode
;; --- in: SS:SP=regs.rSS
intrtn proc
;; --- dword pushs are safe here
	cmp CS:[machine], 3
	jb @F
	.386
ife RING0
	pushfd
	popf		;; skip LoWord(EFL)
	pop word ptr SS:[regs.rFL+2]
endif
	push 0
	pushf
	popfd		;; clear HiWord(EFL) inside debugger (resets AC flag)
	push GS
	push FS
	push ES
	push DS
	pushad
	jmp intrtn1
	.8086
@@:
	sub SP, 2*2	;; skip space for GS, FS
	push ES
	push DS
	push AX
	push AX
	push CX
	push CX
	push DX
	push DX
	push BX
	push BX
	sub SP, 6
	push BP
	push SI
	push SI
	push DI
	push DI
intrtn1::		;; <--- entry for int 22
if RING0
	.386
 if FLATSS
	mov SS, CS:[wFlat]
	mov ESP, CS:[run_sp]	;; restore running stack
 else
	movzx ESP, CS:[run_sp]	;; restore running stack
 endif
else
	mov SP, CS:[run_sp]	;; restore running stack
endif
	cld
	@RestoreSeg DS
ife RING0
	sti			;; interrupts back on
endif

;; if ?PM
 if _PM
;; --- calling int 2fh here is a problem, since breakpoints aren't reset yet.
;; --- this makes it impossible to trace this interrupt.
  if 0	;; DPMIMSW
	mov AX, 1686h		;; actually, fn 1686h tells if int 31h API is available
	int 2fh
	cmp AX, 1
	sbb AX, AX
  else
	mov AX, CS
	sub AX, [pspdbg]	;; Z=rm, NZ=pm
	cmp AX, 1		;; C=rm, NC=pm
	cmc			;; NC=rm, C=pm
	sbb AX, AX		;; 0=rm, -1=pm
  endif
	mov [regs.msw], AX	;; 0000=real-mode, ffff=protected-mode
 endif
;; endif

ife (BOOTDBG or RING0)
	call getpsp
	mov [pspdbe], BX
endif

	push DS
	pop ES
	mov [bInDbg], 1		;; v2.0: must be set before setdbgexc0d0e

;; --- set debugger context

if INT2324
	call getint2324		;; save debuggee's int 23/24, set debugger's int 23/24
endif
if _PM
	call setdbgexc0d0e
endif
if RING0
	cmp [run_int], EXC0EMSG
	jnz @F
	call rendercr2		;; add value of CR2 to msg
@@:
	mov AL, 1
	call srscratch		;; save GDT scratch entry
endif

if LCMDFILE
	call setpspdbg		;; set debugger's PSP
endif
	and byte ptr [regs.rFL+1], not 1	;; clear single-step interrupt

;;	mov [bInDbg], 1		;; v2.0: do this earlier (see above)
if INT22
	cmp [run_int], INT22MSG
	jnz @F
 if _PM
	mov [cssel], 0		;; reset flag 'initial switch has occured'
 endif
	mov AH, 4dh
	int 21h
	mov DI, offset progexit
	call hexword
@@:
endif
ifdef FORCETEXT
	call checkgfx		;; see if current mode is gfx, set to text if yet
endif
if VXCHG
	mov AL, 1		;; restore debugger screen
	call swapscreen
 ifndef VXCHGFLIP
	push ES
	mov AX, 0040h
	mov ES, AX
	mov AL, ES:[84h]	;; did the number of screen rows change?
	mov BH, ES:[62h]	;; BH=video page
	mov [vpage], BH
	cmp AL, [vrows]
	mov [vrows], AL
	jz @F
	mov DH, AL	;; yes. we cannot fully restore, but at least clear
	mov DL, 0	;; bottom line to ensure the debugger displays are seen.
	mov AH, 2	;; set cursor pos
	int 10h
	mov BL, 07h	;; BL=attribute, BH=video page
	mov CX, 80	;; CX=columns
	mov AX, 0920h	;; AL=char to display
	int 10h
@@:
	pop ES
 else
;; --- with page flips, there are problems with many BIOSes:
;; --- the debugger displays may get the color of the debuggee!
;; --- if there's any trick to convince the BIOS not to do this,
;; --- implement it here!
    mov [vpage], 1
 endif
endif
if ALTVID
	call setscreen
endif
	ret

ifdef FORCETEXT
checkgfx:
	mov DX, 3ceh		;; see if in graphics mode
	in AL, DX
	mov BL, AL
	mov AL, 6
	out DX, AL
	inc DX
	in AL, DX
	xchg BL, AL
	dec DX
	out DX, AL
	test BL, 1
	jz @F
	mov AX, 0003h
	int 10h
@@:
	retn
endif
intrtn endp

if VXCMD
	.386
CONST segment
notrappedexc db "No exc to (un)trap", 13, 10, '$'
CONST ends

getexc proc
	call skipwhite
	call getbyte		;; get byte into DL
	call chkeol		;; expect end of line here
	mov SI, offset exctab
	mov CX, SIZEEXCTAB
nextitem:
	lodsb
	cmp AL, DL
	loopnz nextitem
	jz @F
	pop AX
	mov DX, offset notrappedexc
	jmp int21ah9
@@:
	mov DH, 0
	ret
getexc endp

;; --- clear trapped vector: VC exc#
vc_cmd proc
	call getexc
	btr [wTrappedExc], DX
	ret
vc_cmd endp

;; --- trap vector: VT exc#
vt_cmd proc
	call getexc
	bts [wTrappedExc], DX
	ret
vt_cmd endp

;; --- list trapped vectors: VL
vl_cmd proc
	call skipwhite
	call chkeol			;; expect end of line here
	mov SI, offset exctab
	mov BX, offset intsave
	mov CX, SIZEEXCTAB
nextitem:
	mov DI, offset line_out
	push CX
	lodsb
	movzx DX, AL
	call hexbyte
	mov AL, ' '
	stosb
	mov AX, [BX+4]
	call hexword
	mov AL, ':'
	stosb
	mov EAX, [BX+0]
	call hexdword
	bt [wTrappedExc], DX
	jc @F
	mov AL, '*'
	stosb
@@:
	call putsline
	pop CX
	add BX, sizeof INTVEC
	loop nextitem
	ret
vl_cmd endp

	.8086

endif

if VXCHG
;; --- show debuggee screen, wait for a keypress, then restore debugger screen
v_cmd proc
 if VXCMD
	cmp AH, 'v'
	jnz @F
	or AL, TOLOWER
	cmp AL, 'c'
	jz vc_cmd
	cmp AL, 'l'
	jz vl_cmd
	cmp AL, 't'
	jz vt_cmd
@@:
 endif
	cmp AL, CR
	jnz cmd_error
	mov AL, 0
	call swapscreen
 if 0	;; ndef VXCHGBIOS	;; v2.0: no longer needed, swapscreen has set cursor
;; --- swapscreen has restored screen and cursor pos, but we want
;; --- the cursor be shown on the screen - so set it thru BIOS calls.
	mov AH, 0fh	;; get current mode (and video page in BH)
	int 10h
	mov AH, 3	;; get cursor pos of page in BH
	int 10h
	mov AH, 2	;; set cursor pos of page in BH
	int 10h
 endif
	mov AH, 10h
if RING0
	.386
	call CS:[int16vec]
	.8086
else
	int 16h
endif
	mov AL, 1
	call swapscreen
	ret
v_cmd endp

;; --- AL=0: save debugger screen, restore debuggee screen
;; --- AL=1: save debuggee screen, restore debugger screen
swapscreen proc
 ifndef VXCHGFLIP
	.errnz BOOTDBG or RING0, <v cmd with XMS swap not supported>
	mov SI, offset xmsmove
	cmp [SI].XMSM.dsthdl, 0
	jz done
	.286
	shl AX, 14	;; 0->0000, 1 -> 4000h
	mov word ptr [SI].XMSM.dstadr, AX

;; --- use offset & size of current video page as src/dst for
;; --- xms block move. Also toggle cursor pos debuggee/debugger.
	push 0040h	;; 0040h is used because it also works in protected-mode
	pop ES
	mov AX, ES:[4ch]
	mov word ptr [SI].XMSM.size_, AX
	mov AX, ES:[4eh]
	mov word ptr [SI].XMSM.srcadr+0, AX

;; --- get/set cursor pos manually for speed reasons.
	mov BL, ES:[62h]
	mov BH, 0
	shl BX, 1
	mov DX, ES:[BX+50h]	;; get cursor pos of current page
	xchg DX, [csrpos]
if 0
	mov ES:[BX+50h], DX
else
	mov BH, ES:[62h]
	mov AH, 2
	int 10h
endif

	push DS
	pop ES

	mov AH, 0bh		;; save video screen to xms
	call runxms
	call swapsrcdst

	xor byte ptr [SI].XMSM.srcadr+1, 40h

	mov AH, 0bh		;; restore video screen from xms
	call runxms
	call swapsrcdst
 else
    mov AH, 05h			;; just use BIOS to activate video page
  if RING0
	.386
	call CS:[int10vec]
	.8086
  else
	int 10h
  endif
 endif
done:
	ret

 ifndef VXCHGFLIP
	.8086
swapsrcdst:
	mov AX, [SI].XMSM.srchdl
	mov CX, word ptr [SI].XMSM.srcadr+0
	mov DX, word ptr [SI].XMSM.srcadr+2
	xchg AX, [SI].XMSM.dsthdl
	xchg CX, word ptr [SI].XMSM.dstadr+0
	xchg DX, word ptr [SI].XMSM.dstadr+2
	mov [SI].XMSM.srchdl, AX
	mov word ptr [SI].XMSM.srcadr+0, CX
	mov word ptr [SI].XMSM.srcadr+2, DX
	ret
runxms:
  if _PM
	call ispm_dbg
	jnz @F
  endif
	call [xmsdrv]
	ret
  if _PM
@@:
	.286
	xor CX, CX
	push CX				;; SS:SP
	push CX
	push word ptr [xmsdrv+2]	;; CS
	push word ptr [xmsdrv+0]	;; IP
	push CX				;; FS, GS
	push CX
	push [pspdbg]			;; DS
	push 0				;; ES
	pushf
	sub SP, 8*4
	sizeprf				;; mov EDI, ESP
	mov DI, SP
	mov ES:[DI].RMCS.rSI, SI
	mov ES:[DI].RMCS.rAX, AX
	mov BH, 0
	mov AX, 301h
	int 31h
	add SP, sizeof RMCS
	.8086
	ret
  endif
 endif
swapscreen endp
elseif VXCMD
v_cmd proc
	cmp AH, 'v'
	jnz @F
	or AL, TOLOWER
	@dprintf "v_cmd: AX=%X", AX
	cmp AL, 'c'
	jz vc_cmd
	cmp AL, 'l'
	jz vl_cmd
	cmp AL, 't'
	jz vt_cmd
@@:
	jmp cmd_error
v_cmd endp
endif

if ALTVID
;; --- switch to debugger/debuggee screen with option /2.
;; --- since DOS/BIOS is used for output, there's no guarantee that it will work.
;; --- this code assumes that page 0 is set.
setscreen proc
	ret	;; will be patched to "push DS" if "/2" cmdline switch and second adapter exists
	mov DX, [oldcrtp]
	mov BX, [oldcols]
	mov AX, [oldmr]
	mov CX, 0040h		;; 0040h is supposed to work in both rm/pm
	mov DS, CX
	mov CX, CS:[oldcsrpos]
	and byte ptr DS:[10h], not 30h
	cmp DL, 0b4h
	jnz @F
	or byte ptr DS:[10h], 30h
@@:
	xchg BX, DS:[4ah]
	xchg CX, DS:[50h]
	xchg DX, DS:[63h]
	xchg AL, DS:[49h]
	xchg AH, DS:[84h]
	pop DS
	mov [oldcrtp], DX
	mov [oldcsrpos], CX
	mov [oldcols], BX
	mov [oldmr], AX
	ret
setscreen endp
endif

if INT2324
;; --- this is low-level, called on entry into the debugger.
;; --- the debuggee's registers have already been saved here.
;; --- 1. get debuggee's interrupt vectors 23/24
;; --- 2. set debugger's interrupt vectors 23/24
;; --- DS, ES = DGROUP
;; --- Int 21h should not be used here!
getint2324 proc
	mov DI, offset run2324
 if _PM
	call ispm_dbg
	jnz getint2324pm
 endif

	xor SI, SI
	mov DS, SI
	mov SI, 23h*4
	push SI
	movsw		;; save interrupt vector 23h
	movsw
	movsw		;; save interrupt vector 24h
	movsw
	pop DI
	push ES
	pop DS
	xor SI, SI
	mov ES, SI
	mov SI, CCIV	;; move from debugger's PSP to IVT
	movsw
	movsw
	movsw
	movsw
	push DS
	pop ES
	ret
 if _PM
getint2324pm:
	mov BX, 0223h
	mov SI, offset dbg2324
@@:
	mov AX, 204h
	int 31h
	sizeprf		;; mov [DI+0], EDX
	mov [DI+0], DX
	mov [DI+4], CX

	sizeprf		;; xor EDX, EDX
	xor DX, DX
	lodsw
	mov DX, AX
	mov CX, CS
	mov AX, 205h
	int 31h

	add DI, 6
	inc BL
	dec BH
	jnz @B
	ret
	.8086
 endif
getint2324 endp
endif

;; The next three subroutines concern the handling of int 23 and 24.
;; These interrupt vectors are saved and restored when running the child process,
;; but are not active when Debug itself is running.
;; It is still useful for the programmer to be able to check where int 23 and 24 point,
;; so these values are copied into the interrupt table during parts of the c, d, e, m, and s commands,
;; so that they appear to be in effect.
;; The e command also copies these values back.
;; Between calls to dohack and unhack, there should be no calls to DOS,
;; so that there is no possibility of these vectors being used when the child process is not running.

;; --- for protected-mode, this whole procedure with prepare-do-undo is pretty useless -
;; --- hence all three procs are dummies while in pm.
;; --- OTOH, it might be useful, to adjust the DI cmd in protected-mode to return the debuggee's vectors for 23h/24h.

;; PREPHACK - Set up for interrupt vector substitution.
;;	save current value of Int 23/24 (debugger's) to sav2324
;;	Entry	ES = CS
prephack proc
if INT2324
	cmp [hakstat], 0
	jnz @F			;; if hack status error
	push DI
	mov DI, offset sav2324	;; debugger's Int2324
	call prehak1		;; copy IVT 23/24 to DI (real-mode only)
	pop DI
	ret
@@:
	push AX
	push DX
	mov DX, offset ph_msg	;; 'error in sequence of calls to hack'
	call int21ah9		;; print string
	pop DX
	pop AX
endif
	ret
prephack endp

if INT2324
CONST segment
ph_msg	db 'Error in sequence of calls to hack.', CR, LF, '$'
CONST ends

;; --- get current int 23/24, store them at ES:DI
;; --- DI is either sav2324 (debugger's) or run2324 (debuggee's)
prehak1 proc
 if _PM
	call ispm_dbg
	jnz _ret		;; nothing to do
 endif
	push DS
	push SI
	xor SI, SI
	mov DS, SI
	mov SI, 4*23h
	movsw
	movsw
	movsw
	movsw
	pop SI
	pop DS
_ret:
	ret
prehak1 endp
endif

;; DOHACK - set debuggee's int 23/24
;; UNHACK - set debugger's int 23/24
;;		It's OK to do either of these twice in a row.
;;		In particular, the 's' command may do unhack twice in a row.
;;	Entry	DS = debugger's segment
;;	Exit	ES = debugger's segment
dohack proc
if INT2324
	mov [hakstat], 1
 if _PM
	call ispm_dbg		;; v2.0: dohack is dummy in protected-mode
	jnz _ret
 endif
	push SI
	mov SI, offset run2324	;; debuggee's interrupt vectors
	jmp hak1

endif

unhack::
if INT2324
	mov [hakstat], 0
 if _PM
	call ispm_dbg
	jnz _ret		;; v2.0: unhack is dummy now
 endif
	push SI
	mov SI, offset sav2324	;; debugger's interrupt vectors
hak1:
	push DI
	push ES
	xor DI, DI
	mov ES, DI
	mov DI, 4*23h
	movsw
	movsw
	movsw
	movsw
	pop ES
	pop DI
	pop SI
_ret:
endif
	ret

dohack endp

;; --- InDos: return NZ if DOS cannot be used
InDos:
if (BOOTDBG or RING0)
	push AX
	or AL, -1
	pop AX
else
	push DS
	push SI
 if _PM
	call ispm_dbg
	mov SI, word ptr [pInDOS+0]
	mov DS, [InDosSel]
	jnz @F
	mov DS, word ptr CS:[pInDOS+2]
@@:
 else
	lds SI, [pInDOS]
 endif
	cmp byte ptr [SI], 0
	pop SI
	pop DS
endif
	ret

stdoutal:
	push CX
	push DX
	push AX
	mov CX, 1
if FLATSS
	mov [bChar], AL
	mov DX, offset bChar
else
	mov DX, SP
endif
	call stdout
	pop AX
	pop DX
	pop CX
	ret

fullbsout:
	mov AL, 8
	call stdoutal
	mov AL, 20h
	call stdoutal
	mov AL, 8
	jmp stdoutal

;; GETLINE - Print a prompt (address in DX, length in CX) and read a line of input.
;; GETLINE0 - Same as above, but use the output line (so far), plus two spaces and a colon, as a prompt.
;; GETLINE00 - Same as above, but use the output line (so far) as a prompt.
;;	Entry	CX	Length of prompt (getline only)
;;		DX	Address of prompt string (getline only)
;;		DI	Address + 1 of last character in prompt (getline0 and getline00 only)
;;	Exit	AL	First nonwhite character in input line
;;		SI	Address of the next character after that
;;	Uses	AH, BX, CX, DX, DI
getline0:
	mov AX, '  '		;; add two spaces and a colon
	stosw
	mov AL, ':'
	stosb
getline00:
	mov DX, offset line_out
	mov CX, DI
	sub CX, DX

getline proc
	mov [promptlen], CX	;; save length of prompt
	call stdout	;; write prompt (string DX, size CX)
if REDIRECT
	test [fStdin], AT_DEVICE
	jnz gl5		;; jmp if tty input

	mov [lastcmd], offset dmycmd

;; This part reads the input line from a file (in the case of 'debug < file').
;; It is necessary to do this by hand because DOS function 0ah does not handle EOF correctly otherwise.
;; This is especially important for debug because it traps Control-C.
	call fillbuf
	jc q_cmd
	mov [bufnext], SI
	mov CX, [bufend]
	mov DX, offset line_in + 2
	sub CX, DX
	call stdout	;; print out the received line
	jmp gl6		;; done
gl5:
endif

;; --- input a line if stdin is a device (tty)
	mov DX, offset line_in
	call InDos
	jnz rawinput
	mov AH, 0ah	;; buffered keyboard input
	call doscall
gl6:
	mov AL, 10
	call stdoutal
	mov SI, offset line_in + 2
	call skipwhite
	ret

rawinput:
	push DI
	push DS
	pop ES
	inc DX
	inc DX
	mov DI, DX
rawnext:
	mov AH, 00h
if RING0
	.386
	call CS:[int16vec]
	.8086
else
	int 16h
endif
	cmp AL, 0
	jz rawnext
	cmp AL, 0e0h
	jz rawnext
	cmp AL, 08h
	jz del_key
	cmp AL, 7fh
	jz del_key
	stosb
	call stdoutal
	cmp AL, 0dh
	jnz rawnext
	dec DI
	sub DI, DX
	mov AX, DI
	mov DI, DX
	mov byte ptr [DI-1], AL
	dec DX
	dec DX
	pop DI
	jmp gl6
del_key:
	cmp DI, DX
	jz rawnext
	dec DI
	call fullbsout
	jmp rawnext
getline endp

if REDIRECT
;; FILLBUF - Fill input buffer, read from a file.
;;	Called by getline & within 'e' cmd in interactive mode.
;;	Exit	SI	Next readable byte
;;		Carry flag is set if and only if there is an error (e.g., eof)
;;	Uses	None.
fillbuf proc
	push AX
	push BX
	push CX
	push DX
	mov SI, offset line_in+2
	push SI

;; --- read input bytewise until LF.
;; --- note that debug expects CR/LF pairs -
;; --- lines with just LF as EOL marker won't do.
@@:
	mov DX, SI
	cmp DX, offset line_in+LINE_IN_LEN	;; "line too long" is treated as EOF
	jz fb1
	mov CX, 1
	xor BX, BX
	mov AH, 3fh	;; read file
	call doscall
	jc fb1
	and AX, AX
	jz fb1		;; if eof
	mov AL, [SI]
	inc SI
	cmp AL, LF
	jnz @B
	dec SI		;; the LF itself should NOT be handled by the cmds.
	jmp fb2
fb1:
	stc
fb2:
	mov [bufend], SI
	pop SI
	pop DX
	pop CX
	pop BX
	pop AX
	ret
fillbuf endp

endif

;; PARSECM - Parse arguments for C and M commands.
;;	Entry	AL		First nonwhite character of parameters
;;		SI		Address of the character after that
;;	Exit	DS:(E)SI	Address from first parameter
;;		ES:(E)DI	Address from second parameter
;;		(E)CX		Length of address range minus one
;;		m cmd in real-mode expects dst segm:ofs in BX:DX
parsecm proc
	call prephack
	mov BX, [regs.rDS]	;; DS = default for source range segment
	sizeprfX		;; xor ECX, ECX
	xor CX, CX

	call getrange		;; get address range into BX:(E)DX BX:(E)CX
	push BX			;; save segment first address (src for m cmd)
if ?PM
	cmp [bAddr32], 0
	jz @F
	.386
	sub ECX, EDX
	push EDX		;; save offset first address
	push ECX
	jmp pc_01
	.8086
@@:
endif
	sub CX, DX		;; number of bytes minus one
	push DX
	push CX
pc_01:
	call skipcomm0

;; --- get the second (destination) address
	mov BX, [regs.rDS]	;; DS = default for "destination"
if ?PM
	cmp [bAddr32], 0
	jz pc_1
	.386
	call getaddr		;; get address into BX:(E)DX
	mov [bAddr32], 1	;; restore bAddr32
	pop ECX
	mov EDI, ECX
	add EDI, EDX
	jc errorj7
	call chkeol
	mov EDI, EDX
	mov ES, BX
	pop ESI
	pop DS
	ret
	.8086
pc_1:
endif
	call getaddr	;; get destination address into BX:(E)DX
	pop CX
	mov DI, CX
	add DI, DX
	jc errorj7	;; if it wrapped around
	call chkeol	;; expect end of line
	mov DI, DX
	mov ES, BX
	pop SI
	pop DS
	ret
parsecm endp

errorj7:
	jmp cmd_error

if LCMD or WCMD
;; PARSELW - Parse command line for L and W commands.
;;	Entry	AL	First nonwhite character of parameters
;;		SI	Address of the character after that
;;	Exit	If there is at most one argument (program load/write),
;;		then the zero flag is set, and registers are set as follows:
;;		BX:(E)DX	Transfer address
;;	If there are more arguments (absolute disk read/write), then the zero flag is clear, and registers are set as follows:
;;	[usepacket] == 0:
;;		AL	Drive number
;;		CX	Number of sectors to read
;;		DX	Beginning logical sector number
;;		DS:BX	Transfer address
;;	[usepacket] != 0:
;;		AL	Drive number
;;		BX	Offset of packet
;;		CX	0ffffh
parselw proc
	mov BX, [regs.rCS]	;; default segment
	mov DX, 100h		;; default offset
	cmp AL, CR
	je plw2			;; if no arguments
;; --- v2.0: added IsWriteableBX since getaddr will no longer translate BX
;; --- to a writeable selector.
	call getaddr		;; get buffer address into BX:(E)DX
if ?PM
	call IsWriteableBX
endif
	call skipcomm0
	cmp AL, CR
	je plw2			;; if only one argument
	push BX			;; save segment
	push DX			;; save offset
	mov BX, 80h		;; max number of sectors to read
	neg DX
	jz @F			;; if address is zero
	mov CL, 9
	shr DX, CL		;; max number of sectors which can be read
	mov DI, DX
@@:
	call getbyte		;; get drive number (DL)
	call skipcomm0
	push DX
;;	add DL, 'A'
	mov [driveno], DL
	call getdword		;; get relative sector number
	call skipcomm0
	push BX			;; save sector number high
	push DX			;; save sector number low
	push SI			;; in case we find an error
	call getword		;; get sector count
	dec DX
	cmp DX, DI
	jae errorj7		;; if too many sectors
	inc DX
	mov CX, DX
	call chkeol		;; expect end of line
	cmp [usepacket], 0
	jnz plw3		;; if new-style packet called for
	pop SI			;; in case of error
	pop DX			;; get LoWord starting logical sector number
	pop BX			;; get HiWord
	or BX, BX		;; just a 16bit sector number possible
	jnz errorj7		;; if too big
	pop AX			;; drive number
	pop BX			;; transfer buffer ofs
	pop DS			;; transfer buffer seg
	or CX, CX		;; set nonzero flag
plw2:
	ret

;; --- new style packet, [usepacket] != 0

plw3:
	pop BX			;; discard SI
	mov BX, offset packet
	pop word ptr [BX].PACKET.secno+0
	pop word ptr [BX].PACKET.secno+2
	mov [BX].PACKET.numsecs, CX
	pop AX			;; drive number
	pop word ptr [BX].PACKET.dstofs
	pop DX
	xor CX, CX
if ?PM
	call ispm_dbg
	jz @F
 if _PM
	cmp [dpmi32], 0
	jz @F
 endif
	.386
	mov [BX].PACKET32.dstseg, DX
	movzx EBX, BX
	shr EDX, 16		;; get HiWord(offset)
	cmp [bAddr32], 1
	jz @F
	xor DX, DX
	.8086
@@:
endif
	mov [BX].PACKET.dstseg, DX	;; PACKET.dstseg or HiWord(PACKET32.dstofs)
	dec CX				;; set nonzero flag and make CX = -1
	ret
parselw endp
endif

;; PARSE_PT - Parse 'p' or 't' command.
;;	Entry	AL	First character of command
;;		SI	Address of next character
;;	Exit	CX	Number of times to repeat
;;	Uses	AH, BX, CX, DX.
parse_pt proc
	call parseql		;; get optional <=addr> argument
	call skipcomm0		;; skip any white space
	mov CX, 1		;; default count
	cmp AL, CR
	je @F			;; if no count given
	call getword
	call chkeol		;; expect end of line here
	mov CX, DX
	jcxz errorj10		;; must be at least 1
@@:
;;	call seteq		;; make the = operand take effect
	ret
parse_pt endp

;; PARSEQL - Parse '=' operand for 'g', 'p' and 't' commands.
;;	Entry	AL	First character of command
;;		SI	Address of next character
;;	Exit	AL	First character beyond range
;;		SI	Address of the character after that
;;		eqflag	Nonzero if an '=' operand was present
;;		eqladdr	Address, if one was given
;;	Uses AH, BX, CX, (E)DX.
parseql proc
	mov [eqflag], 0		;; mark '=' as absent
	mov BX, [regs.rCS]	;; default segment
	cmp AL, '='
	jne peq1		;; if no '=' operand
	call skipwhite
if _PM
	sizeprf
	xor DX, DX
endif
	call getaddr		;; get address into BX:(E)DX
	sizeprfX		;; mov [eqladdr+0], EDX
	mov [eqladdr+0], DX
	inc [eqflag]
peq1:
	mov [eqladdr+4], BX
	ret
parseql endp

;; SETEQ - Copy the = arguments to their place, if appropriate.
;; This is not done immediately, because the g/p/t cmds may have syntax errors.
;; Uses AX.
seteq proc
	cmp [eqflag], 0		;; '=' argument given?
	jz @F
	sizeprfX		;; mov EAX, [eqladdr+0]
	mov AX, [eqladdr+0]
	sizeprfX		;; mov [regs.rIP+0], EAX
	mov [regs.rIP+0], AX
	mov AX, [eqladdr+4]
	mov [regs.rCS], AX
	mov [eqflag], 0		;; clear the flag
@@:
	ret
seteq endp

;; --- get a valid offset for segment in BX
;; --- in:	BX=segment/selector
;; --- out:	offset in (E)DX
getofsforbx proc
if ?PM
	call getseglimit
	jz gofbx_2
	mov [bAddr32], 1
	push BX
	call getdword
	push BX
	push DX
	.386
	pop EDX
	pop BX
	ret
	.8086
gofbx_2:
endif
	sizeprfX		;; v2.0: xor EDX, EDX
	xor DX, DX
	call getword
;;	@dprintf "getofsforbx: EDX=%lX", EDX
	ret
getofsforbx endp

errorj10:
	jmp cmd_error

;; --- a range is entered with the L/ength argument
;; --- get a valid length for segment in BX
;; --- L=0 means 64 kB (at least in 16bit mode)
;; --- return with NC if value ok.
getlenforbx proc
if ?PM
	call getseglimit
	jz glfbx_1
	push DX
	push BX
	call getdword
	push BX
	push DX
	.386
	pop ECX
	pop BX
	pop DX
	stc
	jecxz glfbx_2
	dec ECX
	add ECX, EDX
	ret
	.8086
glfbx_1:
endif
	push DX
	call getword
	mov CX, DX
	pop DX
;;	stc
;;	jcxz glfbx_2	;; 0 means 64k
	dec CX
	add CX, DX		;; C if it wraps around
glfbx_2:
	ret
getlenforbx endp

;; GETRANGE - Get address range from input line.
;; A range consists of either a start and end address or a start address an 'L' and a length.
;;	Entry	AL	First character of range
;;		SI	Address of next character
;;		BX	Default segment to use
;;		CX	Default length to use (or 0 if not allowed)
;;	Exit	AL	First character beyond range
;;		SI	Address of the character after that
;;		BX:(E)DX	First address in range
;;		BX:(E)CX	Last address in range
;;	Uses	AH
getrange proc			;; used by c, d, m, s, u cmds
	push CX
	call getaddr		;; get address into BX:(E)DX (sets bAddr32)
	push SI
	call skipcomm0
	cmp AL, ' '
	ja gr2
	pop SI			;; restore SI and CX
	pop CX
	jcxz errorj10		;; if a range is mandatory
if ?PM
	cmp [bAddr32], 0	;; can be 1 only on a 80386+
	jz @F
	.386
	dec ECX
	add ECX, EDX
	jnc gr1			;; if no wraparound
	or ECX, -1		;; go to end of segment
	jmp gr1
@@:
endif
	dec CX
	add CX, DX
	jnc gr1			;; if no wraparound
	mov CX, 0ffffh		;; go to end of segment
gr1:
	dec SI			;; restore AL
	lodsb
	ret

gr2:
	or AL, TOLOWER
	cmp AL, 'l'
	je gr3			;; if a range is given
;;	call skipwh0		;; get next nonblank
if ?PM
	cmp [machine], 3
	jb gr2_1
	.386
	push EDX
	call getofsforbx
	mov ECX, EDX
	pop EDX
	cmp EDX, ECX
	ja errorj2
	jmp gr4
	.8086
gr2_1:
endif
	push DX
	call getword
	mov CX, DX
	pop DX
	cmp DX, CX
	ja errorj2		;; if empty range
	jmp gr4

gr3:
	call skipcomma		;; discard the 'l'
	call getlenforbx
	jc errorj2
gr4:
	add SP, 4		;; discard saved CX, SI
	ret
getrange endp

errorj2:
	jmp cmd_error

;; GETADDR - Get address from input line.
;;	Entry	AL	First character of address
;;		SI	Address of next character
;;		BX	Default segment to use
;;	Exit	AL	First character beyond address
;;		SI	Address of the character after that
;;		BX:(E)DX	Address found
;;	Uses	AH, CX
getaddr proc
if ?PM
	mov [bAddr32], 0
 if _PM
	cmp AL, '$'			;; a real-mode segment?
	jnz @F
	lodsb
	call ispm_dbg
	jz @F
	call getword
	cmp AL, ':'
	jnz errorj2
	mov BX, DX
	mov AX, 2
	int 31h
	mov BX, AX
	mov DX, AX
	jc errorj2
	jmp ga3
@@:
 elseif RING0
	cmp AL, '%'			;; a linear address?
	jnz @F
	mov BX, CS:[wFlat]
	jmp ga3
@@:
;; --- hack for a/u cmds: allow to enter a real-mode address.
;; --- since the debugger cannot handle v86-mode exceptions yet,
;; --- this hack allows to at least (dis)assemble real-mode code parts.
	cmp AL, '$'
	jnz normseg
	cmp [lastcmd], offset u_cmd	;; u cmd?
	jz @F
	cmp [errret], offset cmdloop	;; a cmd?
	jz normseg
@@:
	lodsb
	call getword
	cmp AL, ':'
	jnz errorj2
	call setscratchsel	;; set BX to scratchsel
	jmp ga3
normseg:
 endif
endif
	call getofsforbx
	push SI
	call skipwh0
	cmp AL, ':'
	je ga2		;; if this is a segment descriptor
	pop SI
	dec SI
	lodsb
	ret

ga2:
	pop AX		;; throw away saved SI
	mov BX, DX	;; mov segment into BX
ga3:
	call skipwhite	;; skip to next word
if ?PM
	mov [bAddr32], 0	;; v2.0: init bAddr32, will be set if limit > 64k
endif
	call getofsforbx
if ?PM
	@dprintf "getaddr: BX:EDX=%X:%lX, bAddr32=%X", BX, EDX, word ptr [bAddr32]
endif
	ret
getaddr endp

;; GETSTR - Get string of bytes.
;; Put the answer in line_out.
;;	Entry	AL		first character
;;		SI		address of next character
;;	Exit	[line_out]	first byte of string
;;		DI		address of last+1 byte of string
;;	Uses	AX, CL, DL, SI
getstr proc
	mov DI, offset line_out
	cmp AL, CR
	je errorj2	;; we don't allow empty byte strings
gs1:
	cmp AL, "'"
	je gs2		;; if string
	cmp AL, '"'
	je gs2		;; ditto
	call getbyte	;; byte in DL
	mov [DI], DL	;; store the byte
	inc DI
	jmp gs6

gs2:
	mov AH, AL	;; save quote character
gs3:
	lodsb
	cmp AL, AH
	je gs5		;; if possible end of string
	cmp AL, CR
	je errorj2	;; if end of line
gs4:
	stosb		;; save character and continue
	jmp gs3

gs5:
	lodsb
	cmp AL, AH
	je gs4		;; if doubled quote character
gs6:
	call skipcomm0	;; go back for more
	cmp AL, CR
	jne gs1		;; if not done yet
	ret
getstr endp

;; --- in:	AL=first char
;; ---		SI->2. char
;; --- out:	value in BX:DX
issymbol proc
	push AX
	push DI
	push CX
	mov DI, offset regnames
	mov CX, NUMREGNAMES
	mov AH, [SI]		;; get second char of name
	and AX, TOUPPER_W
	cmp byte ptr [SI+1], 'A'
	jnc maybenotasymbol
	repnz scasw
	jnz notasymbol
	xor BX, BX
	mov DI, [DI+NUMREGNAMES*2 - 2]
getsymlow:
	mov DX, [DI]
	inc SI			;; skip over second char
	clc
	pop CX
	pop DI
	pop AX
	ret
maybenotasymbol:
	cmp AL, 'E'		;; 386 standard register names start with E
	jnz notasymbol
	mov AL, [SI+1]
	xchg AL, AH
	and AX, TOUPPER_W
	cmp AX, "PI"
	jnz @F
	mov DI, offset regs.rIP
	jmp iseip
@@:
	mov CX, 8		;; scan for the 8 standard register names only
	repnz scasw
	jnz notasymbol
	mov DI, [DI+NUMREGNAMES*2 - 2]
iseip:
	mov BX, [DI+2]		;; get HiWord of dword register
	inc SI
	jmp getsymlow
notasymbol:
	pop CX
	pop DI
	pop AX
	stc
	ret
issymbol endp

;; GETDWORD - Get (hex) dword from input line.
;;	Entry	AL	first character
;;		SI	address of next character
;;	Exit	BX:DX	dword
;;		AL	first character not in the word
;;		SI	address of the next character after that
;;	Uses	AH, CL
getdword proc
	call issymbol
	jc @F
	lodsb
	ret
@@:
	call getnyb
	jc errorj6		;; if error
	cbw
	xchg AX, DX
	xor BX, BX		;; clear high order word
nextchar:
	lodsb
	call getnyb
	jc done
	test BH, 0f0h
	jnz errorj6		;; if too big
	mov CX, 4
@@:
	shl DX, 1		;; double shift left
	rcl BX, 1
	loop @B
	or DL, AL
	jmp nextchar
done:
	ret
getdword endp

errorj6:
	jmp cmd_error

;; GETWORD - Get (hex) word from input line.
;;	Entry	AL	first character
;;		SI	address of next character
;;	Exit	DX	word
;;		AL	first character not in the word
;;		SI	address of the next character after that
;;	Uses	AH, CL
getword proc
	push BX
	call getdword
	and BX, BX		;; hiword clear?
	pop BX
	jnz errorj6		;; if error
	ret
getword endp

;; GETBYTE - Get (hex) byte from input line into DL.
;;	Entry	AL	first character
;;		SI	address of next character
;;	Exit	DL	byte
;;		AL	first character not in the word
;;		SI	address of the next character after that
;;	Uses	AH, CL
getbyte:
	call getword
	and DH, DH
	jnz errorj6	;; if error
	ret

;; --- GETNYB - Convert the hex character in AL into a nybble.
;; --- Return carry set in case of error.
getnyb:
	push AX
	sub AL, '0'
	cmp AL, 9
	jbe gn1		;; if normal digit
	pop AX
	push AX
	or AL, TOLOWER
	sub AL, 'a'
	cmp AL, 'f'-'a'
	ja gn2		;; if not a-f or A-F
	add AL, 10
gn1:
	inc SP		;; normal return (first pop old AX)
	inc SP
	clc
	ret
gn2:
	pop AX		;; error return
	stc
	ret

;; --- CHKEOL1 - Check for end of line.
chkeol:
	call skipwh0
	cmp AL, CR
	jne errorj8	;; if not found
	ret

errorj8:
	jmp cmd_error

;; SKIPCOMMA - Skip white space, then an optional comma, and more white space.
;; SKIPCOMM0 - Same as above, but we already have the character in AL.
skipcomma:
	lodsb
skipcomm0:
	call skipwh0
	cmp AL, ','
	jne sc2		;; if no comma
	push SI
	call skipwhite
	cmp AL, CR
	jne sc1		;; if not end of line
	pop SI
	mov AL, ','
	ret
sc1:
	add SP, 2	;; pop SI into nowhere
sc2:
	ret

;; --- SKIPALPHA - Skip alphabetic character, and then white space.
skipalpha:
	lodsb
	and AL, TOUPPER
	sub AL, 'A'
	cmp AL, 'Z'-'A'
	jbe skipalpha
	dec SI
;;	jmp skipwhite	;; (control falls through)

;; --- SKIPWHITE - Skip spaces and tabs.
;; --- SKIPWH0 - Same as above, but we already have the character in AL.
skipwhite:
	lodsb
skipwh0:
	cmp AL, ' '
	je skipwhite
	cmp AL, TAB
	je skipwhite
	ret

;; --- IFSEP Compare AL with separators ' ', '\t', ',', ';', '='.
ifsep:
	cmp AL, ' '
	je @F
	cmp AL, TAB
	je @F
	cmp AL, ','
	je @F
	cmp AL, ';'
	je @F
	cmp AL, '='
@@:
	ret

;; --- disassembler code

	include <DisAsm.inc>

;; SHOWMACH - Return strings
;;		"[needs _86]" or "[needs _87]",
;;		"[needs math coprocessor]" or "[obsolete]"
;;	Entry	DI -> table of obsolete instructions (5 items)
;;		CX -> instruction
;;	Exit	SI Address of string
;;		CX Length of string, or 0 if not needed
;;	Uses	AL, DI
showmach proc
	mov SI, offset needsmsg		;; candidate message
	test [ai.dmflags], DM_COPR
	jz is_cpu			;; if not a coprocessor instruction
	mov byte ptr [SI+9], '7'	;; change message text ('x87')
	mov AL, [mach_87]
	cmp [has_87], 0
	jnz sm2				;; if it has a coprocessor
	mov AL, [machine]
	cmp AL, [ai.dismach]
	jb sm3				;; if we display the message
	mov SI, offset needsmath	;; print this message instead
	mov CX, sizeof needsmath
	ret

is_cpu:
	mov byte ptr [SI+9], '6'	;; reset message text ('x86')
	mov AL, [machine]
sm2:
	cmp AL, [ai.dismach]
	jae sm4				;; if no message (so far)
sm3:
	mov AL, [ai.dismach]
	add AL, '0'
	mov [SI+7], AL
	mov CX, sizeof needsmsg	;; length of the message
	ret

;; --- Check for obsolete instruction.
sm4:
	mov SI, offset obsolete	;; candidate message
	mov AX, CX		;; get info on this instruction
	mov CX, 5
	repne scasw
	jne @F			;; if no matches
	mov DI, offset OldCPU + 5 - 1
	sub DI, CX
	xor CX, CX		;; clear CX: no message
	mov AL, [mach_87]
	cmp AL, [DI]
	jle @F			;; if this machine is OK
	mov CX, sizeof obsolete
@@:
	ret
showmach endp

;; --- DUMPREGS - Dump registers.
;; --- 16bit: 8 std regs, NL, skip 2, 4 seg regs, IP, flags
;; --- 32bit: 6 std regs, NL, 2 std regs+IP+FL, flags, NL, 6 seg regs
dumpregs proc
	mov SI, offset regnames
	mov DI, offset line_out
	mov CX, 8			;; print all 8 std regs (16-bit)
	test [rmode], RM_386REGS
	jz @F
	mov CL, 6			;; room for 6 std regs (32-bit) only
@@:
	call dmpr1			;; print first row
	call trimputs
	mov DI, offset line_out
	test [rmode], RM_386REGS
	jnz @F
	push SI
	add SI, 2*2			;; skip "IP"+"FL"
	mov CL, 4			;; print 4 segment regs
	call dmpr1w
	pop SI
	inc CX			;; CX=1
	call dmpr1		;; print (E)IP
	call dmpflags		;; print flags in 8086 mode
	jmp no386_31
@@:
	mov CL, 4		;; print rest of 32-bit std regs + EIP + EFL
	call dmpr1d
	push SI
	call dmpflags		;; print flags in 386 mode
	call trimputs
	pop SI
	mov DI, offset line_out
	mov CL, 6		;; print DS, ES, SS, CS, FS, GS
	call dmpr1w
if RING0
 if DISPPL0STK
	.386
	lar AX, [regs.rCS]
	and AH, 60h
	jz @F
	mov SI, offset pl0esp
	mov CL, sizeof pl0esp
	rep movsb
	mov AX, [regs.r0SS]
	call hexword
	mov AL, ':'
	stosb
	mov EAX, [regs.r0Esp]
	call hexdword
	mov AL, ']'
	stosb
@@:
 endif
endif
no386_31:
	call trimputs

;; --- display 1 disassembled line at CS:[E]IP
	@dprintf "dumpregs"
	mov SI, offset regs.rIP
	mov DI, offset u_addr
	movsw
	movsw
	mov AX, [regs.rCS]
	stosw
	mov AL, DIS_F_REPT or DIS_F_SHOW
	call disasm

;; --- 'r' resets default setting for 'u' to CS:[E]IP
	sizeprf
	mov AX, [regs.rIP]
	sizeprf
	mov [u_addr], AX
	ret

if RING0
 if DISPPL0STK
pl0esp db "[PL0 SS:ESP="
 endif
endif

;; --- Function to print multiple word/dword register entries.
;; --- SI->register names (2 bytes)
;; --- CX=count
dmpr1:
	test [rmode], RM_386REGS
	jnz dmpr1d

;; --- Function to print multiple word register entries.
;; --- SI->register names (2 bytes)
;; --- CX=count
dmpr1w:
	movsw
	mov AL, '='
	stosb
	mov BX, [SI+NUMREGNAMES*2-2]
	mov AX, [BX]
	call hexword
	mov AL, ' '
	stosb
	loop dmpr1w
	ret

;; --- Function to print multiple dword register entries.
;; --- SI->register names (2 bytes)
;; --- CX=count
dmpr1d:
	mov AL, 'E'
	stosb
	movsw
	mov AL, '='
	stosb
	mov BX, [SI+NUMREGNAMES*2-2]
	.386
	mov EAX, [BX]
	.8086
	call hexdword
	mov AL, ' '
	stosb
	loop dmpr1d
	ret
dumpregs endp

if USEFP2STR
 if RING0
	.386
 endif
	include <FpToStr.inc>
endif

;; --- the layout for fsave/frstor depends on mode and 16/32bit
if 0
FPENV16 struc
cw	dw ?
sw	dw ?
tw	dw ?
fip	dw ?	;; IP offset
union
opc	dw ?	;; real-mode: opcode[0-10], IP 16-19 in high bits
fcs	dw ?	;; protected-mode: IP selector
ends
fop	dw ?	;; operand ptr offset
union
foph	dw ?	;; real-mode: operand ptr 16-19 in high bits
fos	dw ?	;; protected-mode: operand ptr selector
ends
FPENV16 ends

FPENV32 struc
cw	dw ?
	dw ?
sw	dw ?
	dw ?
tw	dw ?
	dw ?
fip	dd ?	;; IP offset (real-mode: bits 0-15 only)
union
struct
fopcr	dd ?	;; real-mode: opcode (0-10), IP (12-27)
ends
struct
fcs	dw ?	;; protected-mode: IP selector
fopcp	dw ?	;; protected-mode: opcode(bits 0-10)
ends
ends
foo	dd ?	;; operand ptr offset (real-mode: bits 0-15 only)
union
struct
fooh	dd ?	;; real-mode: operand ptr (12-27)
ends
struct
fos	dw ?	;; protected-mode: operand ptr selector
	dw ?	;; protected-mode: not used
ends
ends
FPENV32 ends
endif

CONST segment
fregnames label byte
	db "CW", "SW", "TW"
	db "OPC=", "IP=", "DP="
dEmpty	db "empty"
dNaN	db "NaN"
CONST ends

;; --- dumpregsFPU - Dump Floating Point Registers
;; --- modifies SI, DI, [E]AX, BX, CX, [E]DX
dumpregsFPU proc
	mov DI, offset line_out
	mov SI, offset fregnames
	mov BX, offset line_in + 2
	sizeprf
	fnsave [BX]

;; --- display CW. SW and TW
	mov CX, 3
nextfpr:
	movsw
	mov AL, '='
	stosb
	xchg SI, BX
	sizeprf		;; lodsd
	lodsw
	xchg SI, BX
	push AX
	call hexword
	mov AL, ' '
	stosb
	loop nextfpr

;; --- display OPC
;; --- in 16bit format protected-mode, there's no OPC
;; --- for 32bit, there's one, but the location is different from real-mode
	push BX
if _PM
	call ispm_dbg
	jz @F
	add BX, 2	;; location of OPC in protected-mode differs from real-mode!
	cmp [machine], 3
	jnb @F
	add SI, 4	;; no OPC for FPENV16 in protected-mode
	jmp noopc
@@:
endif
	movsw
	movsw
	xchg SI, BX
	sizeprf		;; lodsd
	lodsw		;; skip word/dword
	lodsw
	xchg SI, BX
	and AX, 07ffh	;; bits 0-10 only
	call hexword
	mov AL, ' '
	stosb
noopc:
	pop BX

;; --- display IP and DP
	mov CL, 2	;; CH is 0 already
nextfp:
	push CX
	movsw
	movsb
	xchg SI, BX
	sizeprf		;; lodsd
	lodsw
	sizeprf		;; mov EDX, EAX
	mov DX, AX
	sizeprf		;; lodsd
	lodsw
	xchg SI, BX
if _PM
	call ispm_dbg
	jz @F
	call hexword
	mov AL, ':'
	stosb
	jmp fppm
@@:
endif
	mov CL, 12
	sizeprf		;; shr EAX, CL
	shr AX, CL
	cmp [machine], 3
	jb @F
	call hexword
	jmp fppm
@@:
	call hexnyb
fppm:
	sizeprfX	;; mov EAX, EDX
	mov AX, DX
if _PM
	call ispm_dbg
	jz @F
	cmp [machine], 3
	jb @F
	call hexdword
	jmp fppm32
@@:
endif
	call hexword
fppm32:
	mov AL, ' '
	stosb
	pop CX
	loop nextfp

	xchg SI, BX
	call trimputs

;; --- display ST0 - ST7
	pop BP	;; get TW
	pop AX	;; get SW
	pop DX	;; get CW (not used)

	mov CL, 10
	shr AX, CL	;; mov TOP to bits 1-3
	and AL, 00001110b
	mov CL, AL
	ror BP, CL

	mov CL, '0'
nextst:		;; <- next float to display
	mov DI, offset line_out
	push SI
	push CX
	mov AX, "TS"
	stosw
	mov AL, CL
	mov AH, '='
	stosw

	mov AX, BP
	ror BP, 1	;; remain 8086 compatible here!
	ror BP, 1
	and AL, 3	;; 00=valid, 01=zero, 02=NaN, 03=Empty
	jz isvalid
	mov SI, offset dEmpty
	mov CL, sizeof dEmpty
	cmp AL, 3
	jz @F
	mov SI, offset dNaN
	mov CL, sizeof dNaN
	cmp AL, 2
	jz @F
	mov AL, '0'
	stosb
	mov CL, 0
@@:
	rep movsb
	jmp regoutdone
isvalid:
if USEFP2STR
	call FloatToStr
else
	mov CL, 5
@@:
	lodsw
	push AX
	loop @B
	pop AX
	call hexword
	mov AL, '.'
	stosb
	mov CL, 4
@@:
	pop AX
	call hexword
	loop @B
endif
regoutdone:
	mov AL, ' '
@@:
	stosb
	cmp DI, offset line_out+26
	jb @B
	pop AX
	push AX
	test AL, 1
	jz @F
	mov AX, 0a0dh
	stosw
@@:
	call puts
	pop CX
	pop SI
	add SI, 10	;; sizeof tbyte
	inc CL
	cmp CL, '8'
	jnz nextst
	.286		;; avoid wait prefix
	sizeprf
	frstor [line_in + 2]
	.8086
	ret
dumpregsFPU endp

;; --- DMPFLAGS - Dump flags output.
dmpflags proc
	mov SI, offset flgbits
	mov CX, 8	;; lengthof flgbits
nextitem:
	lodsw
	test AX, [regs.rFL]
	mov AX, [SI+16-2]
	jz @F		;; if not asserted
	mov AX, [SI+32-2]
@@:
	stosw
	mov AL, ' '
	stosb
	loop nextitem
	ret
dmpflags endp

if MMXSUPP
	.386
dumpregsMMX proc
	fnsaved [line_in + 2]
	mov SI, offset line_in + 7*4 + 2
	mov CL, '0'
;;	mov DI, offset line_out
nextitem:
	mov AX, "MM"
	stosw
	mov AL, CL
	mov AH, '='
	stosw
	push CX
	mov DL, 8
nextbyte:
	lodsb
	call hexbyte
	mov AL, ' '
	test DL, 1
	jnz @F
	mov AL, '-'
@@:
	stosb
	dec DL
	jnz nextbyte
	dec DI
	mov AX, '  '
	stosw
	add SI, 2
	pop CX
	test CL, 1
	jz @F
	push CX
	call putsline
	pop CX
	mov DI, offset line_out
@@:
	inc CL
	cmp CL, '8'
	jnz nextitem
	fldenvd [line_in + 2]
	ret
dumpregsMMX endp
	.8086
endif

;; --- copystring - copy non-empty null-terminated string.
;; --- SI->string
;; --- DI->buffer
copystring proc
	lodsb
@@:
	stosb
	lodsb
	cmp AL, 0
	jne @B
	ret
copystring endp

;; HEXDWORD - Print hex dword (in EAX).
;; clears HiWord(EAX)

;; HEXWORD - Print hex word (in AX).
;; HEXBYTE - Print hex byte (in AL).
;; HEXNYB - Print hex digit.
;; Uses AL, DI.
hexdword proc
	push AX
	.386
	shr EAX, 16
	.8086
	call hexword
	pop AX
hexdword endp	;; fall through!

hexword proc
	push AX
	mov AL, AH
	call hexbyte
	pop AX
hexword endp	;; fall through!

hexbyte:
	push AX
if RING0
	.386
	shr AL, 4
else
	push CX
	mov CL, 4
	shr AL, CL
endif
	call hexnyb
ife RING0
	pop CX
endif
	pop AX

hexnyb:
	and AL, 0fh
	add AL, 90h		;; these four instructions change to ascii hex
	daa
	adc AL, 40h
	daa
	stosb
	ret

;; TRIMPUTS - Trim excess blanks from string and print (with CR/LF).
;; PUTSLINE - Add CR/LF to string and print it.
;; PUTS - Print string through DI.
trimputs:
	dec DI
	cmp byte ptr [DI], ' '
	je trimputs
	inc DI

putsline:
	mov AX, LF*256 + CR
	stosw

puts:
	mov CX, DI
	mov DX, offset line_out
	sub CX, DX

;; --- fall thru'
;; --- stdout: write DS:DX, size CX to STDOUT (1)
;; --- modifies AX
stdout proc
	call InDos
	push BX
	jnz @F
	mov BX, 1		;; standard output
	mov AH, 40h		;; write to file
	call doscall
	pop BX
	ret
@@:				;; use BIOS for output
	jcxz nooutput
	push SI
	mov SI, DX
nextchar:
	lodsb
	mov BH, [vpage]		;; v2.0: use the current video page
	cmp AL, TAB		;; v2.0: handle tabs
	jz istab
	mov AH, 0eh
if RING0
	.386
	call [int10vec]
	.8086
else
	int 10h
endif
donetab:
	loop nextchar
	pop SI
nooutput:
	pop BX
	ret

;; --- interpret TAB in BIOS output
istab:
	push CX
	push DX
	mov AH, 3
if RING0
	.386
	call [int10vec]
	.8086
else
	int 10h
endif
	mov CL, DL
	and CX, 7	;; 0 1 2 3 4 5 6 7
	sub CL, 8	;; -8 -7 -6 -5 -4 -3 -2 -1
	neg CL		;; 8 7 6 5 4 3 2 1
@@:
	mov AX, 0e20h
if RING0
	.386
	call [int10vec]
	.8086
else
	int 10h
endif
	loop @B
	pop DX
	pop CX
	jmp donetab
stdout endp

ifdef _DEBUG
	pushcontext cpu
	.386
	include <DPrintF.inc>
	popcontext cpu
endif

if LCMDFILE
createdummytask proc
	mov DI, offset regs
	mov CX, sizeof regs/2
	xor AX, AX
	rep stosw

	mov AH, 48h		;; get largest free block
	mov BX, -1
	int 21h
	cmp BX, 11h		;; must be at least 110h bytes!!!
	jc ct_done
	mov AH, 48h		;; allocate it
	int 21h
	jc ct_done		;; shouldn't happen

	mov byte ptr [regs.rIP+1], 1	;; IP=100h

	call setespefl	;; set regs.rSP/rFL

	push BX
	mov DI, offset regs.rDS	;; init regs.rDS, regs.rES
	stosw
	stosw
	mov DI, offset regs.rSS	;; init regs.rSS, regs.rCS
	stosw
	stosw
	call setup_adu		;; setup default for a/d/u cmds
	mov BX, [regs.rCS]	;; BX:DX = where to load program
	mov ES, BX
	pop AX			;; get size of memory block
	mov DX, AX
	add DX, BX
	mov ES:[ALASAP], DX
	cmp AX, 1000h
	jbe @F			;; if memory left <= 64K
	xor AX, AX		;; AX = 1000h (same thing, after shifting)
@@:
	mov CL, 4
	shl AX, CL
	dec AX
	dec AX
	mov [regs.rSP], AX
	xchg AX, DI		;; ES:DI = child stack pointer
	xor AX, AX
	stosw			;; push 0 on client's stack

;; --- Create a PSP
	mov AH, 55h		;; create child PSP
	mov DX, ES
	mov SI, ES:[ALASAP]
	clc				;; works around OS/2 bug
	int 21h
	mov word ptr ES:[TPIV+0], offset intr22
	mov ES:[TPIV+2], CS
	cmp [bInit], 0
	jnz @F
	inc [bInit]
	mov byte ptr ES:[100h], 0c3h	;; place opcode for 'ret' at CS:IP
@@:
	mov [pspdbe], ES

	mov AX, ES
	dec AX
	mov ES, AX
	inc AX
	mov ES:[0001], AX
	mov byte ptr ES:[0008], 0
	push DS			;; restore ES
	pop ES

	call getint2324		;; v2.0 init [run2324]

	call setpspdbg		;; set debugger's PSP
ct_done:
	ret
createdummytask endp
endif

if _PM
;; --- hook int 2fh if a DPMI host is found for Win3x/9x and DosEmu host
;; --- int 2fh, AX=1687h is not hooked, however because it doesn't work.
;; --- Debugging in protected-mode still may work, but the initial-switch to PM must be single-stepped
;; --- modifies AX, BX, CX, DX, DI
hook2f proc
	cmp CS:[cssel], 0		;; initial switch already occured?
	jz @F
	ret
@@:
	cmp word ptr [oldi2f+2], 0
	jnz hook2f_2
	mov AX, 1687h			;; DPMI host installed?
	int 2fh
	and AX, AX
	jnz hook2f_2
	mov word ptr [dpmientry+0], DI	;; true host DPMI entry
	mov word ptr [dpmientry+2], ES
	mov word ptr [dpmiwatch+0], DI
	mov word ptr [dpmiwatch+2], ES
	cmp [bNoHook2F], 0				;; can int 2fh be hooked?
	jnz hook2f_2
	mov word ptr [dpmiwatch+0], offset mydpmientry
	mov word ptr [dpmiwatch+2], CS
	mov AX, 352fh
	int 21h
	mov word ptr [oldi2f+0], BX
	mov word ptr [oldi2f+2], ES
	mov DX, offset debug2F
	mov AX, 252fh
	int 21h
if DISPHOOK
	push DS
	pop ES
	push SI
;; --- don't use line_out here!
	mov DI, offset line_in + 128
	mov DX, DI
	mov SI, offset dpmihook
	call copystring
	pop SI
	mov AX, CS
	call hexword
	mov AL, ':'
	stosb
	mov AX, offset mydpmientry
	call hexword
	mov AX, LF*256 + CR
	stosw
	mov CX, DI
	sub CX, DX
	call stdout
endif
hook2f_2:
	push DS
	pop ES
	ret
hook2f endp
endif

endoftext16 label byte
_TEXT ends

_DATA segment
;; --- I/O buffers.
;; --- (End of permanently resident part.)
line_in		db 255, 0, CR			;; length = 257
line_out	equ line_in+LINE_IN_LEN+1	;; length = 1 + 263
real_end	equ line_in+LINE_IN_LEN+1+264
_DATA ends

_ITEXT segment
if RING0
	dd 0deadbeefh	;; marker for start of _ITEXT, don't remove!
endif

;; --- initcont is located at the start of _ITEXT because
;; --- either a word is written into this segment (the "mov [BX], ..." below)
;; --- or SP has to be adjusted before memory is freed.
;; --- AX, BX=top of memory
initcont:
if DRIVER or RING0 or BOOTDBG
	sub BX, 2
	mov [BX], offset ue_int	;; make debug display "unexpected interrupt"
 if FLATSS
	.386
	movzx EBX, BX
	add EBX, [dwBase]
	mov [run_sp], EBX
 else
	mov [run_sp], BX
 endif
 if BOOTDBG
	mov CX, AX
	mov ES, [pspdbg]		;; copy debugger beyond conv. memory
	xor DI, DI
	xor SI, SI
	rep movsb
	pop ES
	pop DS
	retf
 elseif RING0
	.386
	lss ESP, [regs.r0SSEsp]		;; switch stack back
	pushf
	and byte ptr [ESP+1], 0bfh	;; reset NT flag
	popf
	pop ES
	pop DS
	retd
 else
	ret
 endif
else
	push DS
	pop ES
	mov CL, 4
	shr BX, CL
	mov SP, AX
	mov AH, 4ah
	int 21h			;; free rest of DOS memory
	mov byte ptr [line_out-1], '0'	;; initialize line_out?
	cmp [fileext], 0
	jz @F
	call loadfile
@@:
if ALTVID
	call setscreen
endif
	jmp cmdloop
endif

;; ---------------------------------------
;; --- Debug initialization code.
;; ---------------------------------------
if ALTVID
ALTSWHLP textequ <' [/2]',>
else
ALTSWHLP textequ <>
endif

ife (DRIVER or BOOTDBG or RING0)
imsg1 db DBGNAME, ' version ', @CatStr(!', %VERSION, !'), CR, LF, LF
	db 'Usage: ', DBGNAME, ALTSWHLP ' [[drive:][path]progname [arglist]]', CR, LF, LF
 if ALTVID
	db '  /2: use alternate video adapter for output if available', CR, LF
 endif
	db '  progname: (executable) file to debug or examine', CR, LF
	db '  arglist: parameters given to program', CR, LF, LF
	db 'For a list of debugging commands, '
	db 'run ', DBGNAME, ' and type ? at the prompt.', CR, LF, '$'

imsg2	db 'Invalid switch - '
imsg2a	db 'x', CR, LF, '$'
endif

if _PM
 if DOSEMU
dDosEmuDate db "02/25/93"
 endif
endif

if VDD
szDebxxVdd	db "DEBXXVDD.DLL", 0
szDispatch	db "Dispatch", 0
szInit		db "Init", 0
endif

if DRIVER
init_req struct
	req_hdr <>
units	db ?	;; +13 number of supported units
endaddr	dd ?	;; +14 end address of resident part
cmdline	dd ?	;; +18 address of command line
init_req ends

driver_entry proc far
	push DS
	push DI
	lds DI, CS:[request_ptr]	;; load address of request header
	mov [DI].req_hdr.status, 0100h
	push BX
	push DS
	push ES
	push BP
	push DI
	push SI
	push DX
	push CX
	push CS
	pop DS
	call initcode
	mov [Intrp], offset interrupt
	mov DX, offset drv_installed
	mov AH, 9
	int 21h
	pop CX
	pop DX
	pop SI
	pop DI
	pop BP
	pop ES
	pop DS
	mov word ptr [DI].init_req.endaddr+0, BX	;; if BX == 0, driver won't be installed
	mov word ptr [DI].init_req.endaddr+2, CS	;; set end address
	pop BX
	pop DI
	pop DS
	retf
drv_installed:
	db "DebugX device driver installed", 13, 10, '$'
driver_entry endp

start:
	push CS
	pop DS
	mov DX, offset cantrun
	mov AH, 9
	int 21h
	mov AH, 4ch
	int 21h
cantrun:
	db DBGNAME2, "g v", @CatStr(!', %VERSION, !'), " is a device driver variant of Debug/X.", 13, 10
	db "It's supposed to be loaded in CONFIG.SYS via 'DEVICE=", DBGNAME2, "g.exe'.", 13, 10
	db "$"
endif

;; --- initialization.
;; --- BOOTDBG: no cmdline
;; --- RING0: ESI -> cmdline (linear address)
;; --- DRIVER: cmdline in init_req.cmdline
;; --- anything else: PSP:80h
;; --- register (E)BP must be preserved!
initcode proc
	cld
if RING0
;; --- in:
;; --- loword(AX):	dgroup selector
;; --- hiword(AX):	scratch selector
;; --- CX:	flat data selector
;; --- BP:	size dgroup (also, value of SP during init)
;; --- EBX:	offset output routine (int 10h)
;; --- EDX:	offset input routine (int 16h)
;; --- ES:EDI=IDT
	push DS
	push ES
	mov DS, AX
	mov [wFlat], CX
	shr EAX, 16
	mov [scratchsel], AX
 if LMODE
	mov [jmpv161s], CS
	mov [jmpv162s], CS
 endif
	.386
	mov AX, [ESP+2*2+4]	;; get caller's CS
	mov dword ptr [int10vec+0], EBX
	mov word ptr [int10vec+4], AX
	mov dword ptr [int16vec+0], EDX
	mov word ptr [int16vec+4], AX

;; --- set ring0 stack so output is possible during init
	mov [regs.r0Esp], ESP
	mov [regs.r0SS], SS

;; --- invalidate a & d segment part (will then be reinitialized)
	xor AX, AX
	mov [a_addr+4], AX
	mov [d_addr+4], AX

;; --- set stack
 if FLATSS
	sub ESP, 6
	sgdt [ESP]
	pop AX
	pop EDX
	movzx EBP, BP
	mov EBX, CS
	add EBX, EDX
	push DS
	mov DS, CX
	mov AL, [EBX+4]
	mov AH, [EBX+7]
	shl EAX, 16
	mov AX, [EBX+2]
	pop DS
	add EBP, EAX
	mov SS, CX
	mov ESP, EBP
	mov [dwBase], EAX
  if LMODE
;; --- get [dwBase64] - linear address of _TEXT64
;; --- depends on how _TEXT64 is aligned!
;; --- currently align 16
TEXT64ALIGN equ 16
	mov EDX, offset endoftext16
	add DX, TEXT64ALIGN-1
	and DX, not TEXT64ALIGN-1
	add EAX, EDX
	mov [dwBase64], EAX
	@dprintf "initcode: dwBase64=%lX, start TEXT64=%X", EAX, DX
  endif
 else
	mov AX, DS
	mov SS, AX
	mov SP, BP
 endif
	push ES
	push EDI	;; addr IDT now at [E/BP-6]
	@dprintf "initcode: CS=%X, DS=%X, flat=%X, EBP=%lX, ES:EDI=%X:%lX, ESI=%lX", CS, DS, CX, EBP, ES, EDI, ESI

	mov AX, DS
	mov ES, AX
	mov [machine], 3
elseif DRIVER
	mov AX, CS
elseif BOOTDBG
	push DS
	push ES
	push CS
	pop DS
	mov AX, CS
else
	mov AX, CS
	mov word ptr [execblk.cmdtail+2], AX
	mov word ptr [execblk.fcb1+2], AX
	mov word ptr [execblk.fcb2+2], AX
endif
	mov [pspdbg], AX

;; --- Check for console input vs. input from a file or other device.
if REDIRECT
	mov AX, 4400h	;; IOCTL--get info
	xor BX, BX	;; stdin
	int 21h
	jc @F
	mov [fStdin], DL
@@:
	mov AX, 4400h	;; IOCTL--get info
	mov BX, 1	;; stdout
	int 21h
	jc @F
	mov [fStdout], DL
@@:
endif

;; --- Check DOS version
ife (BOOTDBG or RING0)
	mov AX, 3000h		;; check DOS version
	int 21h
	xchg AL, AH
	cmp AX, 31fh
	jb init2		;; if version < 3.3, then don't use new int 25h method
	inc [usepacket]
 if VDD
	cmp AH, 5
	jnz @F
	mov AX, 3306h
	int 21h
	cmp BX, 3205h
	jnz @F
	mov SI, offset szDebxxVdd	;; DS:SI->"debxxvdd.dll"
	mov BX, offset szDispatch	;; DS:BX->"Dispatch"
	mov DI, offset szInit		;; ES:DI->"Init"
	RegisterModule
	jc init2
	mov [hVdd], AX
	jmp isntordos71
@@:
 endif
	cmp AX, 070ah
	jb init2
isntordos71:
	inc [usepacket]	;; enable FAT32 access method for L/W
endif

ife RING0
;; Determine the processor type.
;; This is adapted from code in the
;;	Pentium<tm> Family User's Manual,
;;	Volume 3: Architecture and Programming Manual, Intel Corp., 1994,
;;	Chapter 5.
;; That code contains the following comment:

;; This program has been developed by Intel Corporation.
;; Software developers have Intel's permission to incorporate this source code into your software royalty free.

;; Intel 8086 CPU check.
;; Bits 12-15 of the FLAGS register are always set on the 8086 processor.
;; Probably the 186 as well.
init2:
	push SP
	pop AX
	cmp AX, SP
	jnz init6		;; if 8086 or 80186 (can't tell them apart)

;; Intel 286 CPU check.
;; Bits 12-15 of the flags register are always clear on the
;; Intel 286 processor in real-address mode.
	mov [machine], 2
	pushf			;; get original flags into AX
	pop AX
	or AX, 0f000h		;; try to set bits 12-15
	push AX			;; save new flags value on stack
	popf			;; replace current flags value
	pushf			;; get new flags
	pop AX			;; store new flags in AX
	test AH, 0f0h		;; if bits 12-15 clear, CPU = 80286
	jz init6		;; if 80286

;; Intel 386 CPU check.
;; The AC bit, bit #18, is a new bit introduced in the EFLAGS register on the Intel486 DX cpu to generate alignment faults.
;; This bit cannot be set on the Intel386 CPU.
	inc [machine]
;; It is now safe to use 32-bit opcode/operands.
endif

	.386

	mov BX, SP		;; save current stack pointer to align
	and SP, not 3		;; align stack to avoid AC fault
	pushfd			;; push original EFLAGS
	pop EAX			;; get original EFLAGS
	mov ECX, EAX		;; save original EFLAGS in CX
	xor EAX, 40000h		;; flip (XOR) AC bit in EFLAGS
	push EAX		;; put new EFLAGS value on stack
	popfd			;; replace EFLAGS value
	pushfd			;; get new EFLAGS
	pop EAX			;; store new EFLAGS value in EAX
	cmp EAX, ECX
	jz init5		;; if 80386 CPU

;; Intel 486 DX CPU, Intel487 SX NDP, and Intel486 SX CPU check.
;; Checking for ability to set/clear ID flag (bit 21) in EFLAGS
;; which indicates the presence of a processor with the ability to use the CPUID instruction.
;;	inc [machine]		;; it's a 486
	mov EAX, ECX		;; get original EFLAGS
	xor EAX, 200000h	;; flip (XOR) ID bit in EFLAGS
	push EAX		;; save new EFLAGS value on stack
	popfd			;; replace current EFLAGS value
	pushfd			;; get new EFLAGS
	pop EAX			;; store new EFLAGS in EAX
	cmp EAX, ECX		;; check if it's changed
	je init5		;; if it's a 486 (can't toggle ID bit)
	push ECX
	popfd			;; restore AC bit in EFLAGS first
	mov SP, BX		;; restore original stack pointer

;; --- Execute CPUID instruction.

	.586

	xor EAX, EAX		;; set up input for CPUID instruction
	cpuid
	cmp EAX, 1
	jl init6		;; if 1 is not a valid input value for CPUID
	xor EAX, EAX		;; otherwise, run CPUID with AX = 1
	inc EAX
	cpuid
if MMXSUPP
	test EDX, 800000h
	setnz [has_mmx]
endif
	mov AL, AH
	and AL, 0fh		;; bits 8-11 are the model number
	cmp AL, 6
	jbe init3		;; if <= 6
	mov AL, 6		;; if > 6, set it to 6
init3:
	mov [machine], AL	;; save it
	jmp init6		;; don't restore SP

init5:
	push ECX
	popfd			;; restore AC bit in EFLAGS first
	mov SP, BX		;; restore original stack pointer

ife RING0
	.8086			;; back to 1980s technology
endif

;; Next determine the type of FPU in a system and set the mach_87 variable with the appropriate value.

;; Coprocessor check.
;; The algorithm is to determine whether the floating-point status and control words can be written to.
;; If not, no coprocessor exists.
;; If the status and control words can be written to, the correct coprocessor is then determined depending on the processor ID.
;; The Intel386 CPU can work with either an Intel 287 NDP or an Intel387 NDP.
;; The infinity of the coprocessormust be checked to determine the correct coprocessor ID.
init6:
ife RING0
	mov BP, SP
BPOFS equ <BP-2>
else
 if FLATSS
BPOFS equ <EBP-8>		;; for RING0, there're already 6 bytes used
 else
BPOFS equ <BP-8>		;; for RING0, there're already 6 bytes used
 endif
endif
	mov AL, [machine]
	mov [mach_87], AL	;; by default, set mach_87 to machine
	inc [has_87]
	cmp AL, 5		;; a Pentium or above always will have a FPU
	jnc init7
	dec [has_87]

	fninit			;; reset FP status word
	mov AX, 5a5ah		;; init with non-zero value
	push AX
	fnstsw [BPOFS]		;; save FP status word
	pop AX			;; check FP status word
	cmp AL, 0
	jne init7		;; if no FPU present

	push AX
	fnstcw [BPOFS]		;; save FP control word
	pop AX			;; check FP control word
	and AX, 103fh		;; see if selected parts look OK
	cmp AX, 3fh
	jne init7		;; if no FPU present
	inc [has_87]		;; there's an FPU
;; --- If we're using a 386, check for 287 vs. 387 by checking whether +infinity = -infinity.
	cmp [machine], 3
	jne init7		;; if not a 386
	fld1			;; must use default control from fninit
	fldz			;; form infinity
	fdivp ST(1), ST		;; 1/0 = infinity
	fld ST			;; form negative infinity
	fchs
	fcompp			;; see if they are the same and remove them
if RING0
	fstsw AX
else
	push AX
	fstsw [BPOFS]		;; look at status from fcompp
	pop AX
endif
	sahf
	jnz init7		;; if they are different, then it's a 387
	dec [mach_87]	;; otherwise, it's a 287
init7:
;; --- remove size and addr prefixes if cpu is < 80386
;;	mov [machine], 2	;; activate to test non-386 code branches
ife RING0
	cmp [machine], 3
	jnb nopatch
	mov SI, offset patches
	mov CX, cntpatch
@@:
	lodsw
	xchg AX, BX
	mov byte ptr [BX], 90h
	loop @B
	mov [patch_movsp], 3eh	;; set ("unnecessary") DS segment prefix
	mov [patch_iret], 0cfh	;; code for iret
nopatch:
endif

;; --- Interpret switches and erase them from the command line.
ife BOOTDBG
 ife RING0
	mov AX, 3700h		;; get switch character in DL
	int 21h
	mov [swchar], DL
	cmp DL, '/'
	jne @F
	mov [swch1], DL
@@:
 endif

 if RING0
	mov ES, [wFlat]
 elseif DRIVER
	les SI, CS:[request_ptr]	;; load address of request header
	les SI, ES:[SI].init_req.cmdline
@@:
	lodsb ES:[SI]		;; skip program name
	cmp AL, 13
	jz @F
	cmp AL, ' '
	jnz @B
@@:
 else
	mov SI, DTA+1
 endif
contparse:
@@:
 if RING0
	.386
	lodsb ES:[ESI]
	.8086
 elseif DRIVER
	lodsb ES:[SI]
 else
	lodsb
 endif
	cmp AL, ' '
	je @B
	cmp AL, TAB
	je @B
;; --- Process the /? switch (or the [swchar]? switch).
;; --- If swchar != / and /? occurs, make sure nothing follows.
	cmp AL, [swchar]
	je @F			;; if switch character
	cmp AL, '/'
	jne doneoptions		;; if not the help switch
@@:
 if RING0
	.386
	lodsb ES:[ESI]
	.8086
 elseif DRIVER
	lodsb ES:[SI]
 else
	lodsb
	cmp AL, '?'
	jne @F
;; helpexit:			;; Print help message and exit
	mov DX, offset imsg1	;; command-line help message
;;	call int21ah9	;; v2.0: int21ah9 cannot be used (pInDOS not yet set)
	mov AH, 9
	int 21h
	int 20h			;; done
@@:
 endif

 if ALTVID
	cmp AL, '2'
	jnz noopt2
	mov AX, 1a00h
  if RING0
	.386
	call [int10vec]
  else
	int 10h
  endif
	cmp AL, 1ah
	jnz noaltvid
	cmp BH, 0
	jz noaltvid
	mov byte ptr [setscreen], 1eh	;; "push DS"
	push DS
	mov AX, 40h		;; segment value 40h even works in Jemm ring 0
	mov DS, AX
	mov DX, DS:[63h]
	pop DS
	xor DL, 60h
	mov [oldcrtp], DX
	mov AL, 7
	cmp DL, 0b4h
	jz @F
	mov AL, 3
@@:
	mov [oldmode], AL
;; --- to initially get the cursor pos of the alt screen, read the CRT.
;; --- this code assumes that page 0 is active (offset == 0);
;; --- could be fixed by reading CRT 0ch/0dh.
	mov AL, 0eh
	out DX, AL
	inc DX
	in AL, DX
	mov AH, AL
	dec DX
	mov AL, 0fh
	out DX, AL
	inc DX
	in AL, DX
	mov BL, 80
	div BL
	xchg AL, AH
	mov [oldcsrpos], AX
noaltvid:
	jmp contparse
noopt2:
 endif

;; --- ||| Other switches may go here.

 if MCLOPT and (CATCHINT0C or CATCHINT0D)
	cmp AL, 'm'		;; /m cmdline option?
	jnz @F
	mov [bMPicB], 20h
	jmp contparse
@@:
 endif

 if RING0 and CATCHINT41
	cmp AL, 'i'		;; /i cmdline option?
	jnz noopti
	mov [itab41.bInt], -1	;; deactivate Int 41h hook
	jmp contparse
noopti:
 endif

 ife (DRIVER or RING0)	;; those versions ignore invalid cmdline args
	mov [imsg2a], AL
	mov DX, offset imsg2	;; Invalid switch
;;	call int21ah9	;; v2.0: int21ah9 cannot be used (pInDOS not yet set)
	mov AH, 9
	int 21h
	mov AX, 4c01h	;; Quit and return error status
	int 21h
 endif

doneoptions:
 ife (DRIVER or RING0)
	dec SI
	lodsb
	call n_cmd		;; Feed the remaining command line to the 'n' command.
 endif
endif	;; ife BOOTDBG

if BOOTDBG
;; --- get final address of debugger behind conv. memory
	push DS
	xor CX, CX
	mov DS, CX
	mov AX, offset real_end + STACKSIZ + (1024-1)
	mov CL, 10
	shr AX, CL
	sub DS:[413h], AX
	mov AX, DS:[413h]
	pop DS
	mov CL, 6
	shl AX, CL
	mov [pspdbg], AX
endif

if DMCMD
	mov AH, 52h		;; get list of lists
	int 21h
	mov AX, ES:[BX-2]	;; start of MCBs
	mov [wMCB], AX
endif

ife (BOOTDBG or RING0)
	mov AH, 34h
	int 21h
	mov word ptr [pInDOS+0], BX
	mov word ptr [pInDOS+2], ES
endif
;; --- get address of DOS swappable DATA area
;; --- to be used to get/set PSP and thus avoid DOS calls
;; --- will not work for DOS < 3
if USESDA
	push DS
	mov AX, 5d06h
	int 21h
	mov AX, DS
	pop DS
	jc @F
	mov word ptr [pSDA+0], SI
	mov word ptr [pSDA+2], AX
@@:
endif

if _PM
;; --- Windows 3x/9x and DosEmu are among those hosts which handle some
;; --- V86 Ints internally without first calling the interrupt chain.
;; --- This causes various sorts of troubles and incompatibilities.
 if WIN9XSUPP
	mov AX, 1600h	;; running in a win3x/win9x dos box?
	int 2fh
	and AL, AL		;; returns in AL 3=win3x, 4=win9x
	jnz no2fhook
 endif
 if DOSEMU
	mov AX, 0f000h
	mov ES, AX
	mov DI, 0fff5h
	mov SI, offset dDosEmuDate
	mov CX, 4
	repe cmpsw		;; running in DosEmu?
	jz no2fhook
 endif
	jmp dpmihostchecked
no2fhook:
	inc [bNoHook2F]
dpmihostchecked:
endif
	push DS
	pop ES
if INT22
;; --- Save and modify termination address and the parent PSP field.
	mov SI, TPIV
	mov DI, offset psp22
	movsw
	movsw
	mov word ptr [SI-4], offset intr22dbg

	mov [SI-2], CS
	mov SI, PARENT
	movsw
	mov [SI-2], CS
	mov [pspdbe], CS	;; indicate there is no debuggee loaded yet
endif

if VXCHG
 ifndef VXCHGFLIP
	mov AX, 4300h	;; check if XMM is here
	int 2fh
	cmp AL, 80h
	jnz noxmm		;; no - no screen flip
	mov AX, 4310h
	int 2fh
	mov word ptr [xmsdrv+0], BX
	mov word ptr [xmsdrv+2], ES
	.286
	mov DX, 32		;; alloc 32 kB EMB
	mov AH, 9
	call [xmsdrv]
	cmp AX, 1
	jnz noxmm
	mov SI, offset xmsmove
	mov [SI].XMSM.dsthdl, DX			;; save the handle in block move struct.
	mov byte ptr [SI].XMSM.dstadr+1, 40h		;; the XMS memory will be used to
	push 0								;; save/restore 2 screens, with a max
	pop ES								;; capacity per screen of 16 kB
	mov AX, ES:[44ch]					;; current screen size, might change!
	mov word ptr [SI].XMSM.size_, AX
	mov AX, ES:[44eh]					;; page start in video memory
	mov word ptr [SI].XMSM.srcadr+0, AX
	mov AX, 0b000h
	cmp byte ptr ES:[463h], 0b4h
	jz @F
	or AH, 8
@@:
	mov word ptr [SI].XMSM.srcadr+2, AX
	mov AL, ES:[484h]
	mov [vrows], AL
	mov AH, 0fh					;; get active video page in BH
	int 10h
	mov AH, 3					;; get cursor pos in DX of active page
	int 10h
	mov [csrpos], DX
	mov AH, 0bh					;; save current screen now
	call [xmsdrv]
	.8086
noxmm:
 else
;; --- use BIOS to swap page 0/1, a simple approach
;; --- that in theory would fit perfectly, but
;; --- unfortunately in reality may have quirks.
  if RING0
	.386
	push DS
	mov DS, [wFlat]
	movzx ESI, word ptr DS:[44eh]
	movzx ECX, word ptr DS:[44ch]
	mov DX, DS:[450h+0*1]
	mov DS:[450h+1*2], DX
	mov EAX, 0b0000h
	cmp byte ptr DS:[463], 0b4h
	jz @F
	or AH, 80h
@@:
	mov EDI, ESI
	add EDI, ECX
	add ESI, EAX
	add EDI, EAX
	push DS
	pop ES
	rep movsb ES:[EDI], DS:[ESI]
	pop DS
	.8086
  else
	xor AX, AX
	mov ES, AX
	mov SI, ES:[44eh]	;; page offset curr page
	mov CX, ES:[44ch]	;; page size
	shr CX, 1
	mov AX, 0501h	;; debugger page is 1
  ife (DRIVER or BOOTDBG)
	mov [vpage], AL		;; std: init here since we'll jump right into the debugger
  endif
	int 10h
	mov DI, ES:[44eh]	;; page offset page 1
	mov DX, ES:[450h+0*1]
	mov ES:[450h+1*2], DX
	mov AX, 0b000h		;; copy page contents to page 1
	cmp byte ptr ES:[463h], 0b4h
	jz @F
	or AH, 8
@@:
	push DS
	mov ES, AX
	mov DS, AX
	rep movsw
	pop DS
  endif
 endif
	push DS
	pop ES
endif

;; --- Set up interrupt vectors.

	mov CX, NUMINTS
	mov SI, offset inttab
	mov DI, offset intsave
if RING0
	.386
	les EBX, [BP-6]
	@dprintf "initcode: setup int vectors, ES:EBX=%X:%lX", ES, EBX
elseif BOOTDBG
	xor AX, AX
	mov ES, AX
endif
@@:
	lodsb
if RING0
	cmp AL, -1
	jz skipint
	movzx EDX, AL
 if LMODE
	shl EDX, 1	;; in long mode, vector size is 16
 endif
	mov AX, ES:[EBX+EDX*8+0]
	mov [DI+0], AX
	mov AX, ES:[EBX+EDX*8+6]
	mov [DI+2], AX
	mov AX, ES:[EBX+EDX*8+2]
	mov [DI+4], AX
elseif BOOTDBG
	mov BL, AL
	mov BH, 0
	shl BX, 1
	shl BX, 1
	mov AX, ES:[BX+0]
	mov DX, ES:[BX+2]
	mov [DI+0], AX
	mov [DI+2], DX
else
	mov AH, 35h
	int 21h
	mov [DI+0], BX
	mov [DI+2], ES
	xchg AX, DX		;; save int # in DL
endif
	mov AX, [SI]	;; get address
if RING0
 if LMODE
	movzx EAX, AX
	add EAX, [dwBase64]
	mov ES:[EBX+EDX*8+0], AX
	mov word ptr ES:[EBX+EDX*8+2], 8	;; selector 8 is 64-bit (Dos32cm)
	shr EAX, 16
 else
	mov ES:[EBX+EDX*8+0], AX
	mov ES:[EBX+EDX*8+2], CS
	xor AX, AX
 endif
	mov ES:[EBX+EDX*8+6], AX
skipint:
elseif BOOTDBG
	mov DX, [pspdbg]
	mov ES:[BX+0], AX
	mov ES:[BX+2], DX
else
	xchg AX, DX		;; AL=int#, DX=offset
	mov AH, 25h		;; set interrupt vector
	int 21h
endif
	add SI, 2
	add DI, sizeof INTVEC
	loop @B

;; --- prepare to shrink Debug and set its stack

	mov AX, offset real_end + STACKSIZ + 15
	and AL, not 15		;; debug's top of stack
	mov BX, AX
if FLATSS
	add EAX, [dwBase]
	mov [top_sp], EAX
	@dprintf "top_sp=%lX", EAX
else
	mov [top_sp], AX
endif
	jmp initcont

initcode endp
_ITEXT ends

_IDATA segment
cntpatch = ($ - patches)/2
_IDATA ends
	end start
