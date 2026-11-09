@echo off
rem BluePulse - run from this folder. Double-click for the browser demo, or type:
rem   run            browser (Edge) with demo data
rem   run windows    Windows app with live Bluetooth (needs Visual Studio C++ tools + Developer Mode)
rem   run android    phone over USB (needs the Android SDK)
rem   run test       all tests
rem   run doctor     what is installed and what is missing
rem Works even where PowerShell scripts are blocked: it starts run.ps1 with -ExecutionPolicy Bypass.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
if errorlevel 1 pause
