param(
    [Parameter(Mandatory = $true)]
    [string] $InstallDirectory
)

$ErrorActionPreference = 'Stop'

$target = [System.IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
$allowedTargets = @(
    [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'DDS Thumbnail Provider')).TrimEnd('\'),
    [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'DdsThumbnailProvider')).TrimEnd('\')
)

if ($target -notin $allowedTargets) {
    Write-Error "Refusing to remove unexpected installation directory: $target"
    exit 1
}

if (-not (Test-Path -LiteralPath $target)) {
    exit 0
}

try {
    Remove-Item -LiteralPath $target -Recurse -Force
    exit 0
}
catch {
    # A thumbnail host can keep an already-loaded image mapped after COM
    # unregistration. Queue only the remaining, validated installation files
    # for deletion at reboot; Explorer itself is never stopped.
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

internal static class PendingFileDeletion
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        int flags);
}
'@

$moveFileDelayUntilReboot = 0x4
$failures = 0

$files = Get-ChildItem -LiteralPath $target -Recurse -Force -File -ErrorAction SilentlyContinue
foreach ($file in $files) {
    if (-not [PendingFileDeletion]::MoveFileEx($file.FullName, $null, $moveFileDelayUntilReboot)) {
        Write-Warning "Could not schedule file deletion: $($file.FullName)"
        $failures++
    }
}

$directories = Get-ChildItem -LiteralPath $target -Recurse -Force -Directory -ErrorAction SilentlyContinue |
    Sort-Object { $_.FullName.Length } -Descending
foreach ($directory in $directories) {
    if (-not [PendingFileDeletion]::MoveFileEx($directory.FullName, $null, $moveFileDelayUntilReboot)) {
        Write-Warning "Could not schedule directory deletion: $($directory.FullName)"
        $failures++
    }
}

if (-not [PendingFileDeletion]::MoveFileEx($target, $null, $moveFileDelayUntilReboot)) {
    Write-Warning "Could not schedule installation directory deletion: $target"
    $failures++
}

if ($failures -ne 0) {
    exit 1
}
