<#
  Install.ps1
  Copies Check-AsusBios.ps1 to %USERPROFILE%\Scripts and adds a Startup
  shortcut that runs it hidden at every login. No admin rights needed.

  -Uninstall   remove the Startup shortcut and the installed script
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$dest   = Join-Path $env:USERPROFILE 'Scripts'
$script = Join-Path $dest 'Check-AsusBios.ps1'
$lnk    = Join-Path ([Environment]::GetFolderPath('Startup')) 'Check ASUS BIOS.lnk'

if ($Uninstall) {
    Remove-Item $lnk, $script -ErrorAction SilentlyContinue
    Write-Host "Removed startup shortcut and $script (log file left in $dest)."
    return
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Check-AsusBios.ps1') $script -Force

# conhost --headless runs PowerShell without flashing a window.
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath       = "$env:SystemRoot\System32\conhost.exe"
$s.Arguments        = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
$s.WorkingDirectory = $dest
$s.Description      = 'Checks ASUS for a newer BIOS at login'
$s.Save()

Write-Host "Installed $script"
Write-Host "Startup shortcut: $lnk"
Write-Host "Test now with: powershell -ExecutionPolicy Bypass -File `"$script`" -Force -DelaySeconds 0"
