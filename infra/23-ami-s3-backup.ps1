# Task 2.2: back the instance up to S3 as an AMI object and launch a new instance from it
# (EC2 "Store and restore an AMI using S3"; these APIs are CLI-only). Steps can be re-run one at a time:
#   -Step image | store | delete-source | restore | launch | all       Listing: 14-ami-s3-backup-restore (appended)
param([ValidateSet('image', 'store', 'delete-source', 'restore', 'launch', 'all')][string]$Step = 'all',
      [string]$Listing = '14-ami-s3-backup-restore')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2

function Get-GoldenAmi {
    "$(Invoke-Aws ec2 describe-images --owners self --filters "Name=name,Values=$($A2.GoldenPrefix)*" --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)".Trim() -replace '^None$', ''
}
function Get-RestoredAmi {
    "$(Invoke-Aws ec2 describe-images --owners self --filters "Name=name,Values=$($A2.RestoredAmi)" --query 'Images[0].ImageId' --output text)".Trim() -replace '^None$', ''
}
function Get-BackupObjectKey {
    "$(Invoke-Aws s3api list-objects-v2 --bucket $A2.BucketBackup --query "Contents[?ends_with(Key, '.bin')].Key | [-1]" --output text)".Trim() -replace '^None$', ''
}
function Wait-ImageAvailable([string]$ImageId) {
    Add-Listing "PS> aws ec2 wait image-available --image-ids $ImageId"
    Wait-A2 { "$(Invoke-Aws ec2 describe-images --image-ids $ImageId --query 'Images[0].State' --output text)".Trim() -eq 'available' } 3600 "AMI $ImageId" 30
}

