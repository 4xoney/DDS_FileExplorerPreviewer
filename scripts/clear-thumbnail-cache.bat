@echo off
setlocal EnableExtensions

echo This closes Explorer and deletes the current user's Windows thumbnail cache.
choice /C YN /M "Continue"
if errorlevel 2 exit /b 0

taskkill /F /IM explorer.exe >nul 2>&1
timeout /t 1 /nobreak >nul
del /F /Q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
start "" explorer.exe

echo Thumbnail cache cleared.
pause
