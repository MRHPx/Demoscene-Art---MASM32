@echo off
set nama=demoscene
set letak=C:\masm32\bin
set include=C:\masm32\include
set lib=C:\masm32\lib

del %nama%.exe
del *.obj
del *.obj
del *.RES

cls

if not exist %nama%.rc goto langsunghapus
%letak%\Rc.exe /v %nama%.rc
%letak%\Cvtres.exe /machine:ix86 %nama%.res
:langsunghapus

if exist %1.obj del %nama%.obj
if exist %1.exe del %nama%.exe

%letak%\Ml.exe /c /coff /I%include% %nama%.asm
if errorlevel 1 goto assemblersalah

if not exist %nama%.res goto gakpakeresource

%letak%\Link.exe /SUBSYSTEM:WINDOWS /LIBPATH:%lib% %nama%.obj %nama%.res
if errorlevel 1 goto linksalah

goto sipker

:gakpakeresource
%letak%\Link.exe /SUBSYSTEM:WINDOWS /LIBPATH:%lib% %nama%.obj
if errorlevel 1 goto linksalah

goto sipker

:linksalah
echo _
echo LINK ADA YANG SALAH REK!
pause
goto buyar

:assemblersalah
echo _
echo ASSEMBLY ADA YANG SALAH REK!
pause
goto buyar

:sipker
if exist *.obj del *.obj
if exist *.res del *.res
echo SIP SEMUA REK!
pause
%nama%.exe

:buyar