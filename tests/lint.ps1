# Lints everything that runs on Linux (no CR characters, bash -n, ShellCheck, php -l), then runs the PHP unit tests.
#   powershell -NoProfile -File tests\lint.ps1 [-Path <folders>]
param([string[]]$Path = @('codedeploy', 'infra\remote', 'infra\user-data'))
$ErrorActionPreference = 'Continue'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location (Split-Path $PSScriptRoot -Parent)
$failures = 0
$files = @(Get-ChildItem -Path ($Path | Where-Object { Test-Path $_ }) -Recurse -File -Include *.sh, *.yml, *.php, *.conf)
foreach ($f in $files) {
    if ([IO.File]::ReadAllText($f.FullName).Contains("`r")) { Write-Host "CR          $($f.FullName)"; $failures++ }
}
$shell = @($files | Where-Object { $_.Extension -eq '.sh' })
foreach ($f in $shell) {
    & 'C:\Program Files\Git\bin\bash.exe' -n ($f.FullName -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { Write-Host "bash -n     $($f.Name)"; $failures++ }
}
if ($shell.Count) {
    & shellcheck -x -P SCRIPTDIR -s bash @($shell | ForEach-Object { $_.FullName })
    if ($LASTEXITCODE -ne 0) { Write-Host 'ShellCheck  reported the problems above'; $failures++ }
}
foreach ($f in @($files | Where-Object { $_.Extension -eq '.php' })) {
    $null = & php -l $f.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "php -l      $($f.Name)"; $failures++ }
}
& php tests\run.php
if ($LASTEXITCODE -ne 0) { $failures++ }
& 'C:\Program Files\Git\bin\bash.exe' tests/deploy-revision.test.sh
if ($LASTEXITCODE -ne 0) { $failures++ }
if ($failures) { Write-Host "LINT FAILED ($failures problem(s))"; exit 1 }
Write-Host "LINT OK ($($files.Count) files checked)"
