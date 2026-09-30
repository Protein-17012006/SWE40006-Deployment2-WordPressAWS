# Task 2.3 scaling tests (spec section 7).
#   -Test manual         desired 3, then back to 2                                   (run in the background)
#   -Test dynamic-start  20 minutes of CPU load on every ASG instance
#   -Test dynamic-watch  -Target 4|2 [-Minutes 8]: one line per minute until the group has -Target instances
#   -Test selfheal       terminate one instance and wait for its replacement         (run in the background)
# Listings: 16-scaling-manual, 17-scaling-dynamic (appended), 18-scaling-self-healing
param([Parameter(Mandatory = $true)][ValidateSet('manual', 'dynamic-start', 'dynamic-watch', 'selfheal')][string]$Test,
      [int]$Target = 4, [int]$Minutes = 8)
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2

function Get-AsgState {
    (Invoke-Aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $A2.Asg --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[].{Id:InstanceId,State:LifecycleState}}' --output json) -join "`n" | ConvertFrom-Json
}
function Get-InServiceIds($State) { @($State.Instances | Where-Object { $_.State -eq 'InService' } | ForEach-Object { $_.Id }) }
function Get-AlarmState([string]$Kind) {
    "$(Invoke-Aws cloudwatch describe-alarms --alarm-name-prefix "TargetTracking-$($A2.Asg)-$Kind" --query 'MetricAlarms[0].StateValue' --output text)".Trim()
}
function Get-AsgCpu {
    $end = (Get-Date).ToUniversalTime()
    $v = "$(Invoke-Aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions "Name=AutoScalingGroupName,Value=$($A2.Asg)" --start-time ($end.AddMinutes(-5).ToString('s') + 'Z') --end-time ($end.ToString('s') + 'Z') --period 60 --statistics Average --query 'sort_by(Datapoints, &Timestamp)[-1].Average' --output text)".Trim()
    if ($v -eq 'None' -or -not $v) { 'n/a' } else { '{0:N0}%' -f [double]$v }
}
function Show-AsgState([string]$Label) {
    $s = Get-AsgState
    $ids = Get-InServiceIds $s
    Add-Listing ("{0}  {1}: desired={2} in-service={3} healthy-targets={4} cpu={5}" -f (Get-Date -Format 'HH:mm:ss'), $Label, $s.Desired, $ids.Count, (Get-HealthyTargetCount -InstanceIds $ids), (Get-AsgCpu))
}
function Wait-Capacity([int]$Count) {
    Wait-A2 {
        $s = Get-AsgState
        $ids = Get-InServiceIds $s
        ($s.Instances.Count -eq $Count) -and ($ids.Count -eq $Count) -and ((Get-HealthyTargetCount -InstanceIds $ids) -eq $Count)
    } 1200 "$Count in-service, healthy instances" 20
}
function Show-Activities([int]$Max) {
    $null = Invoke-AwsShow autoscaling describe-scaling-activities --auto-scaling-group-name $A2.Asg --max-items $Max --query 'Activities[].[StartTime,StatusCode,Description]' --output table
}

switch ($Test) {
    'manual' {
        try {
            Show-AsgState 'before'
            $null = Invoke-AwsShow autoscaling set-desired-capacity --auto-scaling-group-name $A2.Asg --desired-capacity 3
            Wait-Capacity 3
            Show-AsgState 'after set-desired-capacity 3'
            $null = Invoke-AwsShow autoscaling set-desired-capacity --auto-scaling-group-name $A2.Asg --desired-capacity 2
            Wait-Capacity 2
            Show-AsgState 'after set-desired-capacity 2'
            Show-Activities 4
        } finally { Save-Listing '16-scaling-manual' }
    }
    'dynamic-start' {
        try {
            Show-AsgState 'before the load'
            foreach ($id in Get-AsgInstanceIds) {
                $ip = "$(Invoke-Aws ec2 describe-instances --instance-ids $id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)".Trim()
                Copy-ToRemote $ip @('infra\remote\stress.sh')
                $null = Invoke-Remote $ip 'bash a2/stress.sh 20' -Show
            }
        } finally { Save-Listing '17-scaling-dynamic' }
    }
    'dynamic-watch' {
        $reached = $false
        try {
            $deadline = (Get-Date).AddMinutes($Minutes)
            while ((Get-Date) -lt $deadline) {
                $s = Get-AsgState
                $ids = Get-InServiceIds $s
                $healthy = Get-HealthyTargetCount -InstanceIds $ids
                Add-Listing ("{0}  desired={1} in-service={2} healthy={3} cpu={4} AlarmHigh={5} AlarmLow={6}" -f (Get-Date -Format 'HH:mm:ss'), $s.Desired, $ids.Count, $healthy, (Get-AsgCpu), (Get-AlarmState 'AlarmHigh'), (Get-AlarmState 'AlarmLow'))
                if ($s.Desired -eq $Target -and $s.Instances.Count -eq $Target -and $ids.Count -eq $Target -and $healthy -eq $Target) { $reached = $true; break }
                Start-Sleep -Seconds 60
            }
            if ($reached) { Add-Listing "The group reached $Target in-service, healthy instances"; Show-Activities 6 }
        } finally { Save-Listing '17-scaling-dynamic' -Append }
        if (-not $reached) { Write-Host "Not at $Target instances yet: run  -Test dynamic-watch -Target $Target  again"; exit 3 }
    }
    'selfheal' {
        try {
            Show-AsgState 'before'
            $victim = (Get-InServiceIds (Get-AsgState))[0]
            $null = Invoke-AwsShow ec2 terminate-instances --instance-ids $victim --query 'TerminatingInstances[0].[InstanceId,CurrentState.Name]' --output text
            Wait-A2 {
                $ids = Get-InServiceIds (Get-AsgState)
                ($ids.Count -eq 2) -and ($victim -notin $ids) -and ((Get-HealthyTargetCount -InstanceIds $ids) -eq 2)
            } 1200 'a healthy replacement instance' 20
            Show-AsgState 'after the replacement'
            Show-Activities 3
        } finally { Save-Listing '18-scaling-self-healing' }
    }
}
