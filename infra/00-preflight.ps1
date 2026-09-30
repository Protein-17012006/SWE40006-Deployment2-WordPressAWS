# Read-only checks before anything is created (spec section 5.2). Listing: 02-preflight.
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    Write-Step 'Caller identity (aws login session)'
    $null = Invoke-AwsShow sts get-caller-identity --output table

    Write-Step 'Account security and cost controls (read-only; replaces the dropped screenshots u02 and u04)'
    $null = Invoke-AwsShow iam get-account-summary --query 'SummaryMap.{RootMfaEnabled:AccountMFAEnabled,Users:Users,Roles:Roles}' --output table
    $null = Invoke-AwsShow budgets describe-budgets --account-id $script:AccountId --query 'Budgets[].{Name:BudgetName,Limit:BudgetLimit.Amount,Unit:BudgetLimit.Unit}' --output table

    Write-Step 'Default VPC and its default subnets'
    $vpc = Get-DefaultVpcId
    Add-Listing "Default VPC: $vpc"
    $null = Invoke-AwsShow ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" 'Name=default-for-az,Values=true' --query 'Subnets[].[AvailabilityZone,SubnetId,CidrBlock,MapPublicIpOnLaunch]' --output table

    Write-Step 'EC2 vCPU quota: Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances'
    $quota = "$(Invoke-AwsShow service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value' --output text)".Trim()
    Add-Listing "Peak need: 10 vCPUs (CodeDeployDemo + 4 ASG instances, 2 vCPUs each). Current quota: $quota"

    Write-Step 'Latest Amazon Linux 2023 AMI'
    $null = Invoke-AwsShow ssm get-parameters --names $A2.AmiParameter --query 'Parameters[0].[Name,Value]' --output text

    Write-Step 'CodeDeploy agent installers in this Region'
    foreach ($prefix in 'latestv2', 'latest') {
        $url = "https://aws-codedeploy-$($A2.Region).s3.$($A2.Region).amazonaws.com/$prefix/install"
        try { $r = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $url; Add-Listing "$url -> HTTP $($r.StatusCode)" }
        catch { Add-Listing "$url -> not available ($($_.Exception.Message))" }
    }

    Write-Step 'Default RDS for MariaDB engine version and db.t4g.micro availability'
    $null = Invoke-AwsShow rds describe-db-engine-versions --engine mariadb --default-only --query 'DBEngineVersions[0].[Engine,EngineVersion,DBParameterGroupFamily]' --output text
    $version = "$(Invoke-Aws rds describe-db-engine-versions --engine mariadb --default-only --query 'DBEngineVersions[0].EngineVersion' --output text)".Trim()
    $null = Invoke-AwsShow rds describe-orderable-db-instance-options --engine mariadb --engine-version $version --db-instance-class $A2.DbClass --query 'OrderableDBInstanceOptions[0].[DBInstanceClass,StorageType]' --output text
} finally {
    Save-Listing '02-preflight'
}
