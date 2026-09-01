param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'transcribe'
$Cli = Join-Path $InstallDir 'transcribe-cli.exe'
$Model = Join-Path $InstallDir 'models\gigaam-v3-e2e-rnnt-Q8_0.gguf'
$PidFile = Join-Path $env:TEMP 'transcribe.pid'
$WavFile = Join-Path $env:TEMP 'transcribe-rec.wav'
$FfmpegLocal = Join-Path $InstallDir 'tools\ffmpeg.exe'
$DeviceFile = Join-Path $InstallDir 'audio_device.txt'

function Get-Ffmpeg {
    if (Test-Path $FfmpegLocal) { return $FfmpegLocal }
    return 'ffmpeg'
}

function Get-AudioDevice {
    if ($env:TRANSCRIBE_AUDIO_DEVICE) { return $env:TRANSCRIBE_AUDIO_DEVICE }
    if (Test-Path $DeviceFile) { return (Get-Content $DeviceFile -Raw).Trim() }
    throw "Audio device not configured. Re-run install.ps1 or set TRANSCRIBE_AUDIO_DEVICE."
}

function Start-Recording {
    if (Test-Path $PidFile) {
        $oldPid = Get-Content $PidFile -Raw
        if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { return }
    }
    if (Test-Path $WavFile) { Remove-Item $WavFile -Force }
    $ffmpeg = Get-Ffmpeg
    $device = Get-AudioDevice
    $args = @('-y', '-hide_banner', '-loglevel', 'error', '-f', 'dshow', '-i', "audio=$device", '-ar', '16000', '-ac', '1', $WavFile)
    $proc = Start-Process -FilePath $ffmpeg -ArgumentList $args -PassThru -WindowStyle Hidden
    Set-Content -Path $PidFile -Value $proc.Id -NoNewline
}

function Stop-Recording {
    if (-not (Test-Path $PidFile)) { return }
    $procId = [int](Get-Content $PidFile -Raw)
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Id $procId -Force
        Start-Sleep -Milliseconds 200
    }
    if (-not (Test-Path $WavFile) -or ((Get-Item $WavFile).Length -lt 32000)) {
        if (Test-Path $WavFile) { Remove-Item $WavFile -Force }
        return
    }

    $output = & $Cli -m $Model $WavFile 2>$null
    Remove-Item $WavFile -Force -ErrorAction SilentlyContinue
    $text = ($output | Where-Object { $_ -match '^text: ' } | Select-Object -First 1) -replace '^text: ', ''
    if (-not $text -or $text -eq '(empty)') { return }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetText($text.Trim())
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait('^v')
}

switch ($Action) {
    'start' { Start-Recording }
    'stop'  { Stop-Recording }
}
