<#
  Check-AsusBios.ps1
  Runs at login. Compares the installed BIOS version with the newest one on
  ASUS's support site and shows a Windows notification if an update exists.
  Stays silent when up to date or when offline. Log and state are kept in
  %LOCALAPPDATA%\AsusBiosCheck.

  Network errors (e.g. a VPN still connecting) are retried with increasing
  waits for up to -MaxWaitMinutes. If no check has succeeded for
  -WarnAfterDays, a warning notification points to the log (at most once a day).

  -IncludeBeta     also notify about beta BIOS releases
  -Force           always show a notification (for testing)
  -DelaySeconds    wait before the first attempt (default 0; the login task
                   already waits 30 seconds)
  -MaxWaitMinutes  keep retrying network errors this long (default 15)
  -WarnAfterDays   warn when checks have failed this long (default 7)
#>
param(
    [switch]$IncludeBeta,
    [switch]$Force,
    [int]$DelaySeconds = 0,
    [int]$MaxWaitMinutes = 15,
    [int]$WarnAfterDays = 7
)

$ErrorActionPreference = 'Stop'
$DataDir   = Join-Path $env:LOCALAPPDATA 'AsusBiosCheck'
$LogFile   = Join-Path $DataDir 'Check-AsusBios.log'
$StateFile = Join-Path $DataDir 'Check-AsusBios.state.json'
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
# One line per entry; some exception messages contain line breaks.
function Log($msg) { "$(Get-Date -Format s)  $($msg -replace '\s*\r?\n\s*', ' ')" | Add-Content -Path $LogFile }

# State: FirstRun, LastSuccess, LastWarning (ISO 8601 strings).
function Get-State {
    $state = [pscustomobject]@{ FirstRun = (Get-Date -Format s); LastSuccess = $null; LastWarning = $null }
    if (Test-Path $StateFile) {
        try {
            $saved = Get-Content $StateFile -Raw | ConvertFrom-Json
            # Copy known fields over the defaults, so a file missing any of them still works.
            foreach ($name in 'FirstRun', 'LastSuccess', 'LastWarning') {
                if ($saved.$name) { $state.$name = [string]$saved.$name }
            }
        }
        catch {
            # Keep the unreadable file for inspection, then start fresh.
            $bad = "$StateFile.corrupt"
            Move-Item $StateFile $bad -Force
            Log "WARNING: state file was unreadable ($($_.Exception.Message)); moved to $bad and starting fresh"
        }
    }
    $state
}
function Save-State($s) { $s | ConvertTo-Json | Set-Content $StateFile }

# Errors that mean "the network isn't ready yet" and are worth retrying.
function Test-Transient($err) {
    $ex = $err.Exception
    if ($ex -is [System.Net.WebException]) {
        $resp = $ex.Response
        if (-not $resp) { return $true }                      # DNS, connect, timeout, TLS
        return [int]$resp.StatusCode -ge 500 -or [int]$resp.StatusCode -eq 429
    }
    return $ex -is [System.Net.Sockets.SocketException] -or $ex -is [System.TimeoutException]
}

function Show-Toast($title, $body, $url, $button = 'Open BIOS page') {
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
  <actions><action content="$($esc::Escape($button))" activationType="protocol" arguments="$($esc::Escape($url))"/></actions>
</toast>
"@)
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
        [Windows.UI.Notifications.ToastNotification]::new($xml))
}

$state = Get-State

try {
    # Give the network a moment to come up after login.
    Start-Sleep -Seconds $DelaySeconds

    $board     = (Get-CimInstance Win32_BaseBoard).Product          # motherboard model name
    $installed = (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion     # installed BIOS version

    $api = 'https://www.asus.com/support/api/product.asmx/GetPDBIOS?website=global&cpu=&model=' +
           [Uri]::EscapeDataString($board)

    # Retry network errors with growing waits (30s, 60s, 120s, then 300s) until the deadline.
    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    $wait = 30
    $attempt = 0
    while ($true) {
        $attempt++
        try { $resp = Invoke-RestMethod -Uri $api -UserAgent 'Mozilla/5.0' -TimeoutSec 30; break }
        catch {
            if (-not (Test-Transient $_) -or (Get-Date).AddSeconds($wait) -gt $deadline) { throw }
            Log "attempt $attempt failed ($($_.Exception.Message)); retrying in $wait s"
            Start-Sleep -Seconds $wait
            $wait = [Math]::Min($wait * 2, 300)
        }
    }
    if ($resp.Status -ne 'SUCCESS') { throw "ASUS API returned status '$($resp.Status)' for model '$board'" }

    $files = ($resp.Result.Obj | Where-Object Name -eq 'BIOS').Files
    if (-not $IncludeBeta) { $files = $files | Where-Object IsRelease -eq 1 }
    $latest = $files | Sort-Object { [int]$_.Version } -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No BIOS entries found in ASUS response' }

    $isNewer = [int]$latest.Version -gt [int]$installed
    $beta    = if ($latest.IsRelease -eq 1) { '' } else { ' (beta)' }
    Log "board='$board' installed=$installed latest=$($latest.Version)$beta newer=$isNewer"
    $state.LastSuccess = Get-Date -Format s
    Save-State $state

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

    # Offline now and then is normal; failing for days means something is broken.
    $since = if ($state.LastSuccess) { [datetime]$state.LastSuccess } else { [datetime]$state.FirstRun }
    $warnedRecently = $state.LastWarning -and ([datetime]$state.LastWarning) -gt (Get-Date).AddDays(-1)
    if (((Get-Date) - $since).TotalDays -ge $WarnAfterDays -and -not $warnedRecently) {
        $last = if ($state.LastSuccess) { "Last successful check: $($since.ToString('yyyy-MM-dd'))" } else { 'It has never succeeded.' }
        try {
            Show-Toast 'BIOS update check is failing' "$last`n$($_.Exception.Message)" ([Uri]$LogFile).AbsoluteUri 'Open log'
            $state.LastWarning = Get-Date -Format s
        } catch { Log "ERROR showing warning: $($_.Exception.Message)" }
    }
    Save-State $state
}

# Keep the log small.
if ((Test-Path $LogFile) -and (Get-Content $LogFile).Count -gt 200) {
    Get-Content $LogFile | Select-Object -Last 100 | Set-Content $LogFile
}
