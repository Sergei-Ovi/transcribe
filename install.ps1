#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'transcribe'
$ToolsDir = Join-Path $InstallDir 'tools'
$ModelQuant = 'Q8_0'
$ModelName = 'gigaam-v3-e2e-rnnt'
$ModelUrl = "https://huggingface.co/handy-computer/${ModelName}-gguf/resolve/main/${ModelName}-${ModelQuant}.gguf"
$ReleaseRepo = if ($env:TRANSCRIBE_RELEASE_REPO) { $env:TRANSCRIBE_RELEASE_REPO } else { 'Sergei-Ovi/transcribe' }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AhkUrl = 'https://www.autohotkey.com/download/ahk-v2.zip'
$FfmpegUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$CliAsset = 'transcribe-cli-windows-x86_64.exe'

function Write-Step([string]$Message) {
    Write-Host "==> $Message"
}

function Get-LatestRelease {
    $response = Invoke-RestMethod "https://api.github.com/repos/$ReleaseRepo/releases/latest"
    return $response.tag_name
}

function Get-FfmpegPath {
    $local = Join-Path $ToolsDir 'ffmpeg.exe'
    if (Test-Path $local) { return $local }
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { return 'ffmpeg' }
    return $null
}

function Ensure-Ffmpeg {
    if (Get-FfmpegPath) { return }

    Write-Step 'Downloading portable ffmpeg...'
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

    Write-Step 'Downloading portable AutoHotkey v2...'
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

function Install-Cli {
    $cliPath = Join-Path $InstallDir 'transcribe-cli.exe'
    if (Test-Path $cliPath) {
        Write-Step 'transcribe-cli already installed, skipping download'
        return
    }

    $release = Get-LatestRelease
    $url = "https://github.com/$ReleaseRepo/releases/download/$release/$CliAsset"
    Write-Step "Downloading transcribe-cli $release ($CliAsset)..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $cliPath -UseBasicParsing
    } catch {
        Remove-Item $cliPath -ErrorAction SilentlyContinue
        throw "Failed to download $url. Publish a release first: git tag v1.0.0; git push origin v1.0.0"
    }
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

function Install-RuntimeScripts {
    $sourcePs1 = Join-Path $ScriptDir 'transcribe.ps1'
    if (-not (Test-Path $sourcePs1)) {
        throw 'transcribe.ps1 not found next to install.ps1'
    }
    Copy-Item $sourcePs1 (Join-Path $InstallDir 'transcribe.ps1') -Force
}

function Write-TranscribeAhk {
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
    Write-Host "    Releases:    https://github.com/$ReleaseRepo/releases"
    Write-Host ''

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    Install-Cli
    Install-Model
    Ensure-Ffmpeg
    $ffmpeg = Get-FfmpegPath
    Detect-Microphone $ffmpeg
    Install-RuntimeScripts
    Write-TranscribeAhk
    $ahk = Ensure-AutoHotkey
    Install-StartupShortcut $ahk

    Write-Host ''
    Write-Step 'Done!'
    Write-Host "    CLI:     $(Join-Path $InstallDir 'transcribe-cli.exe')"
    Write-Host "    Model:   $(Join-Path $InstallDir "models\${ModelName}-${ModelQuant}.gguf")"
    Write-Host "    Script:  $(Join-Path $InstallDir 'transcribe.ps1')"
    Write-Host "    Hotkey:  F9 hold-to-record (AutoHotkey, starts with Windows)"
    Write-Host ''
    Write-Host '    Log out/in or run transcribe.ahk once if F9 does not work yet.'
}

Main
