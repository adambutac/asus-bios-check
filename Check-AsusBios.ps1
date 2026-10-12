<#
  Check-AsusBios.ps1
  Runs at login. Compares the installed BIOS version with the newest one on
  ASUS's support site and shows a Windows notification if an update exists.
  Stays silent when up to date or when offline.

  -IncludeBeta   also notify about beta BIOS releases
  -Force         always show a notification (for testing)
  -DelaySeconds  wait before checking (default 30, lets the network come up)
#>
param([switch]$IncludeBeta, [switch]$Force, [int]$DelaySeconds = 30)

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $PSScriptRoot 'Check-AsusBios.log'
function Log($msg) { "$(Get-Date -Format s)  $msg" | Add-Content -Path $LogFile }

function Show-Toast($title, $body, $url) {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    $esc = [Security.SecurityElement]
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml(@"
<toast activationType="protocol" launch="$($esc::Escape($url))">
  <visual><binding template="ToastGeneric">
    <text>$($esc::Escape($title))</text>
    <text>$($esc::Escape($body))</text>
  </binding></visual>
  <actions><action content="Open BIOS page" activationType="protocol" arguments="$($esc::Escape($url))"/></actions>
</toast>
"@)
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
        [Windows.UI.Notifications.ToastNotification]::new($xml))
}

try {
    # Give the network a moment to come up after login.
    Start-Sleep -Seconds $DelaySeconds

    $board     = (Get-CimInstance Win32_BaseBoard).Product          # motherboard model name
    $installed = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion     # installed BIOS version

    $api = 'https://www.asus.com/support/api/product.asmx/GetPDBIOS?website=global&cpu=&model=' +
           [Uri]::EscapeDataString($board)
    $resp = $null
    foreach ($attempt in 1..3) {
        try { $resp = Invoke-RestMethod -Uri $api -UserAgent 'Mozilla/5.0' -TimeoutSec 30; break }
        catch { if ($attempt -eq 3) { throw } ; Start-Sleep -Seconds 60 }
    }
    if ($resp.Status -ne 'SUCCESS') { throw "ASUS API returned status '$($resp.Status)' for model '$board'" }

    $files = ($resp.Result.Obj | Where-Object Name -eq 'BIOS').Files
    if (-not $IncludeBeta) { $files = $files | Where-Object IsRelease -eq 1 }
    $latest = $files | Sort-Object { [int]$_.Version } -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No BIOS entries found in ASUS response' }

    $isNewer = [int]$latest.Version -gt [int]$installed
    $beta    = if ($latest.IsRelease -eq 1) { '' } else { ' (beta)' }
    Log "board='$board' installed=$installed latest=$($latest.Version)$beta newer=$isNewer"

    if ($isNewer -or $Force) {
        $page = 'https://www.asus.com/supportonly/' + [Uri]::EscapeDataString($board.ToLower()) + '/helpdesk_bios/'
        $notes = ($latest.Description -replace '<br\s*/?>', ' ' -replace '<[^>]+>', '' -replace '"', '').Trim()
        if ($notes.Length -gt 160) { $notes = $notes.Substring(0, 157) + '...' }
        $title = if ($isNewer) { "BIOS update available: $($latest.Version)$beta" } else { "BIOS is up to date ($installed)" }
        Show-Toast $title "Installed: $installed  |  Released: $($latest.ReleaseDate)`n$notes" $page
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
}

# Keep the log small.
if ((Test-Path $LogFile) -and (Get-Content $LogFile).Count -gt 200) {
    Get-Content $LogFile | Select-Object -Last 100 | Set-Content $LogFile
}
