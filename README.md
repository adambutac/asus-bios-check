# asus-bios-check

A small PowerShell script that runs at Windows login and shows a notification when ASUS publishes a newer BIOS for your motherboard.

- Reads the board model and installed BIOS version from WMI. Nothing is hard-coded.
- Queries the JSON API behind the ASUS support site (`/support/api/product.asmx/GetPDBIOS`).
- Ignores beta releases unless you pass `-IncludeBeta`.
- Stays silent when you're up to date or offline. Writes one line per run to `Check-AsusBios.log` next to the installed script.
- Clicking the notification opens the board's BIOS download page.

Requires Windows PowerShell 5.1 (built into Windows 10 and 11) and an ASUS motherboard.

## Install

From PowerShell (no admin needed):

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

This copies the script to `%USERPROFILE%\Scripts` and adds `Check ASUS BIOS.lnk` to your Startup folder (`shell:startup`).

To uninstall:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall
```

## Options

| Switch | Effect |
|---|---|
| `-IncludeBeta` | Also notify about beta BIOS releases |
| `-Force` | Always show a notification, even when you're up to date (for testing) |
| `-DelaySeconds <n>` | Wait before checking so the network is up (default 30) |

To make an option permanent, add it to the end of the shortcut's Target in its Properties.

## Notes

- The ASUS API needs the model name exactly as WMI reports it, as shown by `(Get-CimInstance Win32_BaseBoard).Product`. If a check fails, the reason is in the log.
- This only notifies you. Flash the BIOS from the BIOS itself (EZ Flash 3) with the file on a USB drive. If the release notes mention fTPM, suspend BitLocker first.
