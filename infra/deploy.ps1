# Deploys the uploaded revision to CodeDeployDemo in place, running its appspec hooks in CodeDeploy's lifecycle
# order (tutorial Step 4). AWS CodeDeploy itself is not available on this AWS Free-plan account
# (docs/error-log.md #3), so infra/remote/deploy-revision.sh does the agent's work, started over SSH.
#   -SiteUrl / -DbHost first update those (non-secret) parameters. The description must not contain quotes.
param(
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string]$Listing,
    [string]$SiteUrl = '',
    [string]$DbHost = ''
)
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
if ($Description -match "['`"]") { throw 'The description must not contain quotes' }
$ip = (Get-A2Instance $A2.DemoName).PublicIp
try {
    if ($SiteUrl) { $null = Invoke-AwsShow ssm put-parameter --name "$($A2.ParamPrefix)/site_url" --type String --value $SiteUrl --overwrite --query Version --output text }
    if ($DbHost) { $null = Invoke-AwsShow ssm put-parameter --name "$($A2.ParamPrefix)/db_host" --type String --value $DbHost --overwrite --query Version --output text }

    Write-Step $Description
    Copy-ToRemote $ip @('infra\remote\deploy-revision.sh')
    $null = Invoke-Remote $ip "sudo bash a2/deploy-revision.sh s3://$($A2.BucketDeploy)/$($A2.RevisionKey) '$Description'" -Show
    $null = Invoke-Remote $ip 'tail -n 5 /opt/a2-deploy/history.log' -Show
    $null = Invoke-Remote $ip "systemctl is-active httpd php-fpm; systemctl is-active mariadb || true; curl -s http://localhost/WordPress/ | grep -o -m1 'Served by[^<]*' || echo '(no footer yet: WordPress is not installed)'" -Show
} finally {
    # Cleanup must never hide the error that stopped the script.
    if ($ip) { try { $null = Invoke-Remote $ip 'rm -rf ~/a2' } catch { Write-Host "cleanup of ~/a2 skipped: $($_.Exception.Message)" } }
    Save-Listing $Listing -Append
}
