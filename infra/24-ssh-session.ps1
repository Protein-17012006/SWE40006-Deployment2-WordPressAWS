# Task 2.4: text record of the command-line session on CodeDeployDemo (infra/remote/ssh-demo.sh). Listing: 19-ssh-session.
param([string]$Listing = '19-ssh-session')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
$ip = (Get-A2Instance $A2.DemoName).PublicIp
try {
    $rds = "$(Invoke-Aws rds describe-db-instances --db-instance-identifier $A2.Db --query 'DBInstances[0].Endpoint.Address' --output text)".Trim()
    Copy-ToRemote $ip @('infra\remote\ssh-demo.sh')
    Add-Listing "PS> ssh a2-codedeploy      # user ec2-user, key ~\.ssh\$($A2.KeyName).pem, host $ip"
    $null = Invoke-Remote $ip "bash a2/ssh-demo.sh $rds $($A2.BucketDeploy)" -Show
} finally {
    # Cleanup must never hide the error that stopped the script.
    if ($ip) { try { $null = Invoke-Remote $ip 'rm -rf ~/a2' } catch { Write-Host "cleanup of ~/a2 skipped: $($_.Exception.Message)" } }
    Save-Listing $Listing
}
