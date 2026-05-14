<#
.SYNOPSIS
One-time installer — register paperclip start/stop/smoke as Task Scheduler
tasks at RunLevel=Highest, and drop three desktop shortcuts with hotkeys.

After this runs (once, as Administrator), you can:

  - Press  Ctrl+Alt+P   →  paperclip-start  (no UAC)
  - Press  Ctrl+Alt+O   →  paperclip-stop   (no UAC)
  - Press  Ctrl+Alt+H   →  paperclip-smoke  (no UAC)

Or double-click the Desktop shortcuts.

.DESCRIPTION
Why this works: a Scheduled Task created with `-RunLevel Highest` runs
elevated by definition. The desktop .lnk calls `schtasks /Run /TN <name>`,
which only asks the Task Scheduler service to start the task — that
service is already SYSTEM, so there is no per-invocation UAC prompt. This
is the canonical Windows pattern for "one-time consent, every-day shortcut."

To uninstall: scripts\unregister-paperclip-tasks.ps1 (also requires admin).

.NOTES
Run from an elevated PowerShell:
  Start-Process pwsh -Verb RunAs -ArgumentList "-File D:\paperclip\scripts\register-paperclip-tasks.ps1"
#>
[CmdletBinding()]
param(
  [string]$Repo = "D:\paperclip",
  [string]$StartHotkey = "CTRL+ALT+P",
  [string]$StopHotkey  = "CTRL+ALT+O",
  [string]$SmokeHotkey = "CTRL+ALT+H"
)

$ErrorActionPreference = "Stop"

# Log everything to a file so the elevated window's output survives even if
# the window closes before the user can read it.
$logDir = "D:\paperclip\tmp"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logPath = Join-Path $logDir ("register-tasks-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
trap {
  Write-Host "FATAL: $_" -ForegroundColor Red
  Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
  try { Stop-Transcript | Out-Null } catch { }
  # keep window open for 30 s so user can read the error
  Start-Sleep -Seconds 30
  exit 1
}

function Test-Admin {
  $current = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
  Write-Host "ERROR: must run as Administrator." -ForegroundColor Red
  Write-Host "Re-launch:" -ForegroundColor Yellow
  Write-Host "  Start-Process pwsh -Verb RunAs -ArgumentList ""-File $PSCommandPath""" -ForegroundColor Yellow
  exit 1
}

$startScript = Join-Path $Repo "scripts\restart-paperclip.ps1"
$stopScript  = Join-Path $Repo "scripts\stop-paperclip.ps1"
$smokeScript = Join-Path $Repo "scripts\smoke-heartbeat.sh"
foreach ($p in @($startScript, $stopScript, $smokeScript)) {
  if (-not (Test-Path $p)) { throw "missing required script: $p" }
}

# Pick the user the task should run as — the user who launched this admin
# script. $env:USERNAME under "Run as Administrator" still resolves to the
# real interactive account, which is what we want (not SYSTEM).
$user = "$env:USERDOMAIN\$env:USERNAME"

function Register-Task {
  param(
    [string]$Name,
    [string]$Exe,
    [string]$ArgString,    # NOTE: must not be named $Args — that is a reserved automatic variable in PS
    [string]$Description
  )
  $action = New-ScheduledTaskAction -Execute $Exe -Argument $ArgString -WorkingDirectory $Repo
  $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable
  $task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings -Description $Description
  Register-ScheduledTask -TaskName $Name -InputObject $task -Force | Out-Null
  Write-Host "  registered: $Name" -ForegroundColor Green
}

Write-Host "==> [1/3] register Scheduled Tasks" -ForegroundColor Cyan

# We invoke pwsh.exe (PowerShell 7+, already on PATH here) so the modern
# language features in restart-paperclip.ps1 keep working.
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
Write-Host "  PowerShell host: $pwsh"

Register-Task -Name "paperclip-start" `
  -Exe $pwsh `
  -ArgString ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $startScript) `
  -Description "Start the paperclip server (paperclipai run --instance default)."

Register-Task -Name "paperclip-stop" `
  -Exe $pwsh `
  -ArgString ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $stopScript) `
  -Description "Stop the paperclip server tree."

