@echo off
setlocal EnableExtensions

set "PROJECT_DIR=%~dp0.."
set "ISCC="

where ISCC.exe >nul 2>&1
if not errorlevel 1 set "ISCC=ISCC.exe"
if not defined ISCC if exist "%LocalAppData%\Programs\Inno Setup 7\ISCC.exe" set "ISCC=%LocalAppData%\Programs\Inno Setup 7\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 7\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 7\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles(x86)%\Inno Setup 7\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 7\ISCC.exe"

if not defined ISCC (
    echo ERROR: Inno Setup 7 is not installed.
    echo Install JRSoftware.InnoSetup.7 with winget, then try again.
    exit /b 1
)

if not exist "%PROJECT_DIR%\bin\x64\Release\net48\DdsThumbnailProvider.dll" (
    echo ERROR: Release build not found. Run scripts\build-release.bat first.
    exit /b 1
)

pushd "%PROJECT_DIR%\installer"
"%ISCC%" "DdsThumbnailProvider.iss"
set "BUILD_RESULT=%ERRORLEVEL%"
popd

if not "%BUILD_RESULT%"=="0" exit /b %BUILD_RESULT%

echo.
echo Installer created:
echo %PROJECT_DIR%\dist\DDS-Thumbnail-Provider-Setup-1.0.3.exe
exit /b 0
