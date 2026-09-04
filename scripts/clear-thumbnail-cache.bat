@echo off
setlocal EnableExtensions

echo This requests a thumbnail refresh without stopping Windows Explorer.
choice /C YN /M "Continue"
if errorlevel 2 exit /b 0

del /F /Q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
if exist "%SystemRoot%\System32\ie4uinit.exe" "%SystemRoot%\System32\ie4uinit.exe" -show >nul 2>&1

echo Thumbnail refresh requested. Windows may keep cache files that are in use.
echo If an old thumbnail remains, sign out and back in instead of force-closing Explorer.
pause
