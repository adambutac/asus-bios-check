# asus-bios-check

A small PowerShell script that runs at Windows login and shows a notification when ASUS publishes a newer BIOS for your motherboard.

- Reads the board model and installed BIOS version from WMI. Nothing is hard-coded.
- Queries the JSON API behind the ASUS support site (`/support/api/product.asmx/GetPDBIOS`).
- Ignores beta releases unless you pass `-IncludeBeta`.
- Stays silent when you're up to date or offline. Writes one line per run to `%LOCALAPPDATA%\AsusBiosCheck\Check-AsusBios.log`.
- Clicking the notification opens the board's BIOS download page.

## When the check fails

- **Network errors** (no connection, DNS failure, timeout, or ASUS server errors) are retried with waits of 30 s, 1 min, 2 min, then every 5 min, for up to 15 minutes. This covers VPNs that are slow to connect after login.
- **Other errors**, such as ASUS rejecting the request or an unknown model, aren't retried, because retrying won't fix them.
- A failed check is logged and the script tries again at the next login. If no check has succeeded for 7 days, a **"BIOS update check is failing"** notification opens the log. It shows at most once a day. Success times are stored in `Check-AsusBios.state.json` in the same folder. If that file is ever unreadable, it's renamed to `.corrupt`, a warning is logged, and tracking starts fresh.

Requires Windows PowerShell 5.1 (built into Windows 10 and 11) and an ASUS motherboard.

## Install

From PowerShell (no admin needed):

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

This installs for the current user only, following the usual Windows locations for per-user apps:

| What | Where |
|---|---|
| Script | `%LOCALAPPDATA%\Programs\AsusBiosCheck\Check-AsusBios.ps1` |
| Log and state | `%LOCALAPPDATA%\AsusBiosCheck\` (created on first run) |
| Login task | `AsusBiosCheck` in Task Scheduler, starting 30 seconds after login |

The task runs as you, without admin rights, using `conhost --headless` so no window appears. In Task Scheduler you can see when it last ran and its result, or disable it.

Run `Install.ps1` again after editing the script to update the installed copy.

To uninstall (removes the task, the script and its log and state):

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall
```

## Options

| Switch | Effect |
|---|---|
| `-IncludeBeta` | Also notify about beta BIOS releases |
| `-Force` | Always show a notification, even when you're up to date (for testing) |
| `-DelaySeconds <n>` | Wait before the first attempt (default 0; the login task already waits 30 s) |
| `-MaxWaitMinutes <n>` | Keep retrying network errors for this long (default 15) |
| `-WarnAfterDays <n>` | Warn when no check has succeeded for this long (default 7) |

To make an option permanent, open the `AsusBiosCheck` task in Task Scheduler, go to **Actions → Edit**, and add it to the end of **Add arguments**.

## Notes

- The ASUS API needs the model name exactly as WMI reports it, as shown by `(Get-CimInstance Win32_BaseBoard).Product`. If a check fails, the reason is in the log.
- This only notifies you. Flash the BIOS from the BIOS itself (EZ Flash 3) with the file on a USB drive. If the release notes mention fTPM, suspend BitLocker first.
