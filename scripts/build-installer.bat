@echo off
setlocal EnableExtensions

set "PROJECT_DIR=%~dp0.."
set "ISCC="
set "APP_VERSION=1.0.5"
set "ASSEMBLY_VERSION="

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

for /f "usebackq delims=" %%V in (`powershell.exe -NoProfile -Command "[Reflection.AssemblyName]::GetAssemblyName('%PROJECT_DIR%\bin\x64\Release\net48\DdsThumbnailProvider.dll').Version.ToString()"`) do set "ASSEMBLY_VERSION=%%V"
if not "%ASSEMBLY_VERSION%"=="%APP_VERSION%.0" (
    echo ERROR: Release build version is %ASSEMBLY_VERSION%; installer version is %APP_VERSION%.
    echo Run scripts\build-release.bat before building the installer.
    exit /b 1
)

pushd "%PROJECT_DIR%\installer"
"%ISCC%" "DdsThumbnailProvider.iss"
set "BUILD_RESULT=%ERRORLEVEL%"
popd

if not "%BUILD_RESULT%"=="0" exit /b %BUILD_RESULT%

echo.
echo Installer created:
echo %PROJECT_DIR%\dist\DDS-Thumbnail-Provider-Setup-%APP_VERSION%.exe
exit /b 0
