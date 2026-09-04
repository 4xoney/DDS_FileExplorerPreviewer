@echo off
setlocal

where dotnet.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: The .NET SDK is not installed or is not on PATH.
    echo Install the .NET 8 SDK, then try again.
    exit /b 1
)

pushd "%~dp0.."
dotnet build "DdsThumbnailProvider.sln" --configuration Release
set "BUILD_RESULT=%ERRORLEVEL%"
popd

if not "%BUILD_RESULT%"=="0" exit /b %BUILD_RESULT%

echo.
echo Build complete. Run scripts\install.bat to install the thumbnail provider.
exit /b 0
