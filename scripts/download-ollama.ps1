# Robust downloader: resume + mirror fallback. ASCII only (PS 5.1 safe).
$ErrorActionPreference = 'Continue'
$out = Join-Path $env:TEMP 'OllamaSetup.exe'
$gh  = 'https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe'
$mirrors = @(
    "https://cors.isteed.cc/$gh",
    "https://gh-proxy.com/$gh",
    "https://ghproxy.net/$gh",
    "https://hk.gh-proxy.com/$gh"
)

function Get-RemoteSize([string]$u) {
    $h = curl.exe -sS --ssl-no-revoke -I -L --max-time 25 $u 2>$null
    $line = $h | Where-Object { $_ -match '(?i)^content-length:\s*(\d+)' } | Select-Object -Last 1
    if ($line -match '(\d+)\s*$') { return [int64]$Matches[1] }
    return [int64]0
}

$total = [int64]0
foreach ($m in $mirrors) {
    $total = Get-RemoteSize $m
    if ($total -gt 0) {
        Write-Host ("Total size: {0:N1} MB (via {1})" -f ($total/1MB), $m.Split('/')[2])
        break
    }
}
if ($total -le 0) { Write-Host 'Size probe failed, assuming 1540MB'; $total = [int64](1540MB) }

$stall = 0
for ($round = 1; $round -le 60; $round++) {
    $cur = [int64]0
    if (Test-Path $out) { $cur = (Get-Item $out).Length }
    if ($cur -ge $total) { Write-Host ("DONE: {0:N1} MB" -f ($cur/1MB)); break }

    $mirror = $mirrors[($round - 1) % $mirrors.Count]
    Write-Host ("[{0}] round {1}: have {2:N1}/{3:N1} MB via {4}" -f (Get-Date -Format 'HH:mm:ss'), $round, ($cur/1MB), ($total/1MB), $mirror.Split('/')[2])

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    curl.exe -L --ssl-no-revoke -C - --retry 3 --retry-delay 2 --retry-all-errors --max-time 1200 -sS -o $out $mirror 2>&1 | Select-Object -Last 2 | ForEach-Object { Write-Host ("   " + $_) }
    $sw.Stop()

    $new = [int64]0
    if (Test-Path $out) { $new = (Get-Item $out).Length }
    $rate = 0
    if ($sw.Elapsed.TotalSeconds -gt 0) { $rate = ($new - $cur) / $sw.Elapsed.TotalSeconds }
    Write-Host ("   -> +{0:N1} MB, {1:N0} KB/s, total {2:N1}/{3:N1} MB" -f (($new-$cur)/1MB), ($rate/1KB), ($new/1MB), ($total/1MB))

    if ($new -le $cur) {
        $stall++
        Write-Host ("   ! no progress ($stall/5)")
        if ($stall -ge 5) { Write-Host 'GIVE UP: 5 rounds no progress'; break }
    } else { $stall = 0 }
    Start-Sleep -Seconds 2
}

if (Test-Path $out) {
    $f = Get-Item $out
    Write-Host ("FINAL: {0:N1} MB / {1:N1} MB" -f ($f.Length/1MB), ($total/1MB))
    if ($f.Length -ge $total) { Write-Host 'OK COMPLETE' } else { Write-Host ("INCOMPLETE, missing {0:N1} MB" -f (($total-$f.Length)/1MB)) }
} else {
    Write-Host 'FILE MISSING'
}
