# Helpers shared by the infra scripts. Dot-source after config.ps1:
#   . "$PSScriptRoot\config.ps1"; . "$PSScriptRoot\lib.ps1"; Initialize-A2
# Native aws/ssh failures are detected through $LASTEXITCODE, so PowerShell errors are not escalated here.
$ErrorActionPreference = 'Continue'
# Windows PowerShell 5.1 downloads (Invoke-WebRequest) are many times slower while the progress bar is drawn.
$ProgressPreference = 'SilentlyContinue'
$script:ListingLines = New-Object System.Collections.Generic.List[string]
$script:Redactions = New-Object System.Collections.Generic.List[string]
$script:AccountId = ''
$script:ClientIp = ''

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Initialize-A2 {
    Set-Location $A2.Root
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:AWS_PROFILE = $A2.Profile
    $env:AWS_REGION = $A2.Region
    $env:AWS_PAGER = ''
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    New-Item -ItemType Directory -Force -Path $A2.Build, $A2.Listings | Out-Null
    $id = & aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) { throw 'AWS session missing or expired: ask the student to run  aws login --profile swe40006-a2' }
    $script:AccountId = "$id".Trim()
    $script:ClientIp = "$(Invoke-RestMethod -Uri 'https://checkip.amazonaws.com' -TimeoutSec 20)".Trim()
    $secrets = Get-A2Secrets
    if ($secrets) { Add-SecretRedactions $secrets }
}

function Add-SecretRedactions($Secrets) {
    Add-Redaction $Secrets.dbPassword
    Add-Redaction $Secrets.rdsMasterPassword
    foreach ($m in [regex]::Matches("$($Secrets.authSalts)", "'([A-Za-z0-9]{64})'")) { Add-Redaction $m.Groups[1].Value }
}

function Add-Redaction([string]$Value) {
    if ($Value -and -not $script:Redactions.Contains($Value)) { $script:Redactions.Add($Value) }
}

# Masks secrets, the account ID and the client IP in anything shown on screen or saved as a listing.
function Protect-Text([string]$Text) {
    foreach ($secret in $script:Redactions) { $Text = $Text.Replace($secret, '********') }
    if ($script:AccountId) { $Text = $Text.Replace($script:AccountId, '************') }
    if ($script:ClientIp) { $Text = $Text.Replace($script:ClientIp, 'x.x.x.x') }
    $Text
}

function Add-Listing([string[]]$Lines) {
    foreach ($line in $Lines) {
        $safe = Protect-Text "$line"
        $script:ListingLines.Add($safe)
        Write-Host $safe
    }
}

function Save-Listing([string]$Name, [switch]$Append) {
    $path = Join-Path $A2.Listings "$Name.txt"
    $text = ($script:ListingLines -join "`r`n") + "`r`n"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if ($Append -and (Test-Path $path)) { [IO.File]::AppendAllText($path, "`r`n" + $text, $utf8) }
    else { [IO.File]::WriteAllText($path, $text, $utf8) }
    $script:ListingLines.Clear()
    Write-Host "listing saved: report\listings\$Name.txt"
}

function ConvertTo-ShownCommand([string]$Program, [string[]]$Arguments) {
    $parts = foreach ($a in $Arguments) { if ($a -match '\s') { "'$a'" } else { $a } }
    (@($Program) + @($parts)) -join ' '
}

function Invoke-Aws {
    $out = & aws @args
    if ($LASTEXITCODE -ne 0) { throw "aws $($args[0]) $($args[1]) failed with exit code $LASTEXITCODE" }
    $out
}

# Like Invoke-Aws, but the command and its output also go to the console and the listing buffer.
function Invoke-AwsShow {
    Add-Listing ('PS> ' + (ConvertTo-ShownCommand 'aws' $args))
    $out = & aws @args
    $code = $LASTEXITCODE
    if ($out) { Add-Listing ([string[]]$out) }
    if ($code -ne 0) { throw "aws $($args[0]) $($args[1]) failed with exit code $code" }
    $out
}

function Test-Aws {
    $ErrorActionPreference = 'SilentlyContinue'
    & aws @args *> $null
    $LASTEXITCODE -eq 0
}

