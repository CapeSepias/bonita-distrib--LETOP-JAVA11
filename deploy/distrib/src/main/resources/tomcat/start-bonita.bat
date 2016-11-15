@echo off
setlocal

IF NOT EXIST setup GOTO NOSETUPDIR
   shift
   call setup\setup.bat init %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
   if errorlevel 1 (
       exit /b 1
   )
   call setup\setup.bat configure %0 %1 %2 %3 %4 %5 %6 %7 %8 %9
   if errorlevel 1 (
       exit /b 1
   )

:NOSETUPDIR
cd server
call bin\startup.bat
cd ..
