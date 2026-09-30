# Fails (exit 1) when any file contains a generated secret, the raw AWS account ID or this machine's public IP.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\check-secrets.ps1                 # all listings
#   & .\tests\check-secrets.ps1 -Files (git ls-files)     # tracked files; run it in-process, because
#                                                         # powershell -File cannot pass an array parameter
param([string[]]$Files = @())
. "$PSScriptRoot\..\infra\config.ps1"
. "$PSScriptRoot\..\infra\lib.ps1"
Initialize-A2
if (-not $Files.Count) { $Files = @(Get-ChildItem $A2.Listings -Filter *.txt | ForEach-Object { $_.FullName }) }
$needles = @($script:Redactions) + @($script:AccountId, $script:ClientIp) | Where-Object { $_ }
$hits = foreach ($f in $Files) {
    if (-not (Test-Path $f -PathType Leaf)) { continue }
    $text = [IO.File]::ReadAllText((Resolve-Path $f).Path)
    foreach ($n in $needles) { if ($text.Contains($n)) { "$f contains a value starting with '$($n.Substring(0, 3))'" } }
}
if ($hits) { $hits; exit 1 }
"No secrets, account ID or client IP found in $($Files.Count) file(s)"
