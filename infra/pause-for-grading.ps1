# Pauses the environment between submission and grading (spec section 9). About 10 minutes.
# Listing: 20-pause-resume (appended).
param([string]$Listing = '20-pause-resume')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    Add-Listing "=== PAUSE $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
    Write-Step 'Auto Scaling group to zero instances'
    $null = Invoke-AwsShow autoscaling update-auto-scaling-group --auto-scaling-group-name $A2.Asg --min-size 0 --desired-capacity 0
    Wait-A2 { (Get-AsgInstanceIds).Count -eq 0 } 1200 'the Auto Scaling group to terminate its instances' 20
    Add-Listing 'Auto Scaling group: 0 instances'

    Write-Step 'Stop CodeDeployDemo (its Elastic IP stays associated)'
    $demo = Get-A2Instance $A2.DemoName
    if ($demo.State -ne 'stopped') {
        $null = Invoke-AwsShow ec2 stop-instances --instance-ids $demo.Id --query 'StoppingInstances[0].CurrentState.Name' --output text
        & aws ec2 wait instance-stopped --instance-ids $demo.Id
    }

    Write-Step 'Stop the RDS instance'
    $status = "$(Invoke-Aws rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].DBInstanceStatus' --output text)".Trim()
    if ($status -eq 'available') { $null = Invoke-AwsShow rds stop-db-instance --db-instance-identifier $A2.Db --query 'DBInstance.DBInstanceStatus' --output text }

    Write-Step 'Daily schedule that stops RDS again if AWS restarts it after 7 days'
    if (-not (Test-Aws iam get-role --role-name $A2.ScheduleRole)) {
        $null = Invoke-AwsShow iam create-role --role-name $A2.ScheduleRole --assume-role-policy-document (Expand-A2Template 'scheduler-trust.json') --query 'Role.Arn' --output text
        $null = Invoke-AwsShow iam put-role-policy --role-name $A2.ScheduleRole --policy-name a2-stop-rds --policy-document (Expand-A2Template 'scheduler-permissions.json')
        Start-Sleep -Seconds 15
    }
    if (-not (Test-Aws scheduler get-schedule --name $A2.Schedule)) {
        $null = Invoke-AwsShow scheduler create-schedule --name $A2.Schedule --schedule-expression 'cron(0 18 * * ? *)' --schedule-expression-timezone UTC --flexible-time-window Mode=OFF --target (Expand-A2Template 'schedule-target.json') --query ScheduleArn --output text
    }

    Write-Step 'The load balancer answers with a "paused" page'
    $alb = Get-Alb
    $null = Invoke-AwsShow elbv2 modify-listener --listener-arn (Get-ListenerArn $alb.Arn) --default-actions file://infra/policies/listener-paused.json --query 'Listeners[0].DefaultActions[0].Type' --output text

    Wait-A2 { "$(Invoke-Aws rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].DBInstanceStatus' --output text)".Trim() -eq 'stopped' } 1500 'RDS to stop' 30
    $null = Invoke-AwsShow rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].DBInstanceStatus' --output text
    $null = Invoke-AwsShow ec2 describe-instances --instance-ids $demo.Id --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' --output text
    Add-Listing "PS> curl.exe -s -o NUL -w '%{http_code}' http://$($alb.Dns)/WordPress/"
    Add-Listing ([string](& curl.exe -s -o NUL -w '%{http_code}' "http://$($alb.Dns)/WordPress/"))
} finally {
    Save-Listing $Listing -Append
}
