## Builds MakeTabs.exe and, upon successful compilation, DebugTab.inc from it.
## This step is only required if one of the following files were modified:
## ∙	Op.set
## ∙	Op.key
## ∙	Op.ord
## ∙	MakeTabs.c
## On Windows, if using Open Watcom
##	here jwlink is used instead of wlink
##	\watcom\binnt\wcc -q -ox -i\watcom\h -3 -fo=bin\MakeTabs.obj MakeTabs.c
##	\watcom\binnt\wlink system dos f bin\MakeTabs.obj n bin\MakeTabs.exe op q,m=bin\MakeTabs.map
## On Windows, if using MSVC v1.52
##	\msvc\bin\cl -c -nologo -G3 -Fobin\MakeTabs.obj -I\msvc\include MakeTabs.c
##	set lib=\msvc\lib
##	\msvc\bin\link /NOLOGO bin\MakeTabs.obj,bin\MakeTabs.exe,bin\MakeTabs.map /NON;
##	jwlink format dos f bin\MakeTabs.obj n bin\MakeTabs.exe libpath \watcom\lib286\dos libpath \watcom\lib286 op q,m=bin\MakeTabs.map
## On Linux, using GCC:
## @echo off
gcc MakeTabs.c -o MakeTabs && ./MakeTabs
