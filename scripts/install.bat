@echo off
setlocal EnableExtensions EnableDelayedExpansion

fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SOURCE_DIR=%~dp0..\bin\x64\Release\net48"
set "INSTALL_DIR=%ProgramFiles%\DDS Thumbnail Provider"
set "PAYLOAD_DIR=%INSTALL_DIR%\payload-%RANDOM%-%RANDOM%"
set "PROVIDER_DLL=%PAYLOAD_DIR%\DdsThumbnailProvider.dll"
set "SRM=%INSTALL_DIR%\ServerRegistrationManager.exe"
set "OLD_PROVIDER="
set "OLD_SRM="
set "APP_VERSION=1.0.4"
set "ASSEMBLY_VERSION="

if not exist "%SOURCE_DIR%\DdsThumbnailProvider.dll" (
    echo ERROR: Release build not found.
    echo Run scripts\build-release.bat first.
    pause
    exit /b 1
)

for /f "usebackq delims=" %%V in (`powershell.exe -NoProfile -Command "[Reflection.AssemblyName]::GetAssemblyName('%SOURCE_DIR%\DdsThumbnailProvider.dll').Version.ToString()"`) do set "ASSEMBLY_VERSION=%%V"
if not "%ASSEMBLY_VERSION%"=="%APP_VERSION%.0" (
    echo ERROR: Release build version is %ASSEMBLY_VERSION%; install script version is %APP_VERSION%.
    echo Run scripts\build-release.bat first.
    pause
    exit /b 1
)

for /f "tokens=2,*" %%A in ('reg.exe query "HKLM\SOFTWARE\Classes\CLSID\{4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E}\InprocServer32" /v CodeBase 2^>nul ^| findstr.exe /I /C:"CodeBase"') do set "OLD_PROVIDER=%%B"
if defined OLD_PROVIDER (
    set "OLD_PROVIDER=!OLD_PROVIDER:file:///=!"
    set "OLD_PROVIDER=!OLD_PROVIDER:/=\!"
    set "OLD_PROVIDER=!OLD_PROVIDER:%%20= !"

    if exist "%SRM%" set "OLD_SRM=%SRM%"
    if not defined OLD_SRM for %%I in ("!OLD_PROVIDER!") do if exist "%%~dpIServerRegistrationManager.exe" set "OLD_SRM=%%~dpIServerRegistrationManager.exe"

    if defined OLD_SRM if exist "!OLD_PROVIDER!" (
        "!OLD_SRM!" uninstall "!OLD_PROVIDER!" -os64 >nul 2>&1
        if errorlevel 1 (
            echo ERROR: The existing DDS thumbnail provider could not be unregistered.
            pause
            exit /b 1
        )
    )
)

if not exist "%PAYLOAD_DIR%" mkdir "%PAYLOAD_DIR%"
copy /Y "%SOURCE_DIR%\DdsThumbnailProvider.dll" "%PAYLOAD_DIR%\" >nul
if errorlevel 1 goto :failed
copy /Y "%SOURCE_DIR%\Pfim.dll" "%PAYLOAD_DIR%\" >nul
if errorlevel 1 goto :failed
copy /Y "%SOURCE_DIR%\SharpShell.dll" "%PAYLOAD_DIR%\" >nul
if errorlevel 1 goto :failed
copy /Y "%SOURCE_DIR%\ServerRegistrationManager.exe" "%INSTALL_DIR%\" >nul
if errorlevel 1 goto :failed

"%SRM%" install "%PROVIDER_DLL%" -codebase -os64
if errorlevel 1 goto :failed

reg.exe query "HKLM\SOFTWARE\Classes\.dds\ShellEx\{e357fccd-a995-4576-b01f-234630154e96}" /ve 2>nul | findstr.exe /I /C:"{4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E}" >nul
if errorlevel 1 (
    echo ERROR: The direct .dds thumbnail association was not registered.
    goto :failed
)

reg.exe delete "HKLM\SOFTWARE\Classes\CLSID\{4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E}" /v DisableProcessIsolation /f >nul 2>&1

echo.
echo DDS thumbnail provider %APP_VERSION% installed successfully.
echo Open a folder containing DDS files and choose a large-icon view.
pause
exit /b 0

:failed
if exist "%PROVIDER_DLL%" if exist "%SRM%" "%SRM%" uninstall "%PROVIDER_DLL%" -os64 >nul 2>&1
if exist "%PAYLOAD_DIR%" rmdir /S /Q "%PAYLOAD_DIR%" >nul 2>&1
echo.
echo ERROR: Installation failed. Explorer was not stopped or restarted.
pause
exit /b 1
