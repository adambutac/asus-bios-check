<#
  Check-AsusBios.ps1
  Shows a Windows notification when ASUS has a newer BIOS for this motherboard.
  Meant to run at login (see Install.ps1). Writes one line per run to
  %LOCALAPPDATA%\AsusBiosCheck\Check-AsusBios.log.

  -IncludeBeta  also consider beta BIOS releases
  -Force        show the notification even when up to date (for testing)
#>
param([switch]$IncludeBeta, [switch]$Force)

$ErrorActionPreference = 'Stop'
$RetryMinutes  = 15   # keep retrying while the network or a VPN comes up
$WarnAfterDays = 7    # warn when no check has succeeded for this long
$DataDir     = "$env:LOCALAPPDATA\AsusBiosCheck"
$LogFile     = "$DataDir\Check-AsusBios.log"
$LastSuccess = "$DataDir\last-success.txt"   # its modified time = last successful check

function Log($msg) {
    "$(Get-Date -Format s)  $($msg -replace '\s+', ' ')" | Add-Content $LogFile
}

function Show-Toast($title, $body, $link) {
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $e = [Security.SecurityElement]   # Escape() makes text safe inside XML
    $xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $xml.LoadXml(@"
<toast activationType="protocol" launch="$($e::Escape($link))">
  <visual><binding template="ToastGeneric">
    <text>$($e::Escape($title))</text>
    <text>$($e::Escape($body))</text>
  </binding></visual>
</toast>
"@)
    # Show it as Windows PowerShell, an app every Windows install has registered.
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}

New-Item -ItemType Directory -Force $DataDir | Out-Null
if (-not (Test-Path $LastSuccess)) { Set-Content $LastSuccess (Get-Date -Format s) }   # first run starts the clock

try {
    $board     = (Get-CimInstance Win32_BaseBoard).Product
    $installed = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion
    $api = 'https://www.asus.com/support/webapi/ProductV2/GetPDBIOS?website=global&cpu=&model=' +
           [Uri]::EscapeDataString($board)

    # Retry once a minute until the request works or time runs out.
    $deadline = (Get-Date).AddMinutes($RetryMinutes)
    while ($true) {
        try { $resp = Invoke-RestMethod $api -UserAgent 'Mozilla/5.0' -TimeoutSec 30; break }
        catch {
            if ((Get-Date) -gt $deadline) { throw }
            Log "retrying in 60 s: $($_.Exception.Message)"
            Start-Sleep 60
        }
    }

    $bios   = ($resp.Result.Obj | Where-Object Name -eq 'BIOS').Files |
              Where-Object { $IncludeBeta -or $_.IsRelease -eq 1 }
    $latest = $bios | Sort-Object { [int]$_.Version } | Select-Object -Last 1
    if (-not $latest) { throw "ASUS returned no BIOS for '$board' (status: $($resp.Status))" }

    Log "board='$board' installed=$installed latest=$($latest.Version)"
    Set-Content $LastSuccess (Get-Date -Format s)

    if ([int]$latest.Version -gt [int]$installed -or $Force) {
        $page  = 'https://www.asus.com/supportonly/' + [Uri]::EscapeDataString($board.ToLower()) + '/helpdesk_bios/'
        $notes = $latest.Description -replace '<[^>]+>|"', ' '   # strip HTML tags and quotes
        Show-Toast "Newest BIOS: $($latest.Version) (you have $installed)" "Released $($latest.ReleaseDate). $notes" $page
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    $since = (Get-Item $LastSuccess).LastWriteTime
    if ($since -lt (Get-Date).AddDays(-$WarnAfterDays)) {
        Show-Toast 'BIOS update check is failing' `
            "No successful check since $($since.ToString('yyyy-MM-dd')). $($_.Exception.Message)" `
            ([Uri]$LogFile).AbsoluteUri
    }
}
