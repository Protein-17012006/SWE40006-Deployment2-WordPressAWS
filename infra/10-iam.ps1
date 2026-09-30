# CodeDeploy service role and EC2 instance profile (CodeDeploy Getting Started, steps 2 and 4). Listing: 03-iam-roles.
param([string]$Listing = '03-iam-roles')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    Write-Step "Service role $($A2.ServiceRole)"
    if (Test-Aws iam get-role --role-name $A2.ServiceRole) { Add-Listing "$($A2.ServiceRole) exists" }
    else { $null = Invoke-AwsShow iam create-role --role-name $A2.ServiceRole --assume-role-policy-document file://infra/policies/codedeploy-trust.json --query 'Role.Arn' --output text }
    $null = Invoke-AwsShow iam attach-role-policy --role-name $A2.ServiceRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
    $null = Invoke-AwsShow iam get-role --role-name $A2.ServiceRole --query 'Role.Arn' --output text

    Write-Step "EC2 role and instance profile $($A2.InstanceProfile)"
    if (Test-Aws iam get-role --role-name $A2.InstanceRole) { Add-Listing "$($A2.InstanceRole) role exists" }
    else { $null = Invoke-AwsShow iam create-role --role-name $A2.InstanceRole --assume-role-policy-document file://infra/policies/ec2-trust.json --query 'Role.Arn' --output text }
    $null = Invoke-AwsShow iam put-role-policy --role-name $A2.InstanceRole --policy-name CodeDeployDemo-EC2-Permissions --policy-document (Expand-A2Template 'ec2-permissions.json')
    $null = Invoke-AwsShow iam attach-role-policy --role-name $A2.InstanceRole --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    if (Test-Aws iam get-instance-profile --instance-profile-name $A2.InstanceProfile) { Add-Listing "$($A2.InstanceProfile) instance profile exists" }
    else {
        $null = Invoke-AwsShow iam create-instance-profile --instance-profile-name $A2.InstanceProfile --query 'InstanceProfile.Arn' --output text
        $null = Invoke-AwsShow iam add-role-to-instance-profile --instance-profile-name $A2.InstanceProfile --role-name $A2.InstanceRole
        Write-Host 'Waiting 15 s for the new instance profile to propagate'
        Start-Sleep -Seconds 15
    }
    $null = Invoke-AwsShow iam list-attached-role-policies --role-name $A2.InstanceRole --query 'AttachedPolicies[].PolicyName' --output text
    $null = Invoke-AwsShow iam list-role-policies --role-name $A2.InstanceRole --query 'PolicyNames' --output text
    $null = Invoke-AwsShow iam list-instance-profiles-for-role --role-name $A2.InstanceRole --query 'InstanceProfiles[].InstanceProfileName' --output text
} finally {
    Save-Listing $Listing
}
