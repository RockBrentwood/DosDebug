## Create special Debug versions.

## The Path-Name Separator.
#Z="\\"
Z=/

## The Binaries Directory.
BinDir=bin$Z

## The Listings Directory.
LogDir=log$Z

## The Assembler - this requires an installation of jwasm.
#AS=cas
#AS=gas
AS=jwasm

## The Output Formats.
## Attempts to make ELF-compatible binaries directly will not work, without modifications to the *.asm and *.inc sources.
#BinMode=-elf64
#BinMode=-elf
BinMode=-bin
ExeMode=-mz

echo creating DebugXD - debug version of DebugX
${AS} -nologo -D_PM=1 ${BinMode} -Fo ${BinDir}DebugXD.com -Fl=${LogDir}DebugXD.lst -DCATCHINT01=0 -DCATCHINT03=0 -DPROMPT=] Debug.asm

echo creating DebugXE - checks for exc 06, 0C and 0D in real-mode
${AS} -nologo -D_PM=1 ${BinMode} -Fo ${BinDir}DebugXE.com -Fl=${LogDir}DebugXE.lst -DCATCHINT06=1 -DCATCHINT0C=1 -DCATCHINT0D=1 Debug.asm

echo creating DebugXF - the client cannot modify exc 01, 03, 0D and 0E in protected-mode
${AS} -nologo -D_PM=1 ${BinMode} -Fo ${BinDir}DebugXF.com -Fl=${LogDir}DebugXF.lst -DCATCHINT31=1 Debug.asm

echo creating DebugXG - device driver version of DebugX
${AS} -nologo -D_PM=1 ${ExeMode} -Fo ${BinDir}DebugXG.exe -Fl=${LogDir}DebugXG.lst -DDRIVER=1 Debug.asm

echo creating DebugXU - dx cmd uses unreal mode
${AS} -nologo -D_PM=1 ${BinMode} -Fo ${BinDir}DebugXU.com -Fl=${LogDir}DebugXU.lst -DUSEUNREAL=1 -DCATCHINT0D=1 Debug.asm

echo creating DebugXV - v cmd flips screens \& sysreq trapped
${AS} -nologo -D_PM=1 ${BinMode} -Fo ${BinDir}DebugXV.com -Fl=${LogDir}DebugXV.lst -DVXCHG=1 -DCATCHSYSREQ=1 Debug.asm

echo creating DebugB.bin - a "boot loader" version
${AS} -nologo ${BinMode} -Fo ${BinDir}DebugB.bin -Fl=${LogDir}DebugB.lst -DBOOTDBG=1 Debug.asm

echo creating DebugR.bin - a protected-mode "ring 0" version
${AS} -nologo ${BinMode} -Fo ${BinDir}DebugR.bin -Fl=${LogDir}DebugR.lst -DRING0=1 Debug.asm

echo creating DebugRL.bin - a protected-mode "ring 0" version for long mode
${AS} -nologo ${BinMode} -Fo ${BinDir}DebugRL.bin -Fl=${LogDir}DebugRL.lst -DRING0=1 -DLMODE=1 Debug.asm
