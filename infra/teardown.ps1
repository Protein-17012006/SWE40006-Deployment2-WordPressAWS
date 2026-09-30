# Deletes every Assignment 2 resource after grading (spec section 9). Run it with -DryRun first.
param([switch]$DryRun, [switch]$IUnderstandThisDeletesEverything)
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
if (-not $DryRun -and -not $IUnderstandThisDeletesEverything) { throw 'Use -DryRun to list what would be deleted, or -IUnderstandThisDeletesEverything to delete it.' }
if (-not $DryRun) {
    $typed = Read-Host "Type the AWS account ID ($($script:AccountId)) to delete every Assignment 2 resource"
    if ($typed.Trim() -ne $script:AccountId) { throw 'The account ID did not match; nothing was deleted.' }
}
function Remove-A2([string]$What, [bool]$Exists, [scriptblock]$Action) {
    if (-not $Exists) { return }
    if ($DryRun) { Write-Host "would delete: $What"; return }
    Write-Step "Delete $What"
    & $Action
}

$asgExists = "$(Invoke-Aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $A2.Asg --query 'length(AutoScalingGroups)' --output text)".Trim() -eq '1'
Remove-A2 "Auto Scaling group $($A2.Asg)" $asgExists {
    $null = Invoke-Aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $A2.Asg --force-delete
    Wait-A2 { "$(Invoke-Aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $A2.Asg --query 'length(AutoScalingGroups)' --output text)".Trim() -eq '0' } 1200 'the Auto Scaling group to be deleted' 20
}
Remove-A2 "launch template $($A2.Lt)" (Test-Aws ec2 describe-launch-templates --launch-template-names $A2.Lt) {
    $null = Invoke-Aws ec2 delete-launch-template --launch-template-name $A2.Lt
}
$alb = Get-Alb
Remove-A2 "load balancer $($A2.Alb)" ($null -ne $alb) {
    $null = Invoke-Aws elbv2 delete-load-balancer --load-balancer-arn $alb.Arn
    & aws elbv2 wait load-balancers-deleted --load-balancer-arns $alb.Arn
}
$tg = Get-TgArn
Remove-A2 "target group $($A2.Tg)" ([bool]$tg) { Start-Sleep -Seconds 10; $null = Invoke-Aws elbv2 delete-target-group --target-group-arn $tg }
Remove-A2 "RDS instance $($A2.Db) (no final snapshot)" (Test-Aws rds describe-db-instances --db-instance-identifier $A2.Db) {
    $null = Invoke-Aws rds delete-db-instance --db-instance-identifier $A2.Db --skip-final-snapshot --delete-automated-backups
    & aws rds wait db-instance-deleted --db-instance-identifier $A2.Db
}
Remove-A2 "schedule $($A2.Schedule)" (Test-Aws scheduler get-schedule --name $A2.Schedule) { $null = Invoke-Aws scheduler delete-schedule --name $A2.Schedule }
Remove-A2 "IAM role $($A2.ScheduleRole)" (Test-Aws iam get-role --role-name $A2.ScheduleRole) {
    $null = Invoke-Aws iam delete-role-policy --role-name $A2.ScheduleRole --policy-name a2-stop-rds
    $null = Invoke-Aws iam delete-role --role-name $A2.ScheduleRole
}
foreach ($name in $A2.DemoName, $A2.RestoredName) {
    $instance = Get-A2Instance $name
    Remove-A2 "EC2 instance $name" ($null -ne $instance) {
        $null = Invoke-Aws ec2 terminate-instances --instance-ids $instance.Id
        & aws ec2 wait instance-terminated --instance-ids $instance.Id
    }
}
$alloc = "$(Invoke-Aws ec2 describe-addresses --filters "Name=tag:Name,Values=$($A2.DemoName)" --query 'Addresses[0].AllocationId' --output text)".Trim()
Remove-A2 'Elastic IP' ([bool]$alloc -and $alloc -ne 'None') { $null = Invoke-Aws ec2 release-address --allocation-id $alloc }
$images = "$(Invoke-Aws ec2 describe-images --owners self --filters 'Name=name,Values=a2-wordpress-*' --query 'Images[].ImageId' --output text)".Trim()
foreach ($img in ($images -split '\s+' | Where-Object { $_ -and $_ -ne 'None' })) {
    Remove-A2 "AMI $img and its snapshots" $true {
        $snaps = "$(Invoke-Aws ec2 describe-images --image-ids $img --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)".Trim() -split '\s+'
        $null = Invoke-Aws ec2 deregister-image --image-id $img
        foreach ($s in ($snaps | Where-Object { $_ -and $_ -ne 'None' })) { $null = Invoke-Aws ec2 delete-snapshot --snapshot-id $s }
    }
}
foreach ($bucket in $A2.BucketDeploy, $A2.BucketBackup) {
    Remove-A2 "S3 bucket $bucket and every object in it" (Test-Aws s3api head-bucket --bucket $bucket) { $null = Invoke-Aws s3 rb "s3://$bucket" --force }
}
Remove-A2 "CodeDeploy application $($A2.App)" (Test-Aws deploy get-application --application-name $A2.App) { $null = Invoke-Aws deploy delete-application --application-name $A2.App }
$params = "$(Invoke-Aws ssm describe-parameters --parameter-filters 'Key=Name,Option=BeginsWith,Values=/swe40006/' --query 'Parameters[].Name' --output text)".Trim()
Remove-A2 'SSM parameters under /swe40006/' ([bool]$params -and $params -ne 'None') { $null = Invoke-Aws ssm delete-parameters --names ($params -split '\s+') }
Remove-A2 "instance profile and role $($A2.InstanceRole)" (Test-Aws iam get-role --role-name $A2.InstanceRole) {
    if (Test-Aws iam get-instance-profile --instance-profile-name $A2.InstanceProfile) {
        & aws iam remove-role-from-instance-profile --instance-profile-name $A2.InstanceProfile --role-name $A2.InstanceRole *> $null
        $null = Invoke-Aws iam delete-instance-profile --instance-profile-name $A2.InstanceProfile
    }
    $null = Invoke-Aws iam delete-role-policy --role-name $A2.InstanceRole --policy-name CodeDeployDemo-EC2-Permissions
    $null = Invoke-Aws iam detach-role-policy --role-name $A2.InstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    $null = Invoke-Aws iam delete-role --role-name $A2.InstanceRole
}
Remove-A2 "IAM role $($A2.ServiceRole)" (Test-Aws iam get-role --role-name $A2.ServiceRole) {
    $null = Invoke-Aws iam detach-role-policy --role-name $A2.ServiceRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
    $null = Invoke-Aws iam delete-role --role-name $A2.ServiceRole
}
foreach ($name in $A2.SgDb, $A2.SgWeb, $A2.SgAlb, $A2.SgDemo) {
    $sg = Get-SgId $name
    Remove-A2 "security group $name" ([bool]$sg) {
        # Network interfaces of deleted load balancers and databases take a few minutes to disappear.
        Wait-A2 { Test-Aws ec2 delete-security-group --group-id $sg } 900 "security group $name to become deletable" 30
    }
}
Remove-A2 "key pair $($A2.KeyName) (the local .pem/.ppk files are kept)" (Test-Aws ec2 describe-key-pairs --key-names $A2.KeyName) {
    $null = Invoke-Aws ec2 delete-key-pair --key-name $A2.KeyName
}
if ($DryRun) { Write-Host 'Dry run only: nothing was deleted.' } else { Write-Host 'Teardown finished. Check Billing in a few days for any remaining charges.' }
