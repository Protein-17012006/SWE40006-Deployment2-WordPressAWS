# ED25519 key pair for SSH ("Create a key pair using Amazon EC2", AWS CLI). Listing: 04-key-pair.
param([string]$Listing = '04-key-pair')
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib.ps1"
Initialize-A2
$shownKey = "~\.ssh\$($A2.KeyName).pem"
try {
    Write-Step "Key pair $($A2.KeyName)"
    $exists = Test-Aws ec2 describe-key-pairs --key-names $A2.KeyName
    if ($exists -and -not (Test-Path $A2.KeyPath)) {
        throw "Key pair $($A2.KeyName) exists in AWS but $($A2.KeyPath) is missing; a private key cannot be downloaded twice. Ask the student before deleting the key pair and re-running."
    }
    if ($exists) { Add-Listing "$($A2.KeyName) exists and $shownKey is present" }
    else {
        Add-Listing "PS> aws ec2 create-key-pair --key-name $($A2.KeyName) --key-type ed25519 --key-format pem --query KeyMaterial --output text > $shownKey"
        $material = Invoke-Aws ec2 create-key-pair --key-name $A2.KeyName --key-type ed25519 --key-format pem --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=$($A2.Project)}]" --query KeyMaterial --output text
        New-Item -ItemType Directory -Force -Path (Split-Path $A2.KeyPath) | Out-Null
        [IO.File]::WriteAllText($A2.KeyPath, (($material -join "`n").Trim() + "`n"), (New-Object System.Text.UTF8Encoding $false))
        Add-Listing '(private key saved with LF line endings; its content is never shown)'
    }

    Write-Step 'Restrict the key file to the current user (the Windows equivalent of chmod 400)'
    Add-Listing "PS> icacls $shownKey /inheritance:r /grant:r $($env:USERNAME):R"
    $out = & icacls $A2.KeyPath /inheritance:r /grant:r "$($env:USERNAME):R"
    if ($LASTEXITCODE -ne 0) { throw 'icacls failed' }
    Add-Listing ([string[]]($out | Where-Object { $_ }) -replace [regex]::Escape($env:USERPROFILE), '~')
    Add-Listing "PS> icacls $shownKey"
    Add-Listing ([string[]](& icacls $A2.KeyPath | Where-Object { $_ }) -replace [regex]::Escape($env:USERPROFILE), '~')

    Write-Step 'Fingerprint in EC2 versus the fingerprint of the local private key'
    $null = Invoke-AwsShow ec2 describe-key-pairs --key-names $A2.KeyName --query 'KeyPairs[0].[KeyName,KeyType,KeyFingerprint]' --output text
    Add-Listing "PS> ssh-keygen -l -f $shownKey"
    Add-Listing ([string[]](& ssh-keygen -l -f $A2.KeyPath))
} finally {
    Save-Listing $Listing
}
