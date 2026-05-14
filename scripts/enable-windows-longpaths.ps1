<#
.SYNOPSIS
Plan A — enable Windows long-path support so paperclip's `git worktree add`
stops failing when djcowork2.0's deep crate paths exceed 260 characters.

.DESCRIPTION
Sets:
  1. HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled = 1
     (system-wide, requires admin, kicks in after reboot for some apps)
  2. git config --system core.longpaths true (machine-wide git default)
  3. git config --global core.longpaths true (current-user fallback)

Then cleans up the half-checked-out worktree directory that the previous
failed heartbeat left behind, so the next attempt starts from scratch.

.NOTES
Must be run from an **elevated** PowerShell (Run as Administrator).
The git system config write requires either git's bin dir on PATH or the
GIT_EXEC_PATH variable; this script picks it up from `where.exe git`.

.EXAMPLE
PS> Start-Process pwsh -Verb RunAs -ArgumentList "-File D:\paperclip\scripts\enable-windows-longpaths.ps1"
#>
[CmdletBinding()]
param(
  [string]$WorktreeRoot = "D:\opt\paperclip-wsl-worktrees\djcowork2.0\codex",
  [switch]$SkipCleanup
)

$ErrorActionPreference = "Stop"

function Test-Admin {
  $current = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  Write-Host "ERROR: this script must run as Administrator." -ForegroundColor Red
  Write-Host "Re-launch with:" -ForegroundColor Yellow
  Write-Host '  Start-Process pwsh -Verb RunAs -ArgumentList "-File D:\paperclip\scripts\enable-windows-longpaths.ps1"' -ForegroundColor Yellow
  exit 1
}

Write-Host "==> [1/4] Enable LongPathsEnabled in HKLM filesystem policy" -ForegroundColor Cyan
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
$before = (Get-ItemProperty -Path $regPath -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
Write-Host "    current value: $before"
Set-ItemProperty -Path $regPath -Name LongPathsEnabled -Value 1 -Type DWord
$after = (Get-ItemProperty -Path $regPath -Name LongPathsEnabled).LongPathsEnabled
Write-Host "    new value:     $after"

Write-Host "==> [2/4] Set git system-wide longpaths=true" -ForegroundColor Cyan
$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitExe) {
  Write-Host "    git not on PATH; skipping system git config" -ForegroundColor Yellow
} else {
  Write-Host "    git: $gitExe"
  & $gitExe config --system core.longpaths true
  $sysVal = & $gitExe config --system --get core.longpaths
  Write-Host "    system core.longpaths = $sysVal"
}

Write-Host "==> [3/4] Set git --global longpaths=true (current user)" -ForegroundColor Cyan
if ($gitExe) {
  & $gitExe config --global core.longpaths true
  $gblVal = & $gitExe config --global --get core.longpaths
  Write-Host "    global core.longpaths = $gblVal"
}

Write-Host "==> [4/4] Clean up half-checked-out worktree directory" -ForegroundColor Cyan
if ($SkipCleanup) {
  Write-Host "    -SkipCleanup set; leaving $WorktreeRoot alone"
} elseif (Test-Path $WorktreeRoot) {
  $childCount = (Get-ChildItem -LiteralPath $WorktreeRoot -ErrorAction SilentlyContinue | Measure-Object).Count
  Write-Host "    found $childCount entries under $WorktreeRoot"
  Write-Host "    removing..."
  # robocopy mirror trick handles long paths better than Remove-Item on legacy Windows
  $empty = Join-Path $env:TEMP ("paperclip-empty-" + [Guid]::NewGuid())
  New-Item -ItemType Directory -Path $empty -Force | Out-Null
  & robocopy $empty $WorktreeRoot /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  Remove-Item -LiteralPath $WorktreeRoot -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $WorktreeRoot) {
    Write-Host "    WARN: $WorktreeRoot still exists; some files may be locked" -ForegroundColor Yellow
  } else {
    Write-Host "    cleaned"
  }
} else {
  Write-Host "    $WorktreeRoot does not exist; nothing to clean"
}

Write-Host ""
Write-Host "DONE. Long-path support enabled at registry + git layers." -ForegroundColor Green
Write-Host "Next: restart paperclip so any cached child shells pick up the new env."
Write-Host "  - Run scripts\restart-paperclip.ps1 (or kill the pnpm/tsx tree manually)"
Write-Host ""
Write-Host "Then re-invoke the smoke heartbeat:"
Write-Host '  curl -sS -X POST http://localhost:3100/api/agents/af45bbe9-b5ab-4135-8fb2-8624e05e32a9/heartbeat/invoke -H "Content-Type: application/json" -d "{}"'
