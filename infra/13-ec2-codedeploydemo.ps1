# EC2 instance for CodeDeploy ("Create an Amazon EC2 instance for CodeDeploy (AWS CLI)") plus an Elastic IP.
# Listing: 05-ec2-launch (appended after the security groups).
param([string]$Listing = '05-ec2-launch')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    $instance = Get-A2Instance $A2.DemoName
    if ($instance) { Add-Listing "$($A2.DemoName) exists: $($instance.Id) ($($instance.State))"; $id = $instance.Id }
    else {
        Write-Step 'Launch CodeDeployDemo (Amazon Linux 2023, t3.micro, instance profile, tag Name=CodeDeployDemo)'
        $ami = "$(Invoke-AwsShow ssm get-parameters --names $A2.AmiParameter --query 'Parameters[0].Value' --output text)".Trim()
        $id = "$(Invoke-AwsShow ec2 run-instances --image-id $ami --instance-type $A2.InstanceType --key-name $A2.KeyName --subnet-id (Get-SubnetId $A2.AzA) --security-group-ids (Get-SgId $A2.SgDemo) --iam-instance-profile "Name=$($A2.InstanceProfile)" --metadata-options 'HttpTokens=required,HttpEndpoint=enabled' --user-data file://infra/user-data/install-codedeploy-agent.sh --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$($A2.DemoName)},{Key=Project,Value=$($A2.Project)}]" "ResourceType=volume,Tags=[{Key=Name,Value=$($A2.DemoName)},{Key=Project,Value=$($A2.Project)}]" --count 1 --query 'Instances[0].InstanceId' --output text)".Trim()
    }

    Write-Step 'Wait until the instance passes both status checks'
    Add-Listing "PS> aws ec2 wait instance-status-ok --instance-ids $id"
    & aws ec2 wait instance-status-ok --instance-ids $id
    if ($LASTEXITCODE -ne 0) { throw 'the instance did not reach status ok' }
    $null = Invoke-AwsShow ec2 describe-instance-status --instance-ids $id --query 'InstanceStatuses[*].InstanceStatus.[Status]' --output text

    Write-Step 'Elastic IP (keeps the public address across stop/start)'
    $alloc = "$(Invoke-Aws ec2 describe-addresses --filters "Name=tag:Name,Values=$($A2.DemoName)" --query 'Addresses[0].AllocationId' --output text)".Trim()
    if ($alloc -eq 'None' -or -not $alloc) {
        $alloc = "$(Invoke-AwsShow ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$($A2.DemoName)},{Key=Project,Value=$($A2.Project)}]" --query AllocationId --output text)".Trim()
    }
    $null = Invoke-AwsShow ec2 associate-address --instance-id $id --allocation-id $alloc --query AssociationId --output text
    $null = Invoke-AwsShow ec2 describe-instances --instance-ids $id --query 'Reservations[0].Instances[0].{Id:InstanceId,Ami:ImageId,Type:InstanceType,Az:Placement.AvailabilityZone,PublicIp:PublicIpAddress,Profile:IamInstanceProfile.Arn,IMDSv2:MetadataOptions.HttpTokens,State:State.Name}' --output table
    $ip = "$(Invoke-Aws ec2 describe-instances --instance-ids $id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)".Trim()

    Write-Step 'CodeDeploy agent installed by the user data'
    $null = Invoke-Remote $ip 'cloud-init status --wait >/dev/null; head -2 /etc/os-release; systemctl is-active codedeploy-agent; rpm -q codedeploy-agent' -Show
    Add-Listing "Task 2.1 public URL: http://$ip/WordPress/"
} finally {
    Save-Listing $Listing -Append
}
