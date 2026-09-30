# S3 buckets for the WordPress revision and the backups (CodeDeploy tutorial Step 3), plus a record that the
# AWS CodeDeploy service itself is unavailable on this Free-plan account. Listing: 06-codedeploy-setup (appended).
param([string]$Listing = '06-codedeploy-setup')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    foreach ($bucket in $A2.BucketDeploy, $A2.BucketBackup) {
        Write-Step "Bucket $bucket"
        if (Test-Aws s3api head-bucket --bucket $bucket) { Add-Listing "$bucket exists" }
        else {
            $null = Invoke-AwsShow s3 mb "s3://$bucket" --region $A2.Region
        }
        $null = Invoke-AwsShow s3api put-public-access-block --bucket $bucket --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
        $null = Invoke-AwsShow s3api put-bucket-encryption --bucket $bucket --server-side-encryption-configuration file://infra/policies/bucket-encryption.json
    }
    $null = Invoke-AwsShow s3api put-bucket-policy --bucket $A2.BucketDeploy --policy (Expand-A2Template 'deploy-bucket-policy.json')

    Write-Step 'AWS CodeDeploy on this account (the tutorial creates WordPress_App here)'
    Add-Listing 'PS> aws deploy list-applications'
    Add-Listing ([string[]](cmd /c 'aws deploy list-applications 2>&1'))
    Add-Listing '(AWS CodeDeploy is not available on this AWS Free-plan account, so infra/remote/deploy-revision.sh runs the revision''s appspec hooks instead; see docs/error-log.md #3)'
} finally {
    Save-Listing $Listing -Append
}
