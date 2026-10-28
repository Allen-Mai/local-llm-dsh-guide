# Ollama silent install + verify. ASCII only (PS 5.1 safe).
$ErrorActionPreference = 'Stop'
$Installer = Join-Path $env:TEMP 'OllamaSetup.exe'
$ExePath   = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
$MinBytes  = [int64]1550000000

Write-Host '=== 1. Verify installer ==='
if (-not (Test-Path $Installer)) { throw "Installer missing: $Installer" }
$f = Get-Item $Installer
Write-Host ("Size: {0:N1} MB" -f ($f.Length/1MB))
if ($f.Length -lt $MinBytes) { throw "Installer incomplete (<1.55GB). Re-download." }

Write-Host ''
Write-Host '=== 2. Silent install (per-user, no admin needed) ==='
$proc = Start-Process -FilePath $Installer -ArgumentList '/VERYSILENT','/NORESTART','/SUPPRESSMSGBOXES','/SP-' -Wait -PassThru
Write-Host "Installer exit code: $($proc.ExitCode)"

Write-Host ''
Write-Host '=== 3. Verify installation ==='
if (-not (Test-Path $ExePath)) { throw "Install failed, missing $ExePath" }
$ver = (Get-Item $ExePath).VersionInfo.FileVersion
Write-Host "ollama.exe version: $ver"

Write-Host ''
Write-Host '=== 4. Check env vars ==='
foreach ($k in @('OLLAMA_HOST','OLLAMA_FLASH_ATTENTION','OLLAMA_KV_CACHE_TYPE','OLLAMA_CONTEXT_LENGTH','OLLAMA_NUM_PARALLEL','OLLAMA_MAX_LOADED_MODELS','OLLAMA_KEEP_ALIVE')) {
    $v = [Environment]::GetEnvironmentVariable($k,'User')
    if (-not $v) { $v = '(unset)' }
    Write-Host ("{0,-26} = {1}" -f $k, $v)
}

Write-Host ''
Write-Host '=== 5. Stop any auto-started ollama ==='
Get-Process | Where-Object { $_.Name -match 'ollama' } | ForEach-Object {
    Write-Host "Stopping $($_.Name) (PID $($_.Id))"
    try { $_.Kill() } catch {}
}
Start-Sleep -Seconds 2

Write-Host ''
Write-Host '=== 6. Start ollama serve with tuned env ==='
$env:OLLAMA_HOST              = [Environment]::GetEnvironmentVariable('OLLAMA_HOST','User')
$env:OLLAMA_FLASH_ATTENTION   = '1'
$env:OLLAMA_KV_CACHE_TYPE     = 'q8_0'
$env:OLLAMA_CONTEXT_LENGTH    = '32768'
$env:OLLAMA_NUM_PARALLEL      = '1'
$env:OLLAMA_MAX_LOADED_MODELS = '1'
$env:OLLAMA_KEEP_ALIVE        = '30m'
Write-Host "Binding to $($env:OLLAMA_HOST)"
Start-Process -FilePath $ExePath -ArgumentList 'serve' -WindowStyle Hidden
Start-Sleep -Seconds 8

Write-Host ''
Write-Host '=== 7. Verify listener + API ==='
$listen = Get-NetTCPConnection -LocalPort 11434 -State Listen -ErrorAction SilentlyContinue
if ($listen) {
    $listen | Select-Object LocalAddress,LocalPort,State | Format-Table -AutoSize | Out-String | Write-Host
} else {
    Write-Host 'WARN: 11434 not listening'
}
$ok = $false
try {
    $r = Invoke-RestMethod -Uri 'http://10.8.0.3:11434/api/version' -TimeoutSec 10 -UseBasicParsing
    Write-Host "API OK on 10.8.0.3 version=$($r.version)"
    $ok = $true
} catch {
    Write-Host "API on 10.8.0.3 failed: $($_.Exception.Message)"
}
if (-not $ok) {
    try {
        $r2 = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/version' -TimeoutSec 10 -UseBasicParsing
        Write-Host "API OK on 127.0.0.1 only (version=$($r2.version)) - NOT bound to VPN IP"
    } catch {
        Write-Host 'API unreachable on both addresses'
    }
}
Write-Host ''
Write-Host '=== DONE ==='
