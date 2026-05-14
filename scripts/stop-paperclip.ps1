<#
.SYNOPSIS
Stop the running paperclip server tree by command-line marker, leaving no
orphans behind. No re-launch.

.NOTES
Called via Task Scheduler `paperclip-stop` (registered by
register-paperclip-tasks.ps1) — runs at Highest privilege so it can kill
processes started under the same user without UAC prompts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$root = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match "paperclipai\s+run\s+--instance"
} | Sort-Object -Property CreationDate | Select-Object -First 1

if (-not $root) {
  Write-Host "no paperclip process found — already stopped"
  exit 0
}

Write-Host "root pid: $($root.ProcessId)"
$tree = @($root.ProcessId)
do {
  $desc = Get-CimInstance Win32_Process | Where-Object {
    $_.ParentProcessId -in $tree -and $_.ProcessId -notin $tree
  }
  if ($desc) { $tree += $desc.ProcessId }
} while ($desc)

Write-Host "killing pids: $($tree -join ', ')"
foreach ($pid_ in $tree) {
  try { Stop-Process -Id $pid_ -Force -ErrorAction Stop }
  catch { Write-Host "  skip $pid_ ($($_.Exception.Message))" -ForegroundColor DarkYellow }
}
Write-Host "stopped." -ForegroundColor Green
