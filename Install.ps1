<#
  Install.ps1
  Installs Check-AsusBios.ps1 for the current user and registers a Task
  Scheduler task that runs it hidden at every login. No admin rights needed.

    Script:  %LOCALAPPDATA%\Programs\AsusBiosCheck\Check-AsusBios.ps1
    Data:    %LOCALAPPDATA%\AsusBiosCheck\  (log and state, created on first run)
    Task:    \AsusBiosCheck  (Task Scheduler Library)

  -Uninstall   remove the task, the script and its data
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$AppName    = 'AsusBiosCheck'
$ProgramDir = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
$DataDir    = Join-Path $env:LOCALAPPDATA $AppName
$Script     = Join-Path $ProgramDir 'Check-AsusBios.ps1'
$User       = "$env:USERDOMAIN\$env:USERNAME"

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $AppName -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $ProgramDir, $DataDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed task '$AppName', $ProgramDir and $DataDir."
    return
}

New-Item -ItemType Directory -Force -Path $ProgramDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Check-AsusBios.ps1') $Script -Force

# conhost --headless runs PowerShell without flashing a console window.
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" `
    -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`""

# Start 30 seconds after login so the desktop and network can settle.
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
$trigger.Delay = 'PT30S'

# Runs as you, only while you're logged in (needed to show notifications), without admin rights.
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $AppName -TaskPath '\' -Force `
    -Description 'Checks ASUS for a newer motherboard BIOS at login and shows a notification if one is available.' `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "Installed $Script"
Write-Host "Task Scheduler task: \$AppName (runs at login)"
Write-Host "Log and state: $DataDir"
Write-Host "Test now with: powershell -ExecutionPolicy Bypass -File `"$Script`" -Force"
