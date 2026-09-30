# Amazon RDS for MariaDB instance for WordPress (spec section 6.2). Takes about 10 minutes. Listing: 11-rds-create.
param([string]$Listing = '11-rds-create')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    Write-Step "RDS instance $($A2.Db)"
    if (Test-Aws rds describe-db-instances --db-instance-identifier $A2.Db) { Add-Listing "$($A2.Db) exists" }
    else {
        $version = "$(Invoke-Aws rds describe-db-engine-versions --engine mariadb --default-only --query 'DBEngineVersions[0].EngineVersion' --output text)".Trim()
        $master = (Get-A2Secrets).rdsMasterPassword
        if (-not $master) { throw 'infra/secrets.local.json has no rdsMasterPassword: run infra\14-ssm-parameters.ps1 first' }
        # The master password is masked as ******** in the console output and in the listing.
        $null = Invoke-AwsShow rds create-db-instance --db-instance-identifier $A2.Db --engine mariadb --engine-version $version --db-instance-class $A2.DbClass --allocated-storage 20 --storage-type gp3 --storage-encrypted --master-username admin --master-user-password $master --vpc-security-group-ids (Get-SgId $A2.SgDb) --availability-zone $A2.AzA --no-publicly-accessible --no-multi-az --backup-retention-period 1 --copy-tags-to-snapshot --tags "Key=Project,Value=$($A2.Project)" --query 'DBInstance.[DBInstanceIdentifier,DBInstanceStatus,Engine,EngineVersion,DBInstanceClass]' --output text
    }
    Add-Listing "PS> aws rds wait db-instance-available --db-instance-identifier $($A2.Db)"
    & aws rds wait db-instance-available --db-instance-identifier $A2.Db
    if ($LASTEXITCODE -ne 0) { throw 'the RDS instance did not become available' }
    $null = Invoke-AwsShow rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].{Id:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine,Version:EngineVersion,Class:DBInstanceClass,StorageGiB:AllocatedStorage,Type:StorageType,Encrypted:StorageEncrypted,Public:PubliclyAccessible,MultiAZ:MultiAZ,Zone:AvailabilityZone,BackupDays:BackupRetentionPeriod,Endpoint:Endpoint.Address}' --output table
} finally {
    Save-Listing $Listing
}
