## Create the main Debug versions.

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

## The Output Format
## Attempts to make ELF-compatible binaries directly will not work, without modifications to the *.asm and *.inc sources.
#BinMode=-elf64
#BinMode=-elf
BinMode=-bin

echo creating Debug.com
${AS} -nologo -D_PM=0 ${BinMode} -Fo${BinDir}Debug.com -Fl${LogDir}Debug.lst Debug.asm && chmod 775 ${BinDir}Debug.com
echo creating DebugX.com
${AS} -nologo -D_PM=1 -DALTVID=1 ${BinMode} -Fo ${BinDir}DebugX.com -Fl${LogDir}DebugX.lst Debug.asm && chmod 775 ${BinDir}DebugX.com
## ml -c -nologo -D_PM=1 -Fo ${BinDir}DebugX.obj -Fl${LogDir}DebugX.lst Debug.asm
