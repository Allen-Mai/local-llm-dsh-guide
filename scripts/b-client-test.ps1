# PC-B connectivity test for PC-A LLM service. ASCII only (PS 5.1 safe).
# Usage: powershell -ExecutionPolicy Bypass -File b-client-test.ps1
$ErrorActionPreference = 'Continue'
$A = '10.8.0.3'
$Port = 11434
$Base = "http://${A}:${Port}"

Write-Host '=== 1. Ping PC-A over VPN ===' -ForegroundColor Cyan
$ping = Test-Connection -ComputerName $A -Count 3 -ErrorAction SilentlyContinue
if ($ping) {
    $avg = ($ping | Measure-Object -Property ResponseTime -Average).Average
    Write-Host ("OK  avg latency = {0:N1} ms" -f $avg) -ForegroundColor Green
} else {
    Write-Host 'FAIL - VPN not connected or PC-A offline' -ForegroundColor Red
    Write-Host 'Check: is OpenVPN connected? Is PC-A powered on?'
    exit 1
}

Write-Host ''
Write-Host '=== 2. Ollama API version ===' -ForegroundColor Cyan
try {
    $v = Invoke-RestMethod "$Base/api/version" -TimeoutSec 10 -UseBasicParsing
    Write-Host "OK  ollama version = $($v.version)" -ForegroundColor Green
} catch {
    Write-Host "FAIL - cannot reach $Base : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Check on PC-A: is ollama running? Is it bound to 10.8.0.3?'
    exit 1
}

Write-Host ''
Write-Host '=== 3. Installed models ===' -ForegroundColor Cyan
try {
    $tags = Invoke-RestMethod "$Base/api/tags" -TimeoutSec 10 -UseBasicParsing
    if ($tags.models.Count -eq 0) {
        Write-Host 'No models installed on PC-A yet' -ForegroundColor Yellow
    } else {
        $tags.models | Select-Object name, @{n='GB';e={[math]::Round($_.size/1GB,2)}} | Format-Table -AutoSize | Out-String | Write-Host
    }
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
Write-Host '=== 4. OpenAI-compatible chat test ===' -ForegroundColor Cyan
$model = 'qwen3:8b'
$body = @{
    model    = $model
    messages = @(@{ role = 'user'; content = 'Reply with exactly: CONNECTION OK' })
    stream   = $false
} | ConvertTo-Json -Depth 5
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $r = Invoke-RestMethod "$Base/v1/chat/completions" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 180 -UseBasicParsing
    $sw.Stop()
    Write-Host ("OK  round-trip {0:N1}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    Write-Host "model replied: $($r.choices[0].message.content)"
    if ($r.usage) { Write-Host "tokens: prompt=$($r.usage.prompt_tokens) completion=$($r.usage.completion_tokens)" }
} catch {
    $sw.Stop()
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'If timeout: model may still be loading (first call can take 30-60s). Retry once.'
}

Write-Host ''
Write-Host '=== 5. Generation speed test ===' -ForegroundColor Cyan
$body2 = @{ model = $model; prompt = 'Count from 1 to 50'; stream = $false; options = @{ num_predict = 100 } } | ConvertTo-Json -Depth 5
try {
    $r2 = Invoke-RestMethod "$Base/api/generate" -Method Post -Body $body2 -ContentType 'application/json' -TimeoutSec 180 -UseBasicParsing
    if ($r2.eval_count -and $r2.eval_duration) {
        Write-Host ("Throughput: {0:N1} tok/s" -f ($r2.eval_count / ($r2.eval_duration/1e9))) -ForegroundColor Green
    }
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
Write-Host '=== Done. If all OK, point your client at: ===' -ForegroundColor Cyan
Write-Host "  OpenAI-compatible base URL : $Base/v1"
Write-Host "  API key                    : any non-empty string (no auth enabled yet)"
Write-Host "  Model name                 : $model"
