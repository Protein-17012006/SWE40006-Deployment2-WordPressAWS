# WordPress settings and secrets in SSM Parameter Store (spec section 2.3). Listing: 06-codedeploy-setup (first part).
# Existing parameters are kept; deploy.ps1 changes site_url and db_host later.
param([string]$Listing = '06-codedeploy-setup')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2

function Set-A2Parameter([string]$Name, [string]$Type, [string]$Value) {
    if (Test-Aws ssm get-parameter --name $Name) { Add-Listing "$Name exists (kept)"; return }
    $file = Join-Path $A2.Build 'param-value.local.txt'
    [IO.File]::WriteAllText($file, $Value, (New-Object System.Text.UTF8Encoding $false))
    try { $null = Invoke-AwsShow ssm put-parameter --name $Name --type $Type --value file://build/param-value.local.txt --query Version --output text }
    finally { Remove-Item $file -Force }
}

try {
    $secrets = Get-A2Secrets
    if (-not $secrets) {
        $secrets = [pscustomobject]@{ dbPassword = New-A2Secret; rdsMasterPassword = New-A2Secret; authSalts = New-A2Salts }
        Save-A2Secrets $secrets
        Add-SecretRedactions $secrets
        Add-Listing 'Generated the database passwords and the WordPress salts into infra/secrets.local.json (git-ignored)'
    }
    $ip = (Get-A2Instance $A2.DemoName).PublicIp
    if (-not $ip) { throw 'CodeDeployDemo has no public IP yet: run infra\13-ec2-codedeploydemo.ps1 first' }

    Write-Step "Parameters under $($A2.ParamPrefix)"
    Set-A2Parameter "$($A2.ParamPrefix)/db_host" String 'localhost'
    Set-A2Parameter "$($A2.ParamPrefix)/db_name" String 'wordpress'
    Set-A2Parameter "$($A2.ParamPrefix)/db_user" String 'wpuser'
    Set-A2Parameter "$($A2.ParamPrefix)/db_password" SecureString $secrets.dbPassword
    Set-A2Parameter "$($A2.ParamPrefix)/auth_salts" SecureString $secrets.authSalts
    Set-A2Parameter "$($A2.ParamPrefix)/site_url" String "http://$ip/WordPress"
    Set-A2Parameter $A2.RdsMasterParam SecureString $secrets.rdsMasterPassword
    $null = Invoke-AwsShow ssm describe-parameters --parameter-filters 'Key=Name,Option=BeginsWith,Values=/swe40006/' --query 'Parameters[].[Name,Type,Version]' --output table
    $null = Invoke-AwsShow ssm get-parameter --name "$($A2.ParamPrefix)/site_url" --query Parameter.Value --output text
} finally {
    Save-Listing $Listing
}
