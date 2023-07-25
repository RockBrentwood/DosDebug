## Assemble the samples which are written in masm syntax.
#Z="\\"
Z=/

## The Assembler - jwasm is used.
#AS=cas
#AS=gas
AS=jwasm

## The Output Format
## Attempts to make ELF-compatible binaries directly will not work, without modifications to the *.asm and *.inc sources.
#BinMode=-elf64
#BinMode=-elf
BinMode=-bin
#ExeMode=-bin
ExeMode=-mz

${AS} -nologo ${BinMode} -Fo dpmicl16.com dpmicl16.asm && chmod 775 dpmicl16.com
${AS} -nologo ${BinMode} -Fo dpmibk16.com dpmibk16.asm && chmod 775 dpmibk16.com
${AS} -nologo ${ExeMode} -Fo dpmicl32.exe dpmicl32.asm && chmod 775 dpmicl32.exe
${AS} -nologo ${ExeMode} -Fo dpmibk32.exe dpmibk32.asm && chmod 775 dpmibk32.exe
