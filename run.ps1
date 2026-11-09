# BluePulse - run from a terminal in this folder (or double-click run.bat). Starts main.dart.
#
#   .\run.ps1            web     in Edge with demo data (works without Bluetooth toolchains)
#   .\run.ps1 windows            Windows app, live Bluetooth (needs VS "Desktop development with C++" + Developer Mode)
#   .\run.ps1 android            on a USB-connected phone (needs the Android SDK)
#   .\run.ps1 test               app tests, protocol tests, launcher checks
#   .\run.ps1 analyze            static analysis
#   .\run.ps1 doctor             what is installed and what is missing
#   .\run.ps1 devices            devices Flutter can run on
#
# While the app runs: r = hot reload, R = restart, q = quit.
param(
  [ValidateSet('web', 'windows', 'android', 'test', 'analyze', 'doctor', 'devices')]
  [string]$Target = 'web'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat' }
if (-not (Test-Path $flutter)) { throw "Flutter not found on PATH or at $flutter" }
$dart = Join-Path (Split-Path $flutter) 'dart.bat'
$ps = (Get-Process -Id $PID).Path   # the PowerShell running this script, for the helper scripts

switch ($Target) {
  'web'     { & $flutter run -d edge -t main.dart }
  'windows' { & $flutter run -d windows -t main.dart }
  'android' {
    $id = (& $flutter devices --machine | ConvertFrom-Json | Where-Object { $_.targetPlatform -like 'android*' } | Select-Object -First 1).id
    if (-not $id) { throw 'No Android device found: connect a phone with USB debugging on, then run .\run.ps1 devices' }
    & $flutter run -d $id -t main.dart
  }
  'test' {
    & $flutter test
    Push-Location packages\eye_protocol; & $dart test; Pop-Location
    & $ps -NoProfile -ExecutionPolicy Bypass -File launcher\build.ps1
    & $ps -NoProfile -ExecutionPolicy Bypass -File launcher\test-launcher.ps1
  }
  'analyze' { & $flutter analyze; Push-Location packages\eye_protocol; & $dart analyze; Pop-Location }
  'doctor'  { & $flutter doctor }
  'devices' { & $flutter devices }
}
