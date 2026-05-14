<#
.SYNOPSIS
Remove the three paperclip-* Scheduled Tasks and the desktop shortcuts
installed by register-paperclip-tasks.ps1.

.NOTES
Run from an elevated PowerShell.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

function Test-Admin {
  $current = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
  Write-Host "ERROR: must run as Administrator." -ForegroundColor Red
  exit 1
}

foreach ($name in @("paperclip-start","paperclip-stop","paperclip-smoke")) {
  try {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
    Write-Host "removed task: $name" -ForegroundColor Green
  } catch {
    Write-Host "task $name: $($_.Exception.Message)" -ForegroundColor DarkYellow
  }
}

$desktop = [Environment]::GetFolderPath("Desktop")
foreach ($lnk in @("Paperclip Start.lnk","Paperclip Stop.lnk","Paperclip Smoke.lnk")) {
  $p = Join-Path $desktop $lnk
  if (Test-Path $p) {
    Remove-Item -LiteralPath $p -Force
    Write-Host "removed shortcut: $p" -ForegroundColor Green
  }
}

Write-Host "done." -ForegroundColor Green
