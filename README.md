# asus-bios-check

A small PowerShell script that runs at Windows login and shows a notification when ASUS publishes a newer BIOS for your motherboard. Clicking the notification opens the board's BIOS download page.

- Reads the board model and installed BIOS version from Windows. Nothing is hard-coded.
- Asks the JSON API behind the ASUS support site for the newest BIOS.
- Ignores betas unless you install with `-IncludeBeta`.
- Stays silent when you're up to date. Writes one line per run to the log.

Requires Windows PowerShell 5.1 (built into Windows 10 and 11) and an ASUS desktop motherboard.

## Install

From PowerShell (no admin needed):

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1               # stable releases only
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -IncludeBeta  # also betas
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall    # remove everything
```

It installs for the current user only, in the usual Windows locations for per-user apps:

| What | Where |
|---|---|
| Script | `%LOCALAPPDATA%\Programs\AsusBiosCheck\Check-AsusBios.ps1` |
| Log | `%LOCALAPPDATA%\AsusBiosCheck\Check-AsusBios.log` |
| Last successful check | `%LOCALAPPDATA%\AsusBiosCheck\last-success.txt` (its modified time) |
| Login task | `AsusBiosCheck` in Task Scheduler |

The task starts 30 seconds after you log in. It runs as you, without admin rights, using `conhost --headless` so no window appears. With Task Scheduler's defaults, it won't start while running on battery power.

To change the script or switch `-IncludeBeta` on or off, run `Install.ps1` again.

To test, run the installed script with `-Force`. It shows the notification even when you're up to date.

## When the check fails

- A failed request is retried once a minute for up to 15 minutes, which covers VPNs that are slow to connect after login.
- If it still fails, the error is logged and it tries again at the next login.
- If no check has succeeded for 7 days, each login shows a **"BIOS update check is failing"** notification. Clicking it opens the log.

Both time limits are settings at the top of `Check-AsusBios.ps1`.

## Notes

- This only notifies you. Flash the BIOS from the BIOS itself (EZ Flash 3) with the file on a USB drive. If the release notes mention fTPM, suspend BitLocker first.
- BIOS versions are compared as whole numbers, which is how ASUS numbers desktop boards. Laptop-style versions aren't supported.
