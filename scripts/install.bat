@echo off
setlocal EnableExtensions

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SOURCE_DIR=%~dp0..\bin\x64\Release\net48"
set "INSTALL_DIR=%ProgramFiles%\DdsThumbnailProvider"
set "PROVIDER_DLL=%INSTALL_DIR%\DdsThumbnailProvider.dll"
set "SRM=%INSTALL_DIR%\ServerRegistrationManager.exe"

if not exist "%SOURCE_DIR%\DdsThumbnailProvider.dll" (
    echo ERROR: Release build not found.
    echo Run scripts\build-release.bat first.
    pause
    exit /b 1
)

if exist "%PROVIDER_DLL%" if exist "%SRM%" (
    "%SRM%" uninstall "%PROVIDER_DLL%" -os64 >nul 2>&1
)

taskkill /F /IM explorer.exe >nul 2>&1
timeout /t 1 /nobreak >nul

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy "%SOURCE_DIR%\*" "%INSTALL_DIR%\" /E /I /Y /Q >nul
if errorlevel 1 goto :failed

"%SRM%" install "%PROVIDER_DLL%" -codebase -os64
if errorlevel 1 goto :failed

reg.exe query "HKLM\SOFTWARE\Classes\.dds\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}" /ve 2>nul | findstr.exe /I /C:"{4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E}" >nul
if errorlevel 1 (
    echo ERROR: The direct .dds thumbnail association was not registered.
    goto :failed
)

del /F /Q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1

start "" explorer.exe
echo.
echo DDS thumbnail provider 1.0.2 installed successfully.
echo Open a folder containing DDS files and choose a large-icon view.
pause
exit /b 0

:failed
start "" explorer.exe
echo.
echo ERROR: Installation failed. Explorer has been restarted.
pause
exit /b 1