$script:lastProgress = ''
try {
    $demo = Get-A2Instance $A2.DemoName
    if ($Step -in 'image', 'all') {
        Write-Step 'AMI of CodeDeployDemo (WordPress configured for RDS)'
        $null = Invoke-Remote $demo.PublicIp 'test ! -e ~/a2 && echo no migration files are left in the home directory' -Show
        $ami = "$(Invoke-AwsShow ec2 create-image --instance-id $demo.Id --name ($A2.GoldenPrefix + (Get-Date -Format 'yyyyMMdd-HHmm')) --description 'CodeDeployDemo after deploy 4: WordPress on Amazon RDS' --tag-specifications "ResourceType=image,Tags=[{Key=Project,Value=$($A2.Project)}]" "ResourceType=snapshot,Tags=[{Key=Project,Value=$($A2.Project)}]" --query ImageId --output text)".Trim()
        Wait-ImageAvailable $ami
        $null = Invoke-AwsShow ec2 describe-images --image-ids $ami --query 'Images[0].{Id:ImageId,Name:Name,State:State,BootMode:BootMode,Snapshot:BlockDeviceMappings[0].Ebs.SnapshotId,SizeGiB:BlockDeviceMappings[0].Ebs.VolumeSize}' --output table
    }
    if ($Step -in 'store', 'all') {
        Write-Step 'Store the AMI in S3 as a single object (CreateStoreImageTask)'
        $ami = Get-GoldenAmi
        if (-not $ami) { throw 'no golden AMI to store' }
        if (Get-BackupObjectKey) { Add-Listing "an .bin object already exists in $($A2.BucketBackup)" }
        else { $null = Invoke-AwsShow ec2 create-store-image-task --image-id $ami --bucket $A2.BucketBackup --query ObjectKey --output text }
        Wait-A2 {
            $r = "$(Invoke-Aws ec2 describe-store-image-tasks --image-ids $ami --query 'StoreImageTaskResults[0].[StoreTaskState,ProgressPercentage,StoreTaskFailureReason]' --output text)".Trim()
            if ($r -ne $script:lastProgress) { Add-Listing ("{0}  StoreTaskState/ProgressPercentage: {1}" -f (Get-Date -Format 'HH:mm:ss'), $r); $script:lastProgress = $r }
            if ($r -like 'Failed*') { throw "store task failed: $r" }
            $r -like 'Completed*'
        } 3600 'the store task' 30
        $null = Invoke-AwsShow s3 ls "s3://$($A2.BucketBackup)/" --recursive --human-readable
    }
    if ($Step -in 'delete-source', 'all') {
        Write-Step 'Delete the source AMI and its snapshot, so the restore can only use the S3 object'
        $ami = Get-GoldenAmi
        if ($ami) {
            if (-not (Get-BackupObjectKey)) { throw 'no .bin object in the backup bucket: refusing to delete the source AMI' }
            $snap = "$(Invoke-Aws ec2 describe-images --image-ids $ami --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)".Trim()
            $null = Invoke-AwsShow ec2 deregister-image --image-id $ami
            $null = Invoke-AwsShow ec2 delete-snapshot --snapshot-id $snap
        }
        $null = Invoke-AwsShow ec2 describe-images --owners self --query 'Images[].[ImageId,Name,State]' --output table
    }
    if ($Step -in 'restore', 'all') {
        Write-Step 'Restore a new AMI from the S3 object (CreateRestoreImageTask)'
        $restored = Get-RestoredAmi
        if (-not $restored) {
            $key = Get-BackupObjectKey
            if (-not $key) { throw 'no .bin object to restore from' }
            $restored = "$(Invoke-AwsShow ec2 create-restore-image-task --object-key $key --bucket $A2.BucketBackup --name $A2.RestoredAmi --tag-specifications "ResourceType=image,Tags=[{Key=Project,Value=$($A2.Project)}]" "ResourceType=snapshot,Tags=[{Key=Project,Value=$($A2.Project)}]" --query ImageId --output text)".Trim()
        }
        Wait-ImageAvailable $restored
        $null = Invoke-AwsShow ec2 describe-images --image-ids $restored --query 'Images[0].{Id:ImageId,Name:Name,State:State,Created:CreationDate,BootMode:BootMode,Snapshot:BlockDeviceMappings[0].Ebs.SnapshotId}' --output table
    }
    if ($Step -in 'launch', 'all') {
        Write-Step 'Launch an instance from the restored AMI and put it behind the load balancer'
        $restored = Get-RestoredAmi
        $instance = Get-A2Instance $A2.RestoredName
        if ($instance) { $id = $instance.Id; Add-Listing "$($A2.RestoredName) exists: $id" }
        else {
            $id = "$(Invoke-AwsShow ec2 run-instances --image-id $restored --instance-type $A2.InstanceType --key-name $A2.KeyName --subnet-id (Get-SubnetId $A2.AzB) --security-group-ids (Get-SgId $A2.SgWeb) --iam-instance-profile "Name=$($A2.InstanceProfile)" --metadata-options 'HttpTokens=required,HttpEndpoint=enabled' --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$($A2.RestoredName)},{Key=Project,Value=$($A2.Project)}]" --count 1 --query 'Instances[0].InstanceId' --output text)".Trim()
        }
        Add-Listing "PS> aws ec2 wait instance-status-ok --instance-ids $id"
        & aws ec2 wait instance-status-ok --instance-ids $id
        if ($LASTEXITCODE -ne 0) { throw 'the restored instance did not reach status ok' }
        $tg = Get-TgArn
        $null = Invoke-AwsShow elbv2 register-targets --target-group-arn $tg --targets "Id=$id"
        Add-Listing "PS> aws elbv2 wait target-in-service --target-group-arn <$($A2.Tg) ARN> --targets Id=$id"
        & aws elbv2 wait target-in-service --target-group-arn $tg --targets "Id=$id"
        if ($LASTEXITCODE -ne 0) { throw 'the restored instance did not become healthy' }
        $null = Invoke-AwsShow ec2 describe-instances --instance-ids $id --query 'Reservations[0].Instances[0].{Id:InstanceId,Ami:ImageId,Az:Placement.AvailabilityZone,PrivateIp:PrivateIpAddress,State:State.Name}' --output table
        $null = Invoke-AwsShow elbv2 describe-target-health --target-group-arn $tg --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
    }
} finally {
    Save-Listing $Listing -Append
}
