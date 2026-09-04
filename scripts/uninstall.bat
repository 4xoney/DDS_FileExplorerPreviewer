@echo off
setlocal EnableExtensions EnableDelayedExpansion

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "INSTALL_DIR=%ProgramFiles%\DDS Thumbnail Provider"
set "LEGACY_INSTALL_DIR=%ProgramFiles%\DdsThumbnailProvider"
set "PROVIDER_DLL="
set "SRM=%INSTALL_DIR%\ServerRegistrationManager.exe"

for /f "tokens=2,*" %%A in ('reg.exe query "HKLM\SOFTWARE\Classes\CLSID\{4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E}\InprocServer32" /v CodeBase 2^>nul ^| findstr.exe /I /C:"CodeBase"') do set "PROVIDER_DLL=%%B"
if defined PROVIDER_DLL (
    set "PROVIDER_DLL=!PROVIDER_DLL:file:///=!"
    set "PROVIDER_DLL=!PROVIDER_DLL:/=\!"
    set "PROVIDER_DLL=!PROVIDER_DLL:%%20= !"
)

if not exist "%SRM%" if defined PROVIDER_DLL for %%I in ("!PROVIDER_DLL!") do if exist "%%~dpIServerRegistrationManager.exe" set "SRM=%%~dpIServerRegistrationManager.exe"

if defined PROVIDER_DLL if exist "!PROVIDER_DLL!" if exist "%SRM%" (
    "%SRM%" uninstall "!PROVIDER_DLL!" -os64
    if errorlevel 1 goto :failed
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0remove-installation.ps1" -InstallDirectory "%INSTALL_DIR%"
if errorlevel 1 goto :cleanup_failed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0remove-installation.ps1" -InstallDirectory "%LEGACY_INSTALL_DIR%"
if errorlevel 1 goto :cleanup_failed

echo.
echo DDS thumbnail provider uninstalled successfully.
if exist "%INSTALL_DIR%" echo In-use files are scheduled for deletion at the next Windows restart.
if exist "%LEGACY_INSTALL_DIR%" echo Legacy in-use files are scheduled for deletion at the next Windows restart.
pause
exit /b 0

:failed
echo.
echo ERROR: Unregistration failed; installed files were left in place.
pause
exit /b 1

:cleanup_failed
echo.
echo ERROR: The provider was unregistered, but some installed files could not be removed or scheduled for deletion.
pause
exit /b 1
