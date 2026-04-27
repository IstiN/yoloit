# Windows Build Symlink Resolution Fix

## Issue
When running `flutter run -d windows`, the build fails with:
```
Get-Item : Could not find item C:\Users\...\AppData.
```

This is in the `super_native_extensions` plugin's cargokit build system, which uses a PowerShell script (`resolve_symlinks.ps1`) that doesn't properly handle paths on Windows.

## Root Cause
The `resolve_symlinks.ps1` script:
- Builds paths using forward slashes (`/`)
- Passes unquoted paths to `Get-Item` command
- Doesn't convert back to Windows backslash format
- Lacks error handling for missing intermediate paths

This causes PowerShell to misinterpret the path (treating spaces as delimiters), resulting in truncated/invalid paths.

## Solution

### Option 1: Auto-patch before build (Recommended)
Run the patch script before building:
```powershell
.\windows\flutter\tools\patch_cargokit.ps1
flutter run -d windows
```

### Option 2: Manual patch (One-time)
Edit `windows\flutter\ephemeral\.plugin_symlinks\super_native_extensions\cargokit\cmake\resolve_symlinks.ps1`

Replace line 25-26:
```powershell
# OLD:
$item = Get-Item $realPath
if ($item.LinkTarget) {
```

With:
```powershell
# NEW:
$windowsPath = $realPath.Replace('/', '\')
$item = Get-Item -LiteralPath $windowsPath -ErrorAction SilentlyContinue
if ($item -and $item.LinkTarget) {
```

### Option 3: Update dependencies
Check if newer versions of `super_native_extensions` or `cargokit` have fixed this:
```bash
flutter pub outdated
flutter pub upgrade super_native_extensions
```

## Why this works
- `-LiteralPath` properly quotes and interprets the path
- Converting to backslashes uses native Windows path format
- `-ErrorAction SilentlyContinue` gracefully skips non-existent intermediate paths
- Null check (`$item -and`) prevents errors on missing items

## Reported Issue
This should be reported to:
- https://github.com/google/app-flutter/issues (super_native_extensions)
- https://github.com/bramp/cargokit/issues (cargokit)
