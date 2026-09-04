#define AppName "DDS Thumbnail Provider"
#define AppVersion "1.0.4"
#define AppPublisher "4xon"
#define ProviderClsid "{4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E}"
#define ThumbnailHandlerIid "{e357fccd-a995-4576-b01f-234630154e96}"

[Setup]
AppId={{96E8CF04-25B4-4A21-8FE9-91059714C2CD}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/4xoney/DDS_FileExplorerPreviewer
AppSupportURL=https://github.com/4xoney/DDS_FileExplorerPreviewer/issues
AppUpdatesURL=https://github.com/4xoney/DDS_FileExplorerPreviewer/releases
AppComments=Displays DDS image thumbnails in Windows File Explorer.
DefaultDirName={autopf}\DDS Thumbnail Provider
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.18362
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=4
OutputDir=..\dist
OutputBaseFilename=DDS-Thumbnail-Provider-Setup-{#AppVersion}
SetupLogging=yes
Uninstallable=yes
UninstallDisplayName={#AppName}
ChangesAssociations=yes
RestartIfNeededByRun=no
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}.0
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}

[Files]
; Keep each release in its own directory. Explorer's isolated thumbnail host may
; still have the previous DLL mapped after it is unregistered, so overwriting a
; shared path during an upgrade is neither necessary nor safe.
Source: "..\bin\x64\Release\net48\DdsThumbnailProvider.dll"; DestDir: "{app}\{#AppVersion}"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\bin\x64\Release\net48\Pfim.dll"; DestDir: "{app}\{#AppVersion}"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\bin\x64\Release\net48\SharpShell.dll"; DestDir: "{app}\{#AppVersion}"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\bin\x64\Release\net48\ServerRegistrationManager.exe"; DestDir: "{app}"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[UninstallRun]
Filename: "{app}\ServerRegistrationManager.exe"; Parameters: "uninstall ""{app}\{#AppVersion}\DdsThumbnailProvider.dll"" -os64"; WorkingDir: "{app}"; Flags: runhidden waituntilterminated; RunOnceId: "UnregisterDdsThumbnailProvider"

[Code]
const
  DotNet48Release = 528040;
  ProviderClsid = '{#ProviderClsid}';
  ThumbnailHandlerIid = '{#ThumbnailHandlerIid}';

function IsDotNet48Installed: Boolean;
var
  ReleaseValue: Cardinal;
begin
  Result := RegQueryDWordValue(
    HKEY_LOCAL_MACHINE,
    'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full',
    'Release',
    ReleaseValue) and (ReleaseValue >= DotNet48Release);
end;

function InitializeSetup: Boolean;
begin
  Result := IsDotNet48Installed;
  if not Result then
    MsgBox(
      '.NET Framework 4.8 or newer is required. Install current Windows updates, then run this installer again.',
      mbError,
      MB_OK);
end;

function UnregisterExistingProvider: Boolean;
var
  CodeBase: String;
  ResultCode: Integer;
  RegistrationManager: String;
  ProviderDll: String;
begin
  Result := True;
  RegistrationManager := ExpandConstant('{app}\ServerRegistrationManager.exe');

  { Read the currently registered CodeBase so upgrades work across both the old
    shared layout and the new versioned layout. }
  if RegQueryStringValue(
    HKEY_LOCAL_MACHINE_64,
    'SOFTWARE\Classes\CLSID\' + ProviderClsid + '\InprocServer32',
    'CodeBase',
    CodeBase) then
  begin
    ProviderDll := CodeBase;
    if Pos('file:///', Lowercase(ProviderDll)) = 1 then
      Delete(ProviderDll, 1, 8);
    StringChangeEx(ProviderDll, '/', '\', True);
    StringChangeEx(ProviderDll, '%20', ' ', True);
  end
  else
    ProviderDll := ExpandConstant('{app}\DdsThumbnailProvider.dll');

  { The first installer stored the registration tool beside the provider. }
  if not FileExists(RegistrationManager) then
    RegistrationManager := ExtractFileDir(ProviderDll) + '\ServerRegistrationManager.exe';

  if FileExists(RegistrationManager) and FileExists(ProviderDll) then
    Result := Exec(
      RegistrationManager,
      'uninstall "' + ProviderDll + '" -os64',
      ExpandConstant('{app}'),
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode) and (ResultCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not UnregisterExistingProvider then
  begin
    Result := 'The existing DDS thumbnail provider could not be unregistered. Close File Explorer windows and try again.';
    Exit;
  end;
end;

function RegisterProvider: Boolean;
var
  ResultCode: Integer;
  RegistrationManager: String;
  ProviderDll: String;
  RegisteredClsid: String;
  RegistryPath: String;
begin
  RegistrationManager := ExpandConstant('{app}\ServerRegistrationManager.exe');
  ProviderDll := ExpandConstant('{app}\{#AppVersion}\DdsThumbnailProvider.dll');
  Result := Exec(
    RegistrationManager,
    'install "' + ProviderDll + '" -codebase -os64',
    ExpandConstant('{app}'),
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode) and (ResultCode = 0);

  if Result then
  begin
    RegistryPath := 'SOFTWARE\Classes\.dds\ShellEx\' + ThumbnailHandlerIid;
    Result := RegQueryStringValue(
      HKEY_LOCAL_MACHINE_64,
      RegistryPath,
      '',
      RegisteredClsid) and (CompareText(RegisteredClsid, ProviderClsid) = 0);

    { Thumbnail handlers are isolated by default. Explicitly remove the legacy
      opt-out value in case an older/debug install left it enabled. }
    if Result then
      RegDeleteValue(
        HKEY_LOCAL_MACHINE_64,
        'SOFTWARE\Classes\CLSID\' + ProviderClsid,
        'DisableProcessIsolation');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    if not RegisterProvider then
    begin
      Exec(
        ExpandConstant('{app}\ServerRegistrationManager.exe'),
        'uninstall "' + ExpandConstant('{app}\{#AppVersion}\DdsThumbnailProvider.dll') + '" -os64',
        ExpandConstant('{app}'),
        SW_HIDE,
        ewWaitUntilTerminated,
        ResultCode);
      RaiseException('The DDS thumbnail provider could not be registered. No shell extension was installed.');
    end;
  end;
end;
