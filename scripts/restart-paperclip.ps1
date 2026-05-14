<#
.SYNOPSIS
Stop the running paperclip server tree and start a fresh one.

.DESCRIPTION
Useful after enabling Windows long-path support, changing plugin source, or
fixing the plugin-loader path bug. Locates paperclip's process tree by the
command-line marker `paperclipai run --instance default`, kills the whole
tree, then re-launches via pnpm and waits for /api/health = 200.
#>
[CmdletBinding()]
param(
  [int]$Port = 3100,
  [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Stop"

Write-Host "==> [1/3] Locate paperclip process tree" -ForegroundColor Cyan
$root = Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
  $_.CommandLine -match "paperclipai\s+run" -and $_.CommandLine -notmatch "ConsoleHost"
} | Select-Object -First 1
if (-not $root) {
  # also try pnpm.cmd / pnpm.cjs wrappers
  $root = Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -match "paperclipai\s+run\s+--instance"
  } | Sort-Object -Property CreationDate | Select-Object -First 1
}
if (-not $root) {
  Write-Host "    no paperclip process found; proceeding to launch only"
} else {
  Write-Host "    root pid: $($root.ProcessId)"
  $tree = @($root.ProcessId)
  do {
    $desc = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -in $tree -and $_.ProcessId -notin $tree }
    if ($desc) { $tree += $desc.ProcessId }
  } while ($desc)

  Write-Host "    killing pids: $($tree -join ', ')"
  foreach ($pid_ in $tree) {
    try { Stop-Process -Id $pid_ -Force -ErrorAction Stop }
    catch { Write-Host "    skip $pid_ ($($_.Exception.Message))" -ForegroundColor DarkYellow }
  }
}

Write-Host "==> [2/3] Re-launch paperclip" -ForegroundColor Cyan
$pnpm = "C:\Users\$env:USERNAME\AppData\Roaming\npm\pnpm.cmd"
if (-not (Test-Path $pnpm)) {
  $pnpm = (Get-Command pnpm).Source
}
Start-Process -FilePath $pnpm -ArgumentList "paperclipai","run","--instance","default" `
  -WorkingDirectory "D:\paperclip" -WindowStyle Minimized
Write-Host "    spawned background paperclip run via $pnpm"

Write-Host "==> [3/3] Wait for /api/health = 200 (max $WaitSeconds s)" -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while ((Get-Date) -lt $deadline) {
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:$Port/api/health" -UseBasicParsing -TimeoutSec 3
    if ($r.StatusCode -eq 200) {
      Write-Host "    ready -- $($r.Content)" -ForegroundColor Green
      exit 0
    }
  } catch { }
  Start-Sleep -Seconds 2
}
Write-Host "    TIMEOUT after $WaitSeconds s; health not yet 200" -ForegroundColor Red
exit 1
