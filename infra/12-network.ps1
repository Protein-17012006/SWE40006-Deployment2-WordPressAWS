# Security groups for every tier (spec sections 2.3 and 2.4). Listing: 05-ec2-launch (first part).
param([string]$Listing = '05-ec2-launch')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2

function Get-OrCreateSg([string]$Name, [string]$Description) {
    $id = Get-SgId $Name
    if ($id) { Add-Listing "$Name exists: $id"; return $id }
    "$(Invoke-AwsShow ec2 create-security-group --group-name $Name --description $Description --vpc-id $script:Vpc --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$Name},{Key=Project,Value=$($A2.Project)}]" --query GroupId --output text)".Trim()
}

# Adds one inbound TCP rule unless the same port/source rule exists. Source is a CIDR or a security group ID.
function Add-Ingress([string]$GroupId, [int]$Port, [string]$Source, [string]$Note) {
    $rules = (Invoke-Aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$GroupId" --query 'SecurityGroupRules[?IsEgress==`false`].[FromPort,CidrIpv4,ReferencedGroupInfo.GroupId]' --output json) -join "`n" | ConvertFrom-Json
    foreach ($r in @($rules)) {
        if ($r[0] -eq $Port -and ($r[1] -eq $Source -or $r[2] -eq $Source)) { Add-Listing "rule exists: $GroupId tcp/$Port from $Source"; return }
    }
    if ($Source -like 'sg-*') { $perm = "IpProtocol=tcp,FromPort=$Port,ToPort=$Port,UserIdGroupPairs=[{GroupId=$Source,Description=$Note}]" }
    else { $perm = "IpProtocol=tcp,FromPort=$Port,ToPort=$Port,IpRanges=[{CidrIp=$Source,Description=$Note}]" }
    $null = Invoke-AwsShow ec2 authorize-security-group-ingress --group-id $GroupId --ip-permissions $perm --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text
}

try {
    $script:Vpc = Get-DefaultVpcId
    $me = "$($script:ClientIp)/32"
    Write-Step 'Security groups'
    $demo = Get-OrCreateSg $A2.SgDemo 'CodeDeployDemo - SSH from the student, HTTP from anywhere (CodeDeploy WordPress tutorial)'
    $alb = Get-OrCreateSg $A2.SgAlb 'a2-wordpress-alb - HTTP from the internet'
    $web = Get-OrCreateSg $A2.SgWeb 'WordPress web servers behind the load balancer'
    $db = Get-OrCreateSg $A2.SgDb 'a2-wordpress-db - MariaDB from the web tiers only'
    Write-Step 'Inbound rules'
    Add-Ingress $demo 22 $me 'ssh-student'
    Add-Ingress $demo 80 '0.0.0.0/0' 'http-tutorial'
    Add-Ingress $alb 80 '0.0.0.0/0' 'http-internet'
    Add-Ingress $web 80 $alb 'http-from-alb'
    Add-Ingress $web 22 $me 'ssh-student'
    Add-Ingress $web 22 $demo 'ssh-jump-host'
    Add-Ingress $db 3306 $demo 'mysql-codedeploydemo'
    Add-Ingress $db 3306 $web 'mysql-web'
    foreach ($id in $demo, $alb, $web, $db) {
        $null = Invoke-AwsShow ec2 describe-security-group-rules --filters "Name=group-id,Values=$id" --query 'SecurityGroupRules[?IsEgress==`false`].{Group:GroupId,Port:FromPort,Cidr:CidrIpv4,FromGroup:ReferencedGroupInfo.GroupId,Note:Description}' --output table
    }
} finally {
    Save-Listing $Listing
}
