param(
    [Parameter(Mandatory = $true)]
    [string] $InstallDirectory,

    [switch] $ReleaseLocksOnly
)

$ErrorActionPreference = 'Stop'

$target = [System.IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
$scriptDirectory = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')

if ($ReleaseLocksOnly) {
    # The installed copy is only allowed to inspect the directory containing
    # itself. This still supports a custom Inno Setup installation location.
    if ($target -ne $scriptDirectory) {
        Write-Error "Refusing to inspect a directory outside this installation: $target"
        exit 1
    }
}
else {
    $programFilesRoots = @($env:ProgramFiles, $env:ProgramW6432) |
        Where-Object { $_ } |
        Select-Object -Unique
    $allowedTargets = foreach ($programFilesRoot in $programFilesRoots) {
        [System.IO.Path]::GetFullPath((Join-Path $programFilesRoot 'DDS Thumbnail Provider')).TrimEnd('\')
        [System.IO.Path]::GetFullPath((Join-Path $programFilesRoot 'DdsThumbnailProvider')).TrimEnd('\')
    }

    if ($target -notin $allowedTargets) {
        Write-Error "Refusing to remove unexpected installation directory: $target"
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $target)) {
    exit 0
}

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeInstallationCleanup
{
    public const int ErrorMoreData = 234;

    public enum SurrogateTerminationResult
    {
        Terminated,
        ProcessExited,
        IdentityMismatch,
        Failed
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RmUniqueProcess
    {
        public int ProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    public enum RmAppType
    {
        Unknown = 0,
        MainWindow = 1,
        OtherWindow = 2,
        Service = 3,
        Explorer = 4,
        Console = 5,
        Critical = 1000
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct RmProcessInfo
    {
        public RmUniqueProcess Process;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string AppName;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string ServiceShortName;

        public RmAppType ApplicationType;
        public uint AppStatus;
        public uint TerminalServicesSessionId;

        [MarshalAs(UnmanagedType.Bool)]
        public bool Restartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmStartSession(
        out uint sessionHandle,
        int sessionFlags,
        string sessionKey);

    [DllImport("rstrtmgr.dll")]
    public static extern int RmEndSession(uint sessionHandle);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmRegisterResources(
        uint sessionHandle,
        uint fileCount,
        string[] fileNames,
        uint applicationCount,
        RmUniqueProcess[] applications,
        uint serviceCount,
        string[] serviceNames);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmGetList(
        uint sessionHandle,
        out uint processInfoNeeded,
        ref uint processInfoCount,
        [In, Out] RmProcessInfo[] affectedApplications,
        ref uint rebootReasons);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        int flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint desiredAccess,
        bool inheritHandle,
        int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(
        IntPtr process,
        out System.Runtime.InteropServices.ComTypes.FILETIME creationTime,
        out System.Runtime.InteropServices.ComTypes.FILETIME exitTime,
        out System.Runtime.InteropServices.ComTypes.FILETIME kernelTime,
        out System.Runtime.InteropServices.ComTypes.FILETIME userTime);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool QueryFullProcessImageName(
        IntPtr process,
        int flags,
        StringBuilder imagePath,
        ref int pathLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll")]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    public static SurrogateTerminationResult TerminateVerifiedSurrogate(
        int processId,
        long expectedStartTime,
        string[] allowedImagePaths,
        out string actualImagePath,
        out int nativeError)
    {
        const uint ProcessTerminate = 0x0001;
        const uint ProcessQueryLimitedInformation = 0x1000;
        const uint Synchronize = 0x00100000;
        const int ErrorInvalidParameter = 87;

        actualImagePath = null;
        nativeError = 0;
        IntPtr process = OpenProcess(
            ProcessTerminate | ProcessQueryLimitedInformation | Synchronize,
            false,
            processId);
        if (process == IntPtr.Zero)
        {
            nativeError = Marshal.GetLastWin32Error();
            return nativeError == ErrorInvalidParameter
                ? SurrogateTerminationResult.ProcessExited
                : SurrogateTerminationResult.Failed;
        }

        try
        {
            var path = new StringBuilder(32768);
            int pathLength = path.Capacity;
            if (!QueryFullProcessImageName(process, 0, path, ref pathLength))
            {
                nativeError = Marshal.GetLastWin32Error();
                return SurrogateTerminationResult.Failed;
            }
            actualImagePath = Path.GetFullPath(path.ToString());

            bool allowed = false;
            foreach (string allowedPath in allowedImagePaths)
            {
                if (String.Equals(actualImagePath, allowedPath, StringComparison.OrdinalIgnoreCase))
                {
                    allowed = true;
                    break;
                }
            }
            if (!allowed)
                return SurrogateTerminationResult.IdentityMismatch;

            System.Runtime.InteropServices.ComTypes.FILETIME creationTime;
            System.Runtime.InteropServices.ComTypes.FILETIME exitTime;
            System.Runtime.InteropServices.ComTypes.FILETIME kernelTime;
            System.Runtime.InteropServices.ComTypes.FILETIME userTime;
            if (!GetProcessTimes(
                process,
                out creationTime,
                out exitTime,
                out kernelTime,
                out userTime))
            {
                nativeError = Marshal.GetLastWin32Error();
                return SurrogateTerminationResult.Failed;
            }

            long actualStartTime = ((long)(uint)creationTime.dwHighDateTime << 32) |
                (uint)creationTime.dwLowDateTime;
            if (actualStartTime != expectedStartTime)
                return SurrogateTerminationResult.IdentityMismatch;

            if (!TerminateProcess(process, 0))
            {
                nativeError = Marshal.GetLastWin32Error();
                return SurrogateTerminationResult.Failed;
            }

            WaitForSingleObject(process, 5000);
            return SurrogateTerminationResult.Terminated;
        }
        finally
        {
            CloseHandle(process);
        }
    }
}
'@

function Get-LockingProcesses {
    param([string[]] $Paths)

    if ($Paths.Count -eq 0) {
        return @()
    }

    $sessionHandle = [uint32] 0
    $sessionKey = [Guid]::NewGuid().ToString('N')
    $result = [NativeInstallationCleanup]::RmStartSession([ref] $sessionHandle, 0, $sessionKey)
    if ($result -ne 0) {
        throw "Restart Manager could not start a session (error $result)."
    }

    try {
        $result = [NativeInstallationCleanup]::RmRegisterResources(
            $sessionHandle,
            [uint32] $Paths.Count,
            $Paths,
            0,
            $null,
            0,
            $null)
        if ($result -ne 0) {
            throw "Restart Manager could not inspect the installed files (error $result)."
        }

        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            $needed = [uint32] 0
            $count = [uint32] 0
            $rebootReasons = [uint32] 0
            $result = [NativeInstallationCleanup]::RmGetList(
                $sessionHandle,
                [ref] $needed,
                [ref] $count,
                $null,
                [ref] $rebootReasons)

            if ($result -eq 0) {
                return @()
            }
            if ($result -ne [NativeInstallationCleanup]::ErrorMoreData) {
                throw "Restart Manager could not list processes using the installed files (error $result)."
            }

            $processes = New-Object 'NativeInstallationCleanup+RmProcessInfo[]' $needed
            $count = $needed
            $result = [NativeInstallationCleanup]::RmGetList(
                $sessionHandle,
                [ref] $needed,
                [ref] $count,
                $processes,
                [ref] $rebootReasons)
            if ($result -eq 0) {
                if ($count -eq 0) {
                    return @()
                }
                return @($processes[0..($count - 1)])
            }
            if ($result -ne [NativeInstallationCleanup]::ErrorMoreData) {
                throw "Restart Manager could not list processes using the installed files (error $result)."
            }
        }

        throw 'The processes using the installed files changed too quickly to inspect safely.'
    }
    finally {
        [void] [NativeInstallationCleanup]::RmEndSession($sessionHandle)
    }
}

function Release-ShellExtensionLocks {
    param([string] $Directory)

    $deploymentDirectories = @($Directory)
    $deploymentDirectories += @(
        Get-ChildItem -LiteralPath $Directory -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                (($_.Name -match '^\d+\.\d+\.\d+$') -or
                 ($_.Name -match '^payload-\d+-\d+$'))
            } |
            ForEach-Object { $_.FullName }
    )

    $installedDlls = foreach ($deploymentDirectory in $deploymentDirectories) {
        foreach ($dllName in @('DdsThumbnailProvider.dll', 'Pfim.dll', 'SharpShell.dll')) {
            $dllPath = Join-Path $deploymentDirectory $dllName
            if (Test-Path -LiteralPath $dllPath -PathType Leaf) {
                $dll = Get-Item -LiteralPath $dllPath -Force
                if (-not ($dll.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    [System.IO.Path]::GetFullPath($dllPath)
                }
            }
        }
    }

    if ($installedDlls.Count -eq 0) {
        return
    }

    # The provider is x64-only and Windows hosts isolated thumbnail providers
    # in the 64-bit system DLL surrogate. Do not accept Explorer, Prevhost, a
    # 32-bit surrogate, or an executable merely named dllhost.exe elsewhere.
    $allowedSurrogatePaths = @(
        [System.IO.Path]::GetFullPath((Join-Path $env:windir 'System32\dllhost.exe'))
    )
    foreach ($lockingProcess in @(Get-LockingProcesses -Paths $installedDlls)) {
        $processId = $lockingProcess.Process.ProcessId

        $restartManagerStartTime =
            (([int64] $lockingProcess.Process.ProcessStartTime.dwHighDateTime -band 0xFFFFFFFFL) -shl 32) -bor
            ([int64] $lockingProcess.Process.ProcessStartTime.dwLowDateTime -band 0xFFFFFFFFL)
        $actualImagePath = $null
        $nativeError = 0
        $terminationResult = [NativeInstallationCleanup]::TerminateVerifiedSurrogate(
            $processId,
            $restartManagerStartTime,
            $allowedSurrogatePaths,
            [ref] $actualImagePath,
            [ref] $nativeError)

        if ($terminationResult -eq [NativeInstallationCleanup+SurrogateTerminationResult]::IdentityMismatch) {
            $description = if ($actualImagePath) { $actualImagePath } else { 'a reused process ID' }
            Write-Warning "Leaving unrelated process '$description' (PID $processId) running."
        }
        elseif ($terminationResult -eq [NativeInstallationCleanup+SurrogateTerminationResult]::Failed) {
            Write-Warning "Could not release verified thumbnail host PID $processId (Windows error $nativeError)."
        }
    }
}

try {
    Release-ShellExtensionLocks -Directory $target
}
catch {
    # Keep uninstall reliable if Restart Manager is unavailable. The normal
    # removal path below will queue any remaining mapped files for next reboot.
    Write-Warning $_.Exception.Message
}

if ($ReleaseLocksOnly) {
    exit 0
}

$moveFileDelayUntilReboot = 0x4
$failures = 0
$preservedItems = 0
$ownedRootFileNames = @(
    'DdsThumbnailProvider.dll',
    'Pfim.dll',
    'SharpShell.dll',
    'ServerRegistrationManager.exe',
    'remove-installation.ps1',
    'README.md',
    'THIRD-PARTY-NOTICES.md'
)
$ownedPayloadFileNames = @(
    'DdsThumbnailProvider.dll',
    'Pfim.dll',
    'SharpShell.dll',
    'ServerRegistrationManager.exe'
)

$deploymentDirectories = @(
    Get-ChildItem -LiteralPath $target -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (($_.Name -match '^\d+\.\d+\.\d+$') -or
             ($_.Name -match '^payload-\d+-\d+$'))
        }
)

$ownedFiles = @(
    Get-ChildItem -LiteralPath $target -Force -File -ErrorAction SilentlyContinue |
        Where-Object {
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            ($_.Name -in $ownedRootFileNames)
        }
)
foreach ($deploymentDirectory in $deploymentDirectories) {
    $ownedFiles += @(
        Get-ChildItem -LiteralPath $deploymentDirectory.FullName -Force -File -ErrorAction SilentlyContinue |
            Where-Object {
                -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                ($_.Name -in $ownedPayloadFileNames)
            }
    )
}

$knownRootPaths = @($ownedFiles | ForEach-Object { $_.FullName })
$knownRootPaths += @($deploymentDirectories | ForEach-Object { $_.FullName })
foreach ($item in @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)) {
    if ($item.FullName -notin $knownRootPaths) {
        Write-Warning "Preserving unrecognized item: $($item.FullName)"
        $preservedItems++
    }
}

foreach ($deploymentDirectory in $deploymentDirectories) {
    $knownPayloadPaths = @(
        $ownedFiles |
            Where-Object { $_.DirectoryName -eq $deploymentDirectory.FullName } |
            ForEach-Object { $_.FullName }
    )
    foreach ($item in @(Get-ChildItem -LiteralPath $deploymentDirectory.FullName -Force -ErrorAction SilentlyContinue)) {
        if ($item.FullName -notin $knownPayloadPaths) {
            Write-Warning "Preserving unrecognized item: $($item.FullName)"
            $preservedItems++
        }
    }
}

foreach ($file in $ownedFiles) {
    try {
        Remove-Item -LiteralPath $file.FullName -Force
    }
    catch {
        if (-not [NativeInstallationCleanup]::MoveFileEx($file.FullName, $null, $moveFileDelayUntilReboot)) {
            Write-Warning "Could not remove or schedule owned file: $($file.FullName)"
            $failures++
        }
    }
}

foreach ($directory in $deploymentDirectories) {
    try {
        Remove-Item -LiteralPath $directory.FullName -Force
    }
    catch {
        # Scheduling a directory never removes its contents; it succeeds at
        # reboot only if removal of the explicitly owned files leaves it empty.
        if (($preservedItems -eq 0) -and
            (-not [NativeInstallationCleanup]::MoveFileEx($directory.FullName, $null, $moveFileDelayUntilReboot))) {
            Write-Warning "Could not remove or schedule owned directory: $($directory.FullName)"
            $failures++
        }
    }
}

try {
    Remove-Item -LiteralPath $target -Force
}
catch {
    if (($preservedItems -eq 0) -and
        (-not [NativeInstallationCleanup]::MoveFileEx($target, $null, $moveFileDelayUntilReboot))) {
        Write-Warning "Could not remove or schedule installation directory: $target"
        $failures++
    }
}

if (($failures -ne 0) -or ($preservedItems -ne 0)) {
    exit 1
}
