# Points the SSH rules (description "ssh-student") at this machine's current public IP, e.g. after the home IP changed.
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
$current = "$($script:ClientIp)/32"
foreach ($name in $A2.SgDemo, $A2.SgWeb) {
    $sg = Get-SgId $name
    if (-not $sg) { continue }
    $rules = (Invoke-Aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" --query 'SecurityGroupRules[?Description==`ssh-student`].[SecurityGroupRuleId,CidrIpv4]' --output json) -join "`n" | ConvertFrom-Json
    $present = $false
    foreach ($r in @($rules)) {
        if ($r[1] -eq $current) { $present = $true }
        else { $null = Invoke-AwsShow ec2 revoke-security-group-ingress --group-id $sg --security-group-rule-ids $r[0] }
    }
    if (-not $present) {
        $null = Invoke-AwsShow ec2 authorize-security-group-ingress --group-id $sg --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$current,Description=ssh-student}]" --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text
    }
    Write-Host "$($name): SSH allowed from this machine's current public IP"
}
