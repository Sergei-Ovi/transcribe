#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'transcribe'
$ToolsDir = Join-Path $InstallDir 'tools'
$ModelQuant = 'Q8_0'
$ModelName = 'gigaam-v3-e2e-rnnt'
$ModelUrl = "https://huggingface.co/handy-computer/${ModelName}-gguf/resolve/main/${ModelName}-${ModelQuant}.gguf"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AhkUrl = 'https://www.autohotkey.com/download/ahk-v2.zip'
$FfmpegUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'

function Write-Step([string]$Message) {
    Write-Host "==> $Message"
}

function Find-Python {
    foreach ($candidate in @('python', 'python3', 'py')) {
        if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
        if ($candidate -eq 'py') {
            $version = & py -3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            if ($LASTEXITCODE -eq 0 -and [version]$version -ge [version]'3.9') {
                return @{ Command = 'py'; Args = @('-3') }
            }
            continue
        }
        $version = & $candidate -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        if ($LASTEXITCODE -eq 0 -and [version]$version -ge [version]'3.9') {
            return @{ Command = $candidate; Args = @() }
        }
    }
    return $null
}

function Invoke-Python([hashtable]$Python, [string[]]$ScriptArgs) {
    & $Python.Command @($Python.Args + $ScriptArgs)
    if ($LASTEXITCODE -ne 0) {
        throw "python command failed: $($Python.Command) $($ScriptArgs -join ' ')"
    }
}

function Get-FfmpegPath {
    $local = Join-Path $ToolsDir 'ffmpeg.exe'
    if (Test-Path $local) { return $local }
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { return 'ffmpeg' }
    return $null
}

function Ensure-Ffmpeg {
    if (Get-FfmpegPath) { return }

    Write-Step "Downloading portable ffmpeg..."
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $zipPath = Join-Path $env:TEMP 'transcribe-ffmpeg.zip'
    Invoke-WebRequest -Uri $FfmpegUrl -OutFile $zipPath -UseBasicParsing
    $extractDir = Join-Path $env:TEMP 'transcribe-ffmpeg'
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $ffmpeg = Get-ChildItem -Path $extractDir -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
    if (-not $ffmpeg) { throw 'ffmpeg.exe not found in downloaded archive' }
    Copy-Item $ffmpeg.FullName (Join-Path $ToolsDir 'ffmpeg.exe') -Force
}

function Ensure-AutoHotkey {
    $ahk = Join-Path $ToolsDir 'AutoHotkey64.exe'
    if (Test-Path $ahk) { return $ahk }

    Write-Step "Downloading portable AutoHotkey v2..."
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $zipPath = Join-Path $env:TEMP 'transcribe-ahk.zip'
    Invoke-WebRequest -Uri $AhkUrl -OutFile $zipPath -UseBasicParsing
    $extractDir = Join-Path $env:TEMP 'transcribe-ahk'
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $exe = Get-ChildItem -Path $extractDir -Recurse -Filter 'AutoHotkey64.exe' | Select-Object -First 1
    if (-not $exe) { throw 'AutoHotkey64.exe not found in downloaded archive' }
    Copy-Item $exe.FullName $ahk -Force
    return $ahk
}

function Detect-Microphone([string]$Ffmpeg) {
    $configFile = Join-Path $InstallDir 'audio_device.txt'
    if (Test-Path $configFile) {
        return (Get-Content $configFile -Raw).Trim()
    }

    $output = & $Ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1 | Out-String
    $matches = [regex]::Matches($output, '(?m)\[dshow @ [^\]]+\] "(.+)" \(audio\)')
    if ($matches.Count -eq 0) {
        throw "No audio input devices found. Set device name in $configFile"
    }

    $device = $matches[0].Groups[1].Value
    Set-Content -Path $configFile -Value $device -NoNewline
    Write-Step "Using microphone: $device"
    return $device
}