# Smoke test runs the bash script via Git Bash (always present alongside gh).
$bashExe = "C:\Program Files\Git\bin\bash.exe"
if (-not (Test-Path $bashExe)) {
  $bashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source
}
if (-not $bashExe) {
  Write-Host "  WARN: bash.exe not found; paperclip-smoke task will fail until Git for Windows is installed." -ForegroundColor Yellow
  $bashExe = "C:\Program Files\Git\bin\bash.exe"
}
Register-Task -Name "paperclip-smoke" `
  -Exe $bashExe `
  -ArgString ('-c "{0}"' -f ($smokeScript -replace '\\','/')) `
  -Description "Create a smoke issue + invoke heartbeat against Delivery Lead, print result."

Write-Host ""
Write-Host "==> [2/3] create desktop shortcuts with hotkeys" -ForegroundColor Cyan

$desktop = [Environment]::GetFolderPath("Desktop")
function New-Shortcut {
  param(
    [string]$Path,
    [string]$Target,
    [string]$ArgString,     # again, do not name this $Args
    [string]$IconLocation = "",
    [string]$Hotkey = "",
    [string]$Description = ""
  )
  $wsh = New-Object -ComObject WScript.Shell
  $lnk = $wsh.CreateShortcut($Path)
  $lnk.TargetPath = $Target
  $lnk.Arguments = $ArgString
  if ($IconLocation) { $lnk.IconLocation = $IconLocation }
  if ($Description)  { $lnk.Description = $Description }
  if ($Hotkey)       { $lnk.Hotkey = $Hotkey }
  $lnk.WindowStyle = 7  # minimized
  $lnk.Save()
  Write-Host "  $Path ($Hotkey)" -ForegroundColor Green
}

$schtasks = "C:\Windows\System32\schtasks.exe"

New-Shortcut -Path (Join-Path $desktop "Paperclip Start.lnk") `
  -Target $schtasks `
  -ArgString "/Run /TN paperclip-start" `
  -IconLocation "shell32.dll,137" `
  -Hotkey $StartHotkey `
  -Description "Start the paperclip server. Hotkey: $StartHotkey"

New-Shortcut -Path (Join-Path $desktop "Paperclip Stop.lnk") `
  -Target $schtasks `
  -ArgString "/Run /TN paperclip-stop" `
  -IconLocation "shell32.dll,131" `
  -Hotkey $StopHotkey `
  -Description "Stop the paperclip server. Hotkey: $StopHotkey"

New-Shortcut -Path (Join-Path $desktop "Paperclip Smoke.lnk") `
  -Target $schtasks `
  -ArgString "/Run /TN paperclip-smoke" `
  -IconLocation "shell32.dll,167" `
  -Hotkey $SmokeHotkey `
  -Description "Run the heartbeat smoke against djcowork2.0. Hotkey: $SmokeHotkey"

Write-Host ""
Write-Host "==> [3/3] sanity check — list tasks" -ForegroundColor Cyan
schtasks /Query /TN paperclip-start /FO LIST 2>&1 | Select-String -Pattern "TaskName|Status" | ForEach-Object { Write-Host "  $_" }
schtasks /Query /TN paperclip-stop  /FO LIST 2>&1 | Select-String -Pattern "TaskName|Status" | ForEach-Object { Write-Host "  $_" }
schtasks /Query /TN paperclip-smoke /FO LIST 2>&1 | Select-String -Pattern "TaskName|Status" | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Hotkeys (active when at least one Explorer window is open or while" -ForegroundColor White
Write-Host "the shortcuts live on the Desktop):" -ForegroundColor White
Write-Host "  $StartHotkey  →  paperclip-start"
Write-Host "  $StopHotkey  →  paperclip-stop"
Write-Host "  $SmokeHotkey  →  paperclip-smoke"
Write-Host ""
Write-Host "To uninstall:"
Write-Host "  scripts\unregister-paperclip-tasks.ps1  (also requires admin)"

try { Stop-Transcript | Out-Null } catch { }
# brief pause so the user can confirm visually if the window was launched
# from an elevated double-click rather than the parent shell.
Start-Sleep -Seconds 4
