# Starts everything again for grading (about 15 minutes), then checks both public URLs.
# Run it after  aws login --profile swe40006-a2 . Listing: 20-pause-resume (appended).
param([string]$Listing = '20-pause-resume')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
$failed = $false
try {
    Add-Listing "=== RESUME $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
    Write-Step 'Remove the daily RDS stop schedule'
    if (Test-Aws scheduler get-schedule --name $A2.Schedule) { $null = Invoke-AwsShow scheduler delete-schedule --name $A2.Schedule }

    Write-Step 'Start RDS'
    Wait-A2 { "$(Invoke-Aws rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].DBInstanceStatus' --output text)".Trim() -in 'stopped', 'available' } 1500 'RDS to be stopped or available' 30
    $status = "$(Invoke-Aws rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].DBInstanceStatus' --output text)".Trim()
    if ($status -eq 'stopped') { $null = Invoke-AwsShow rds start-db-instance --db-instance-identifier $A2.Db --query 'DBInstance.DBInstanceStatus' --output text }
    Add-Listing "PS> aws rds wait db-instance-available --db-instance-identifier $($A2.Db)"
    & aws rds wait db-instance-available --db-instance-identifier $A2.Db
    if ($LASTEXITCODE -ne 0) { throw 'RDS did not become available' }

    Write-Step 'Start CodeDeployDemo'
    $demo = Get-A2Instance $A2.DemoName
    if ($demo.State -eq 'stopped') { $null = Invoke-AwsShow ec2 start-instances --instance-ids $demo.Id --query 'StartingInstances[0].CurrentState.Name' --output text }
    & aws ec2 wait instance-status-ok --instance-ids $demo.Id
    $eip = (Get-A2Instance $A2.DemoName).PublicIp

    Write-Step 'Auto Scaling group back to 2 instances'
    $null = Invoke-AwsShow autoscaling update-auto-scaling-group --auto-scaling-group-name $A2.Asg --min-size 2 --desired-capacity 2

    # The forward action goes back first: a target group that no listener uses is never health-checked,
    # so its targets stay "unused" and would never become healthy (docs/error-log.md #6).
    Write-Step 'The load balancer forwards to WordPress again'
    $alb = Get-Alb
    $null = Invoke-AwsShow elbv2 modify-listener --listener-arn (Get-ListenerArn $alb.Arn) --default-actions "Type=forward,TargetGroupArn=$(Get-TgArn)" --query 'Listeners[0].DefaultActions[0].Type' --output text
    Wait-A2 { $ids = Get-AsgInstanceIds; ($ids.Count -ge 2) -and ((Get-HealthyTargetCount -InstanceIds $ids) -ge 2) } 1500 '2 healthy instances behind the load balancer' 20

    Write-Step 'Smoke tests'
    foreach ($check in @(@("http://$($alb.Dns)/", '301'), @("http://$($alb.Dns)/WordPress/", '200'), @("http://$eip/WordPress/", '200'))) {
        $code = "$(& curl.exe -s -o NUL -w '%{http_code}' $check[0])".Trim()
        Add-Listing "$($check[0]) -> HTTP $code (expected $($check[1]))"
        if ($code -ne $check[1]) { $failed = $true }
    }
    $footer = [regex]::Match(((& curl.exe -s "http://$($alb.Dns)/WordPress/") -join "`n"), 'Served by[^<]*').Value
    Add-Listing "Footer through the load balancer: $footer"
    Add-Listing "READY FOR GRADING:  http://$($alb.Dns)/   and   http://$eip/WordPress/"
} finally {
    Save-Listing $Listing -Append
}
if ($failed) { throw 'A smoke test did not return the expected HTTP status (see above)' }