function New-A2Secret([int]$Length = 24) {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

function New-A2Salts {
    $names = 'AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT'
    ($names | ForEach-Object { "define( '$_', '$(New-A2Secret 64)' );" }) -join "`n"
}

function Get-A2Secrets {
    if (Test-Path $A2.Secrets) { Get-Content $A2.Secrets -Raw | ConvertFrom-Json } else { $null }
}

function Save-A2Secrets($Secrets) {
    [IO.File]::WriteAllText($A2.Secrets, ($Secrets | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
}

# Copies a JSON template from infra/policies to build/, replacing the __TOKENS__, and returns its file:// URI.
function Expand-A2Template([string]$Name, [hashtable]$Extra = @{}) {
    $text = [IO.File]::ReadAllText((Join-Path $A2.Root "infra\policies\$Name"))
    $values = @{
        '__ACCOUNT__' = $script:AccountId; '__REGION__' = $A2.Region
        '__DEPLOY_BUCKET__' = $A2.BucketDeploy; '__BACKUP_BUCKET__' = $A2.BucketBackup
        '__INSTANCE_ROLE__' = $A2.InstanceRole; '__DB__' = $A2.Db; '__SCHEDULE_ROLE__' = $A2.ScheduleRole
    }
    foreach ($k in $Extra.Keys) { $values[$k] = $Extra[$k] }
    foreach ($k in $values.Keys) { $text = $text.Replace($k, $values[$k]) }
    [IO.File]::WriteAllText((Join-Path $A2.Build $Name), $text, (New-Object System.Text.UTF8Encoding $false))
    "file://build/$Name"
}

function Get-DefaultVpcId {
    $id = "$(Invoke-Aws ec2 describe-vpcs --filters 'Name=isDefault,Values=true' --query 'Vpcs[0].VpcId' --output text)".Trim()
    if ($id -eq 'None' -or -not $id) { throw 'No default VPC in ap-southeast-1 (create one with  aws ec2 create-default-vpc  after asking the student)' }
    $id
}

function Get-SubnetId([string]$Az) {
    $id = "$(Invoke-Aws ec2 describe-subnets --filters "Name=vpc-id,Values=$(Get-DefaultVpcId)" "Name=availability-zone,Values=$Az" 'Name=default-for-az,Values=true' --query 'Subnets[0].SubnetId' --output text)".Trim()
    if ($id -eq 'None' -or -not $id) { throw "No default subnet in $Az" }
    $id
}

function Get-SgId([string]$Name) {
    $id = "$(Invoke-Aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$(Get-DefaultVpcId)" "Name=group-name,Values=$Name" --query 'SecurityGroups[0].GroupId' --output text)".Trim()
    if ($id -eq 'None') { '' } else { $id }
}

# The newest non-terminated instance with this Name tag, or $null.
function Get-A2Instance([string]$Name) {
    $json = Invoke-Aws ec2 describe-instances --filters "Name=tag:Name,Values=$Name" 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query 'sort_by(Reservations[].Instances[], &LaunchTime)[-1].{Id:InstanceId,State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,ImageId:ImageId,Az:Placement.AvailabilityZone}' --output json
    ($json -join "`n") | ConvertFrom-Json
}

function Get-TgArn {
    if (-not (Test-Aws elbv2 describe-target-groups --names $A2.Tg)) { return '' }
    "$(Invoke-Aws elbv2 describe-target-groups --names $A2.Tg --query 'TargetGroups[0].TargetGroupArn' --output text)".Trim()
}

function Get-Alb {
    if (-not (Test-Aws elbv2 describe-load-balancers --names $A2.Alb)) { return $null }
    (Invoke-Aws elbv2 describe-load-balancers --names $A2.Alb --query 'LoadBalancers[0].{Arn:LoadBalancerArn,Dns:DNSName,State:State.Code}' --output json) -join "`n" | ConvertFrom-Json
}

function Get-ListenerArn([string]$AlbArn) {
    "$(Invoke-Aws elbv2 describe-listeners --load-balancer-arn $AlbArn --query 'Listeners[0].ListenerArn' --output text)".Trim()
}

function Get-AsgInstanceIds {
    $ids = "$(Invoke-Aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $A2.Asg --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text)".Trim()
    if ($ids -and $ids -ne 'None') { @($ids -split '\s+') } else { @() }
}

function Get-HealthyTargetCount([string[]]$InstanceIds = @()) {
    $healthy = "$(Invoke-Aws elbv2 describe-target-health --target-group-arn (Get-TgArn) --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`].Target.Id' --output text)".Trim()
    $list = @()
    if ($healthy -and $healthy -ne 'None') { $list = @($healthy -split '\s+') }
    if ($InstanceIds.Count) { $list = @($list | Where-Object { $_ -in $InstanceIds }) }
    $list.Count
}

function Get-SshArgs {
    @('-i', $A2.KeyPath, '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$($A2.KnownHosts)",
      '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20')
}

# Runs one command line on an instance as ec2-user. The scripts' own known_hosts file (build\known_hosts) keeps the
# student's ~/.ssh/known_hosts untouched, so their first connection still shows the fingerprint prompt.
function Invoke-Remote([string]$HostIp, [string]$Command, [switch]$Show) {
    if ($Command.Contains('"')) { throw 'Remote commands must not contain double quotes (PowerShell 5.1 mangles them); use a script in infra/remote' }
    if ($Show) { Add-Listing ('[ec2-user@' + $HostIp + ']$ ' + $Command) }
    $out = & ssh @(Get-SshArgs) "ec2-user@$HostIp" $Command
    $code = $LASTEXITCODE
    if ($Show -and $out) { Add-Listing ([string[]]$out) }
    if ($code -ne 0) { throw "ssh command failed with exit code ${code}: $Command" }
    $out
}

# Copies local files (relative paths, no drive letters) into ~/a2 on the instance, a directory only ec2-user can read.
function Copy-ToRemote([string]$HostIp, [string[]]$Paths) {
    $null = Invoke-Remote $HostIp 'install -d -m 700 ~/a2'
    & scp @(Get-SshArgs) -q @Paths "ec2-user@${HostIp}:a2/"
    if ($LASTEXITCODE -ne 0) { throw "scp to $HostIp failed" }
}

function Wait-A2([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$What, [int]$IntervalSeconds = 15) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Seconds $IntervalSeconds
    }
    throw "Timed out after $TimeoutSeconds s waiting for $What"
}
