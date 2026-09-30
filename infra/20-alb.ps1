# Application Load Balancer in front of WordPress (spec section 6.1). Listing: 09-alb.
param([string]$Listing = '09-alb')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
try {
    Write-Step "Target group $($A2.Tg)"
    $tg = Get-TgArn
    if ($tg) { Add-Listing "$($A2.Tg) exists" }
    else {
        $tg = "$(Invoke-AwsShow elbv2 create-target-group --name $A2.Tg --protocol HTTP --port 80 --vpc-id (Get-DefaultVpcId) --target-type instance --health-check-protocol HTTP --health-check-path /WordPress/wp-login.php --health-check-interval-seconds 15 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --matcher HttpCode=200 --tags "Key=Project,Value=$($A2.Project)" --query 'TargetGroups[0].TargetGroupArn' --output text)".Trim()
    }
    $null = Invoke-AwsShow elbv2 modify-target-group-attributes --target-group-arn $tg --attributes 'Key=deregistration_delay.timeout_seconds,Value=30' --query 'Attributes[?Key==''deregistration_delay.timeout_seconds''].Value' --output text

    Write-Step "Load balancer $($A2.Alb)"
    $alb = Get-Alb
    if ($alb) { Add-Listing "$($A2.Alb) exists: $($alb.Dns)" }
    else {
        $null = Invoke-AwsShow elbv2 create-load-balancer --name $A2.Alb --type application --scheme internet-facing --ip-address-type ipv4 --subnets (Get-SubnetId $A2.AzA) (Get-SubnetId $A2.AzB) --security-groups (Get-SgId $A2.SgAlb) --tags "Key=Project,Value=$($A2.Project)" --query 'LoadBalancers[0].[LoadBalancerName,DNSName,State.Code]' --output text
        $alb = Get-Alb
    }
    Add-Listing "PS> aws elbv2 wait load-balancer-available --names $($A2.Alb)"
    & aws elbv2 wait load-balancer-available --names $A2.Alb
    if ($LASTEXITCODE -ne 0) { throw 'the load balancer did not become active' }

    Write-Step 'Listener HTTP:80 (default action: forward) and rule "/" -> 301 /WordPress/'
    $listener = Get-ListenerArn $alb.Arn
    if ($listener -eq 'None' -or -not $listener) {
        $listener = "$(Invoke-AwsShow elbv2 create-listener --load-balancer-arn $alb.Arn --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=$tg" --query 'Listeners[0].ListenerArn' --output text)".Trim()
    } else { Add-Listing 'listener HTTP:80 exists' }
    $hasRule = "$(Invoke-Aws elbv2 describe-rules --listener-arn $listener --query 'length(Rules[?Priority==''10''])' --output text)".Trim()
    if ($hasRule -eq '0') {
        $null = Invoke-AwsShow elbv2 create-rule --listener-arn $listener --priority 10 --conditions 'Field=path-pattern,Values=/' --actions 'Type=redirect,RedirectConfig={Path=/WordPress/,StatusCode=HTTP_301}' --query 'Rules[0].RuleArn' --output text
    } else { Add-Listing 'redirect rule (priority 10) exists' }
    $null = Invoke-AwsShow elbv2 describe-rules --listener-arn $listener --query 'Rules[].{Priority:Priority,Path:Conditions[0].Values[0],Action:Actions[0].Type}' --output table

    Write-Step 'Register CodeDeployDemo and wait until it is healthy'
    $demo = Get-A2Instance $A2.DemoName
    $null = Invoke-AwsShow elbv2 register-targets --target-group-arn $tg --targets "Id=$($demo.Id)"
    Add-Listing "PS> aws elbv2 wait target-in-service --target-group-arn <$($A2.Tg) ARN> --targets Id=$($demo.Id)"
    & aws elbv2 wait target-in-service --target-group-arn $tg --targets "Id=$($demo.Id)"
    if ($LASTEXITCODE -ne 0) { throw 'CodeDeployDemo did not become healthy in the target group' }
    $null = Invoke-AwsShow elbv2 describe-target-health --target-group-arn $tg --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table

    Write-Step 'Requests through the load balancer'
    foreach ($path in '/', '/WordPress/') {
        Add-Listing "PS> curl.exe -s -o NUL -w '%{http_code} %{redirect_url}' http://$($alb.Dns)$path"
        Add-Listing ([string](& curl.exe -s -o NUL -w '%{http_code} %{redirect_url}' "http://$($alb.Dns)$path"))
    }
    Add-Listing "Load balancer URL: http://$($alb.Dns)/"
} finally {
    Save-Listing $Listing
}
