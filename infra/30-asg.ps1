# Task 2.3: launch template from the AMI restored from S3, Auto Scaling group behind the ALB, target tracking policy.
#   -Step create   launch template, group, policy; waits for 2 healthy instances   (run in the background)
#   -Step tidy     deregister CodeDeployDemo and a2-restored-from-s3, terminate the latter
# Listing: 15-launch-template-asg (appended)
param([ValidateSet('create', 'tidy')][string]$Step = 'create', [string]$Listing = '15-launch-template-asg')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    $tg = Get-TgArn
    if ($Step -eq 'create') {
        Write-Step "Launch template $($A2.Lt)"
        if (Test-Aws ec2 describe-launch-templates --launch-template-names $A2.Lt) { Add-Listing "$($A2.Lt) exists" }
        else {
            $restored = "$(Invoke-Aws ec2 describe-images --owners self --filters "Name=name,Values=$($A2.RestoredAmi)" --query 'Images[0].ImageId' --output text)".Trim()
            if ($restored -eq 'None' -or -not $restored) { throw 'the restored AMI does not exist: run infra\23-ami-s3-backup.ps1 first' }
            $data = Expand-A2Template 'lt-data.json' @{ '__IMAGE_ID__' = $restored; '__WEB_SG__' = (Get-SgId $A2.SgWeb) }
            $null = Invoke-AwsShow ec2 create-launch-template --launch-template-name $A2.Lt --version-description 'WordPress AMI restored from the S3 backup' --launch-template-data $data --tag-specifications "ResourceType=launch-template,Tags=[{Key=Project,Value=$($A2.Project)}]" --query 'LaunchTemplate.[LaunchTemplateId,LatestVersionNumber]' --output text
        }
        $null = Invoke-AwsShow ec2 describe-launch-template-versions --launch-template-name $A2.Lt --versions '$Default' --query 'LaunchTemplateVersions[0].LaunchTemplateData.{Ami:ImageId,Type:InstanceType,Key:KeyName,Profile:IamInstanceProfile.Name,IMDS:MetadataOptions.HttpTokens,DetailedMonitoring:Monitoring.Enabled}' --output table

        Write-Step "Auto Scaling group $($A2.Asg)"
        $exists = "$(Invoke-Aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $A2.Asg --query 'length(AutoScalingGroups)' --output text)".Trim() -eq '1'
        if ($exists) { Add-Listing "$($A2.Asg) exists" }
        else {
            $null = Invoke-AwsShow autoscaling create-auto-scaling-group --auto-scaling-group-name $A2.Asg --launch-template "LaunchTemplateName=$($A2.Lt),Version=`$Default" --min-size 2 --max-size 4 --desired-capacity 2 --vpc-zone-identifier "$(Get-SubnetId $A2.AzA),$(Get-SubnetId $A2.AzB)" --target-group-arns $tg --health-check-type ELB --health-check-grace-period 300 --default-instance-warmup 120 --tags "Key=Project,Value=$($A2.Project),PropagateAtLaunch=true"
        }
        $null = Invoke-AwsShow autoscaling enable-metrics-collection --auto-scaling-group-name $A2.Asg --granularity 1Minute
        $null = Invoke-AwsShow autoscaling put-scaling-policy --auto-scaling-group-name $A2.Asg --policy-name $A2.Policy --policy-type TargetTrackingScaling --target-tracking-configuration file://infra/policies/cpu50-target-tracking.json --query 'Alarms[].AlarmName' --output text
        Wait-A2 { $ids = Get-AsgInstanceIds; ($ids.Count -ge 2) -and ((Get-HealthyTargetCount -InstanceIds $ids) -ge 2) } 1200 '2 healthy instances from the Auto Scaling group' 20
        $null = Invoke-AwsShow autoscaling describe-auto-scaling-groups --auto-scaling-group-names $A2.Asg --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,HealthCheck:HealthCheckType,Grace:HealthCheckGracePeriod}' --output table
        $null = Invoke-AwsShow autoscaling describe-auto-scaling-instances --query "AutoScalingInstances[?AutoScalingGroupName=='$($A2.Asg)'].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]" --output table
        $null = Invoke-AwsShow elbv2 describe-target-health --target-group-arn $tg --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
    }
    if ($Step -eq 'tidy') {
        Write-Step 'The load balancer now serves only the Auto Scaling group'
        foreach ($name in $A2.DemoName, $A2.RestoredName) {
            $i = Get-A2Instance $name
            if ($i) { $null = Invoke-AwsShow elbv2 deregister-targets --target-group-arn $tg --targets "Id=$($i.Id)" }
        }
        $restoredInstance = Get-A2Instance $A2.RestoredName
        if ($restoredInstance) { $null = Invoke-AwsShow ec2 terminate-instances --instance-ids $restoredInstance.Id --query 'TerminatingInstances[0].[InstanceId,CurrentState.Name]' --output text }
        Start-Sleep -Seconds 40
        $null = Invoke-AwsShow elbv2 describe-target-health --target-group-arn $tg --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
    }
} finally {
    Save-Listing $Listing -Append
}
