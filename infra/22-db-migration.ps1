# Task 2.2: copy the WordPress database from CodeDeployDemo's MariaDB to RDS (dump -> S3 -> import -> row counts).
# Listing: 12-db-migration.
param([string]$Listing = '12-db-migration')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
$ip = (Get-A2Instance $A2.DemoName).PublicIp
$endpoint = "$(Invoke-Aws rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].Endpoint.Address' --output text)".Trim()
$cnf = Join-Path $A2.Build 'rds-admin.cnf'
try {
    $master = (Get-A2Secrets).rdsMasterPassword
    [IO.File]::WriteAllText($cnf, "[client]`nuser=admin`npassword=$master`n", (New-Object System.Text.UTF8Encoding $false))
    Copy-ToRemote $ip @('infra\remote\db-migrate.sh', 'build\rds-admin.cnf')
    Add-Listing '(infra/remote/db-migrate.sh and the RDS master login file copied to ~/a2, a mode-700 directory)'
    Write-Step 'Dump the local database and keep a copy in S3'
    $null = Invoke-Remote $ip "bash a2/db-migrate.sh dump $($A2.BucketBackup)" -Show
    Write-Step 'Import the dump into RDS and create the WordPress user'
    $null = Invoke-Remote $ip "bash a2/db-migrate.sh import $endpoint" -Show
    Write-Step 'Row counts: local MariaDB versus RDS'
    $null = Invoke-Remote $ip "bash a2/db-migrate.sh counts $endpoint" -Show
    $null = Invoke-AwsShow s3 ls "s3://$($A2.BucketBackup)/db/" --human-readable
} finally {
    Remove-Item $cnf -Force -ErrorAction SilentlyContinue
    # Cleanup must never hide the error that stopped the script.
    if ($ip) { try { $null = Invoke-Remote $ip 'rm -rf ~/a2; test ! -e ~/a2 && echo removed ~/a2, including the RDS master login file' -Show } catch { Write-Host "cleanup of ~/a2 skipped: $($_.Exception.Message)" } }
    Save-Listing $Listing
}
