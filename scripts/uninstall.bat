@echo off
setlocal EnableExtensions

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=%ProgramFiles%\DdsThumbnailProvider"
set "PROVIDER_DLL=%INSTALL_DIR%\DdsThumbnailProvider.dll"
set "SRM=%INSTALL_DIR%\ServerRegistrationManager.exe"

if exist "%PROVIDER_DLL%" if exist "%SRM%" (
    "%SRM%" uninstall "%PROVIDER_DLL%" -os64
    if errorlevel 1 goto :failed
)

taskkill /F /IM explorer.exe >nul 2>&1
timeout /t 1 /nobreak >nul

if exist "%INSTALL_DIR%" rmdir /S /Q "%INSTALL_DIR%"
start "" explorer.exe

echo.
echo DDS thumbnail provider uninstalled successfully.
pause
exit /b 0

:failed
echo.
echo ERROR: Unregistration failed; installed files were left in place.
pause
exit /b 1
