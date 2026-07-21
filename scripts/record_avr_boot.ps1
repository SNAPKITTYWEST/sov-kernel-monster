# record_avr_boot.ps1
# Records the AVR cold boot demo as an asciinema .cast file
# and also saves a plain .log for archiving.
#
# Usage:
#   pwsh -File scripts/record_avr_boot.ps1
#
# Output:
#   avr_cold_boot_YYYYMMDD_HHMMSS.cast   (asciinema v2 format — playable with asciinema play)
#   avr_cold_boot_YYYYMMDD_HHMMSS.log    (plain text transcript)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$castFile  = Join-Path $PSScriptRoot "..\avr_cold_boot_$timestamp.cast"
$logFile   = Join-Path $PSScriptRoot "..\avr_cold_boot_$timestamp.log"
$script    = Join-Path $PSScriptRoot "avr_cold_boot_demo.py"

# Resolve absolute paths
$castFile  = [System.IO.Path]::GetFullPath($castFile)
$logFile   = [System.IO.Path]::GetFullPath($logFile)
$script    = [System.IO.Path]::GetFullPath($script)

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     SOV-KERNEL-MONSTER  ·  AVR Cold Boot Recorder            ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Recording to:" -ForegroundColor Yellow
Write-Host "    $castFile" -ForegroundColor White
Write-Host "    $logFile"  -ForegroundColor White
Write-Host ""
Write-Host "  Press ENTER to start recording..." -ForegroundColor Green
$null = Read-Host

# ── Build asciinema v2 .cast manually ──────────────────────────────
# Format: header JSON line, then event lines: [time, "o", data]

$header = @{
    version   = 2
    width     = 180
    height    = 50
    timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    title     = "SOV-KERNEL-MONSTER AVR Cold Boot — Ahmad Ali Parr 2026"
    env       = @{ TERM = "xterm-256color"; SHELL = "pwsh" }
} | ConvertTo-Json -Compress

# Run demo, capture output with timing
$startTime = [System.Diagnostics.Stopwatch]::StartNew()
$events    = [System.Collections.Generic.List[string]]::new()

# Capture python output line by line with timestamps
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = "python"
$psi.Arguments              = "`"$script`""
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi

# Buffer for tee (show on screen AND capture)
$logLines = [System.Collections.Generic.List[string]]::new()

$outputHandler = {
    param($sender, $e)
    if ($null -ne $e.Data) {
        $elapsed = $startTime.Elapsed.TotalSeconds
        $line    = $e.Data + "`n"
        # Asciinema event
        $ev = "[{0:F6}, `"o`", {1}]" -f $elapsed, ($line | ConvertTo-Json -Compress)
        $events.Add($ev)
        $logLines.Add($e.Data)
        Write-Host $e.Data
    }
}

$proc.add_OutputDataReceived($outputHandler)
$proc.Start() | Out-Null
$proc.BeginOutputReadLine()
$proc.WaitForExit()

$startTime.Stop()

# ── Write .cast file ────────────────────────────────────────────────
$castLines = [System.Collections.Generic.List[string]]::new()
$castLines.Add($header)
foreach ($ev in $events) { $castLines.Add($ev) }
[System.IO.File]::WriteAllLines($castFile, $castLines, [System.Text.Encoding]::UTF8)

# ── Write .log file ─────────────────────────────────────────────────
[System.IO.File]::WriteAllLines($logFile, $logLines, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║  RECORDING COMPLETE                                           ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  .cast  : $castFile" -ForegroundColor Cyan
Write-Host "  .log   : $logFile"  -ForegroundColor Cyan
Write-Host ""
Write-Host "  To replay (if asciinema installed):" -ForegroundColor Yellow
Write-Host "    asciinema play `"$castFile`"" -ForegroundColor White
Write-Host ""
Write-Host "  To share: upload .cast to https://asciinema.org/docs/self-hosting" -ForegroundColor DIM
Write-Host ""
