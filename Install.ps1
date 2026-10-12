<#
  Install.ps1
  Installs Check-AsusBios.ps1 for the current user and runs it 30 seconds
  after each login with Task Scheduler. No admin rights needed.

    Script:  %LOCALAPPDATA%\Programs\AsusBiosCheck\Check-AsusBios.ps1
    Data:    %LOCALAPPDATA%\AsusBiosCheck\
    Task:    AsusBiosCheck

  -IncludeBeta  also notify about beta BIOS releases
  -Uninstall    remove the task, the script and its data
#>
param([switch]$IncludeBeta, [switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$ProgramDir = "$env:LOCALAPPDATA\Programs\AsusBiosCheck"
$Script     = "$ProgramDir\Check-AsusBios.ps1"

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName AsusBiosCheck -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $ProgramDir, "$env:LOCALAPPDATA\AsusBiosCheck" -Recurse -ErrorAction SilentlyContinue
    Write-Host 'Uninstalled.'
    return
}

New-Item -ItemType Directory -Force $ProgramDir | Out-Null
Copy-Item "$PSScriptRoot\Check-AsusBios.ps1" $Script -Force

# conhost --headless runs PowerShell without flashing a window.
$arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`""
if ($IncludeBeta) { $arguments += ' -IncludeBeta' }

$action  = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = 'PT30S'   # 30 seconds
Register-ScheduledTask -TaskName AsusBiosCheck -Action $action -Trigger $trigger -Force | Out-Null

Write-Host "Installed. Test with: powershell -ExecutionPolicy Bypass -File `"$Script`" -Force"
