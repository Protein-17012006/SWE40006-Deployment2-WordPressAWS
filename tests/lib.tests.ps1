# Unit tests for the pure helpers in infra/lib.ps1:  powershell -NoProfile -File tests\lib.tests.ps1
. "$PSScriptRoot\..\infra\config.ps1"
. "$PSScriptRoot\..\infra\lib.ps1"
$script:passed = 0
$script:failed = 0

function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passed++; "PASS  $Name" }
    catch { $script:failed++; "FAIL  $Name`n      $($_.Exception.Message)" }
}
function Assert-Equal($Expected, $Actual) {
    if ($Expected -cne $Actual) { throw "expected '$Expected', got '$Actual'" }
}
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Test-Case 'New-A2Secret returns 24 unambiguous letters and digits' {
    $s = New-A2Secret
    Assert-True ($s -cmatch '^[A-HJ-NP-Za-km-z2-9]{24}$') "unexpected secret format: $s"
    Assert-True ($s -cne (New-A2Secret)) 'two secrets were identical'
}

Test-Case 'New-A2Salts defines the eight WordPress keys with 64-character values' {
    $lines = (New-A2Salts) -split "`n"
    Assert-Equal 8 $lines.Count
    Assert-True ($lines[0] -cmatch "^define\( 'AUTH_KEY', '[A-Za-z0-9]{64}' \);$") "bad first line: $($lines[0])"
    Assert-True ($lines[7] -cmatch "^define\( 'NONCE_SALT', '[A-Za-z0-9]{64}' \);$") "bad last line: $($lines[7])"
}

Test-Case 'Protect-Text masks secrets, the account ID and the client IP' {
    $script:AccountId = '123456789012'
    $script:ClientIp = '203.0.113.7'
    Add-Redaction 'Sup3rS3cretValue'
    Assert-Equal 'arn:aws:iam::************:role/x from x.x.x.x using ********' (Protect-Text 'arn:aws:iam::123456789012:role/x from 203.0.113.7 using Sup3rS3cretValue')
}

Test-Case 'ConvertTo-ShownCommand quotes arguments that contain spaces' {
    Assert-Equal "aws deploy push --description 'Deploy 1'" (ConvertTo-ShownCommand 'aws' @('deploy', 'push', '--description', 'Deploy 1'))
}

Test-Case 'scripts never pass an unquoted comma list to a command (PowerShell would split it)' {
    $offenders = foreach ($f in Get-ChildItem "$PSScriptRoot\..\infra", "$PSScriptRoot\..\codedeploy" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.ArrayLiteralAst] -and
            $n.Parent -is [System.Management.Automation.Language.CommandAst] -and
            @($n.Elements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.StringConstantType -eq 'BareWord' -and $_.Value -like '*=*' }).Count
        }, $true) | ForEach-Object { "$($f.Name):$($_.Extent.StartLineNumber) $($_.Extent.Text)" }
    }
    Assert-True (-not $offenders) ('unquoted comma lists: ' + ($offenders -join '; '))
}

"`n$($script:passed) passed, $($script:failed) failed"
if ($script:failed) { exit 1 }
