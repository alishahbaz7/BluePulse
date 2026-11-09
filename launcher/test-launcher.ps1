# Checks the launcher against a fake install: it must start the newest complete version, compare
# versions numerically, skip half-written (.partial) and empty folders, and pass arguments on minus
# its own flags. Run after build.ps1.
param([string]$Launcher = (Join-Path $PSScriptRoot '..\build\launcher\BluePulse.exe'))

$ErrorActionPreference = 'Stop'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$work = Join-Path ([IO.Path]::GetTempPath()) ("eye-launcher-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $work | Out-Null

# A stand-in app: writes "<its folder>|<args>" to <root>\started.txt and exits.
$dummySrc = Join-Path $work 'Dummy.cs'
@'
using System; using System.IO;
static class P { static void Main(string[] a) {
  var dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
  var root = Directory.GetParent(Directory.GetParent(dir).FullName).FullName;
  File.WriteAllText(Path.Combine(root, "started.txt"), Path.GetFileName(dir) + "|" + string.Join(" ", a));
} }
'@ | Set-Content $dummySrc
$dummy = Join-Path $work 'Dummy.exe'
& $csc /nologo /target:winexe "/out:$dummy" $dummySrc | Out-Null

function New-Root([string[]]$complete, [string[]]$partial, [string[]]$empty) {
  $root = Join-Path $work ([guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory (Join-Path $root 'versions') -Force | Out-Null
  Copy-Item $Launcher (Join-Path $root 'BluePulse.exe')
  foreach ($v in $complete) {
    $d = Join-Path $root "versions\BluePulse-v$v"; New-Item -ItemType Directory $d | Out-Null
    Copy-Item $dummy (Join-Path $d "BluePulse-v$v.exe")
  }
  foreach ($v in $partial) {
    $d = Join-Path $root "versions\BluePulse-v$v.partial"; New-Item -ItemType Directory $d | Out-Null
    Copy-Item $dummy (Join-Path $d "BluePulse-v$v.exe")
  }
  foreach ($v in $empty) { New-Item -ItemType Directory (Join-Path $root "versions\BluePulse-v$v") | Out-Null }
  return $root
}

function Run([string]$root, [string[]]$launcherArgs) {
  $exe = Join-Path $root 'BluePulse.exe'
  if ($launcherArgs) { Start-Process -FilePath $exe -ArgumentList $launcherArgs -Wait } else { Start-Process -FilePath $exe -Wait }
  $marker = Join-Path $root 'started.txt'
  for ($i = 0; $i -lt 50 -and -not (Test-Path $marker); $i++) { Start-Sleep -Milliseconds 100 }
  if (-not (Test-Path $marker)) { return '<nothing started>' }
  return (Get-Content $marker -Raw).Trim()
}

$fails = 0
function Check([string]$name, [string]$got, [string]$want) {
  if ($got -eq $want) { Write-Output "PASS  $name" } else { Write-Output "FAIL  $name - got '$got', want '$want'"; $script:fails++ }
}

$r = New-Root @('1.0.0', '1.2.0') @('1.9.0') @('1.5.0')
Check 'newest complete version; skips .partial and empty folders' (Run $r @()) 'BluePulse-v1.2.0|'

$r = New-Root @('1.2.0', '1.10.0', '1.9.3') @() @()
Check 'versions compare numerically (1.10.0 > 1.9.3 > 1.2.0)' (Run $r @()) 'BluePulse-v1.10.0|'

$r = New-Root @('1.0.0') @() @()
Check 'arguments pass through, launcher flags removed' (Run $r @('--after-update', 'hello', '"two words"')) 'BluePulse-v1.0.0|hello two words'

$log = Get-Content (Join-Path $r 'launcher.log') -Raw
Check 'writes launcher.log' ([bool]($log -match 'started 1\.0\.0 after update')) 'True'

Remove-Item $work -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
if ($fails -gt 0) { Write-Output "$fails failed"; exit 1 } else { Write-Output 'All launcher checks passed' }