function Install-PythonEnv([hashtable]$Python) {
    $venvPython = Join-Path $InstallDir 'venv\Scripts\python.exe'
    if (-not (Test-Path $venvPython)) {
        Write-Step 'Creating Python venv and installing transcribe-cpp...'
        Invoke-Python $Python @('-m', 'venv', (Join-Path $InstallDir 'venv'))
        & $venvPython -m pip install --upgrade pip
        if ($LASTEXITCODE -ne 0) { throw 'pip upgrade failed' }
        & $venvPython -m pip install transcribe-cpp
        if ($LASTEXITCODE -ne 0) { throw 'transcribe-cpp install failed' }
    } else {
        Write-Step 'Python venv already exists, skipping transcribe-cpp install'
    }

    $source = Join-Path $ScriptDir 'transcribe.py'
    if (-not (Test-Path $source)) {
        throw "transcribe.py not found next to install.ps1"
    }
    Copy-Item $source (Join-Path $InstallDir 'transcribe.py') -Force
}

function Install-Model {
    $modelDir = Join-Path $InstallDir 'models'
    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
    $modelFile = Join-Path $modelDir "${ModelName}-${ModelQuant}.gguf"
    if (-not (Test-Path $modelFile)) {
        Write-Step "Downloading ${ModelName} model (${ModelQuant})..."
        Invoke-WebRequest -Uri $ModelUrl -OutFile $modelFile -UseBasicParsing
    }
}

function Write-TranscribePs1 {
    @'
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'transcribe'
$Python = Join-Path $InstallDir 'venv\Scripts\python.exe'
$Transcribe = Join-Path $InstallDir 'transcribe.py'
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

    $text = & $Python $Transcribe $Model $WavFile 2>$null
    Remove-Item $WavFile -Force -ErrorAction SilentlyContinue
    if (-not $text) { return }

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Clipboard]::SetText($text.Trim())
    Start-Sleep -Milliseconds 80
    [System.Windows.Forms.SendKeys]::SendWait('^v')
}

switch ($Action) {
    'start' { Start-Recording }
    'stop'  { Stop-Recording }
}
'@ | Set-Content -Path (Join-Path $InstallDir 'transcribe.ps1') -Encoding UTF8
}

function Write-TranscribeAhk {
    $ps1 = Join-Path $InstallDir 'transcribe.ps1'
    @"
#Requires AutoHotkey v2.0
#SingleInstance Force

InstallDir := "$InstallDir"
Ps1 := InstallDir . "\transcribe.ps1"

RunTranscribe(action) {
    Run('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' Ps1 '" ' action, , 'Hide')
}

F9::{
    RunTranscribe('start')
    KeyWait('F9')
    RunTranscribe('stop')
}
"@ | Set-Content -Path (Join-Path $InstallDir 'transcribe.ahk') -Encoding UTF8
}

function Install-StartupShortcut([string]$AhkExe) {
    $startup = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startup 'transcribe.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $AhkExe
    $shortcut.Arguments = "`"$(Join-Path $InstallDir 'transcribe.ahk')`""
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Hold F9 to transcribe speech'
    $shortcut.Save()
    Write-Step "Added startup shortcut: $shortcutPath"
}

function Main {
    Write-Step 'transcribe installer (Windows)'
    Write-Host "    Install dir: $InstallDir"
    Write-Host ''

    $python = Find-Python
    if (-not $python) {
        throw 'Python 3.9+ not found. Install from https://www.python.org/downloads/ and re-run.'
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    Install-PythonEnv $python
    Install-Model
    Ensure-Ffmpeg
    $ffmpeg = Get-FfmpegPath
    Detect-Microphone $ffmpeg
    Write-TranscribePs1
    Write-TranscribeAhk
    $ahk = Ensure-AutoHotkey
    Install-StartupShortcut $ahk

    Write-Host ''
    Write-Step 'Done!'
    Write-Host "    Python:  $(Join-Path $InstallDir 'venv\Scripts\python.exe')"
    Write-Host "    Model:   $(Join-Path $InstallDir "models\${ModelName}-${ModelQuant}.gguf")"
    Write-Host "    Script:  $(Join-Path $InstallDir 'transcribe.ps1')"
    Write-Host "    Hotkey:  F9 hold-to-record (AutoHotkey, starts with Windows)"
    Write-Host ''
    Write-Host '    Log out/in or run transcribe.ahk once if F9 does not work yet.'
}

Main
