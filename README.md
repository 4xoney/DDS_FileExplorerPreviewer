# DDS Thumbnail Provider

A small, install-once Windows Explorer shell extension that displays image thumbnails for `.dds` files. It has no window, tray icon, service, or background process. Explorer loads the provider only when it needs a DDS thumbnail and keeps using the user's existing default application when a DDS file is opened.

Created and maintained by **4xon**.

## Download

Download the latest installer from [GitHub Releases](https://github.com/4xoney/DDS_FileExplorerPreviewer/releases/latest). The source code does not need to be downloaded to install the thumbnail provider.

## Requirements

- 64-bit Windows 10 or Windows 11
- .NET Framework 4.8 runtime (included with current Windows versions)
- To build: .NET 8 SDK (the project restores its .NET Framework reference assemblies)

## Build and install

1. Run `scripts\build-release.bat`.
2. Run `scripts\install.bat`. It requests administrator permission, copies the release to a new deployment directory under `%ProgramFiles%\DDS Thumbnail Provider`, and registers the x64 shell extension.
3. Open a folder containing `.dds` files and select Medium, Large, or Extra large icons.

The build output is under `bin\x64\Release\net48` and contains the provider plus its runtime dependencies and SharpShell's registration utility.

## Single-file installer

For distribution, run `scripts\build-installer.bat` after building the Release configuration. It requires Inno Setup 7 and creates one distributable file:

```text
dist\DDS-Thumbnail-Provider-Setup-1.0.5.exe
```

The installer provides a standard elevated Windows wizard, upgrades an existing installation, registers the provider directly for `.dds`, notifies Explorer of the association change, and adds a normal Programs and Features uninstall entry. It does not terminate or restart the Windows shell. Each release uses a separate payload directory, so an upgraded shell-extension DLL is never overwritten while Windows still has it mapped. During uninstall, the provider is unregistered and only the disposable Windows thumbnail host using its DLLs is stopped, allowing the complete installation directory to be removed immediately. Recipients need only the generated `.exe`; they do not need the source tree, build tools, batch scripts, or dependency files separately.

## Uninstall

Run `scripts\uninstall.bat`. It unregisters the extension, releases its DLLs from the isolated Windows thumbnail host, and removes the installation directory. `explorer.exe` is never terminated or restarted. Cleanup is restricted to files owned by this application; unrecognized files, directories, and reparse points are preserved and reported. If an unrelated process has loaded one of the application's private DLL copies, that process is left running and the owned DLL is scheduled for removal at the next restart.

If Explorer continues showing an old or generic thumbnail during development, run `scripts\clear-thumbnail-cache.bat`. It requests a refresh without stopping Explorer; sign out and back in if Windows keeps an old cache file locked.

## Supported images and safety limits

Pfim supplies DDS decoding, including common uncompressed, BC/DXT, DX10, grayscale, and floating-point formats. The provider converts Pfim's decoded formats to a 32-bit ARGB bitmap and preserves the original aspect ratio.

To protect Explorer from malformed files that claim extreme dimensions, the provider rejects images over 32,768 pixels on either axis, over 64 megapixels, or over 256 MiB encoded. Unsupported or corrupt DDS files fall back to Explorer's normal generic icon.

## Project layout

```text
src/
  DdsThumbnailHandler.cs    Explorer/SharpShell entry point
  DdsHeaderValidator.cs     Lightweight DDS and allocation-safety checks
  DdsStreamBuffer.cs        Explorer COM stream compatibility layer
  DdsBitmapConverter.cs     Pfim pixels to resized ARGB Bitmap
scripts/
  build-release.bat
  build-installer.bat
  install.bat
  uninstall.bat
  remove-installation.ps1
  clear-thumbnail-cache.bat
tests/
  DdsThumbnailProvider.Tests/  Dependency-free smoke-test executable
installer/
  DdsThumbnailProvider.iss     Single-file installer definition
```

## Development check

The solution build also builds a small test executable. Run it with:

```powershell
dotnet run --project tests\DdsThumbnailProvider.Tests -c Release
```

During development, rebuild and rerun `install.bat`. The script unregisters an existing copy and installs the new build to a fresh deployment directory, avoiding writes to any DLL that Windows still has mapped.

To run the complete handler path against a real texture tree, pass its directory to the test executable:

```powershell
dotnet run --project tests\DdsThumbnailProvider.Tests -c Release -- "C:\path\to\textures"
```

## Notes

- The provider is x64-only because modern Windows Explorer is 64-bit.
- This is a thumbnail provider for Explorer icon views. It intentionally does not add a full Preview Pane handler.
- Shell extensions run inside Explorer. Only install builds you trust, and keep the installed DLLs in their stable Program Files directory.

## Support development

If this utility is useful to you, donations are optional and appreciated:

[Buy 4xon a coffee](https://buymeacoffee.com/4xon)

## License

DDS Thumbnail Provider is copyright © 2026 4xon and released under the [MIT License](LICENSE). Third-party components retain their own copyrights and licenses; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
