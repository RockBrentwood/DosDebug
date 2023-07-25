X=.exe
S=.asm
AS=jwasm
RM=rm -f
ASOPTS=-mz
MODS=CodeTS32 DbgMbr HugeSeg Leave Str32 TestI2F TestQQ UnReal
EXES=$(MODS:%=%$X)
ASMS=$(MODS:%=%$S)

all: ${EXES}

##$S$X:
##	${AS} ${ASOPTS} $^

CodeTS32$X: CodeTS32$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
DbgMbr$X: DbgMbr$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
HugeSeg$X: HugeSeg$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
Leave$X: Leave$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
Str32$X: Str32$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
TestI2F$X: TestI2F$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
TestQQ$X: TestQQ$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@
UnReal$X: UnReal$S
	${AS} ${ASOPTS} $^ -Fo $@ && chmod 775 $@

clean:
	${RM} *.err
clobber: clean
	${RM} ${EXES}
