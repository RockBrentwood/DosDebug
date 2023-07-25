## For the C programs.
#X=.exe
X=

## The Assembler - this requires an installation of jwasm.
#AS=cas
#AS=gas
AS=jwasm

## The Output Format
## Attempts to make ELF-compatible binaries directly will not work, without modifications to the *.asm and *.inc sources.
#BinMode=-elf64
#BinMode=-elf
BinMode=-bin

ExeMode=-mz

## The Path-Name Separator.
#Z="\\"
Z=/

## The Binaries Directory.
BinDir=bin$Z

## The Listings Directory.
LogDir=log$Z

##
#RM=del
RM=rm -f

## Create all Debug versions.
all: \
	${BinDir}Debug.com ${BinDir}DebugX.com \
	${BinDir}DebugXD.com ${BinDir}DebugXE.com ${BinDir}DebugXF.com \
	${BinDir}DebugXG.exe ${BinDir}DebugXU.com ${BinDir}DebugXV.com \
	${BinDir}DebugB.bin ${BinDir}DebugR.bin ${BinDir}DebugRL.bin

## Run MakeTabs$X.
DebugTab.inc: MakeTabs$X Op.set Op.key Op.ord
	./MakeTabs$X

## Create MakeTabs$X.
## On Windows, using Open Watcom:
##	here jwlink is used instead of wlink
##	\watcom\binnt\wcc -q -ox -i\watcom\h -3 -fo=${LogDir}MakeTabs.obj MakeTabs.c
##	\watcom\binnt\wlink system dos f ${LogDir}MakeTabs.obj n ${LogDir}MakeTabs.exe op q,m=${LogDir}MakeTabs.map
## On Windows, using MSVC v1.52:
##	\msvc\bin\cl -c -nologo -G3 -Fo ${LogDir}MakeTabs.obj -I\msvc\include MakeTabs.c
##	set lib=\msvc\lib
##	\msvc\bin\link /NOLOGO ${LogDir}MakeTabs.obj,${LogDir}MakeTabs.exe,${LogDir}MakeTabs.map /NON;
##	jwlink format dos f ${LogDir}MakeTabs.obj n ${LogDir}MakeTabs.exe libpath \watcom\lib286\dos libpath \watcom\lib286 op q,m=${LogDir}MakeTabs.map
## On Linux, using GCC:
MakeTabs$X: MakeTabs.c
	gcc MakeTabs.c -o MakeTabs

## Create Debug[X].com
${BinDir}Debug.com: Debug.asm TrapR.inc
##	${AS} -nologo ${BinMode} -Fo $@ -Fl${LogDir}Debug.lst Debug.asm ## The original.
	${AS} -nologo -D_PM=0 ${BinMode} -Fo $@ -Fl${LogDir}Debug.lst Debug.asm
${BinDir}DebugX.com: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 -DALTVID=1 ${BinMode} -Fo $@ -Fl${LogDir}DebugX.lst Debug.asm

## Create the special versions: DebugX{D,E,F,U,V}.com and DebugXG.exe.
## XD: Debug version of DebugX.
## XE: checks for exc 06, 0c and 0d in real-mode.
## XF: client can't modify exc 01, 03, 0d and 0e in protected-mode.
## XG: device driver version of DebugX.
## XU: dx cmd uses unreal mode.
## XV: v cmd flips screens & sysreq trapped.
${BinDir}DebugXD.com: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 ${BinMode} -Fo $@ -Fl=${LogDir}DebugXD.lst -DCATCHINT01=0 -DCATCHINT03=0 -DPROMPT=] Debug.asm
${BinDir}DebugXE.com: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 ${BinMode} -Fo $@ -Fl=${LogDir}DebugXE.lst -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 Debug.asm
${BinDir}DebugXF.com: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 ${BinMode} -Fo $@ -Fl=${LogDir}DebugXF.lst -DCATCHINT31=1 Debug.asm
${BinDir}DebugXG.exe: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 ${ExeMode} -Fo $@ -Fl=${LogDir}DebugXG.lst -DDRIVER=1 Debug.asm
${BinDir}DebugXU.com: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 ${BinMode} -Fo $@ -Fl=${LogDir}DebugXU.lst -DUSEUNREAL=1 -DCATCHINT0D=1 Debug.asm
${BinDir}DebugXV.com: Debug.asm TrapR.inc TrapD.inc
	${AS} -nologo -D_PM=1 ${BinMode} -Fo $@ -Fl=${LogDir}DebugXV.lst -DVXCHG=1 -DCATCHSYSREQ=1 Debug.asm

## Create the binary versions: Debug{B,R,RL}.bin.
## B: A "boot loader" version..
## R: A protected-mode "ring 0" version.
## RL: A protected-mode "ring 0" version for long mode.
${BinDir}DebugB.bin: Debug.asm TrapR.inc
	${AS} -nologo ${BinMode} -Fo $@ -Fl=${LogDir}DebugB.lst -DBOOTDBG=1 Debug.asm
${BinDir}DebugR.bin: Debug.asm TrapP.inc
	${AS} -nologo ${BinMode} -Fo $@ -Fl=${LogDir}DebugR.lst -DRING0=1 Debug.asm
${BinDir}DebugRL.bin: Debug.asm TrapPL.inc
	${AS} -nologo ${BinMode} -Fo $@ -Fl=${LogDir}DebugRL.lst -Sg -DRING0=1 -DLMODE=1 Debug.asm

Debug.asm: DebugTab.inc DPrintF.inc FpToStr.inc DisAsm.inc

clean:
	${RM} ${LogDir}Debug*.lst
	${RM} MakeTabs$X
clobber: clean
	${RM} ${BinDir}Debug*.bin
	${RM} ${BinDir}Debug*.com
	${RM} ${BinDir}Debug*.exe
