# Patch script to fix cargokit symlink resolution on Windows
# This addresses: Get-Item : Could not find item error during build

$symlinkScript = "$PSScriptRoot\..\ephemeral\.plugin_symlinks\super_native_extensions\cargokit\cmake\resolve_symlinks.ps1"

if (Test-Path $symlinkScript) {
    Write-Host "Patching cargokit resolve_symlinks.ps1..."

    $content = Get-Content $symlinkScript -Raw

    # Replace the problematic Get-Item call with fixed version
    $oldPattern = @"
`$item = Get-Item `$realPath
        if (`$item.LinkTarget) {
"@

    $newPattern = @"
`$windowsPath = `$realPath.Replace('/', '\')
        `$item = Get-Item -LiteralPath `$windowsPath -ErrorAction SilentlyContinue
        if (`$item -and `$item.LinkTarget) {
"@

    if ($content -like "*Get-Item `$realPath*") {
        $content = $content -replace [regex]::Escape($oldPattern), $newPattern
        Set-Content $symlinkScript $content -Encoding UTF8
        Write-Host "✓ Patched resolve_symlinks.ps1"
    } else {
        Write-Host "✓ resolve_symlinks.ps1 already patched or pattern not found"
    }
} else {
    Write-Host "Note: cargokit plugin not yet loaded (ephemeral directory not ready)"
}
