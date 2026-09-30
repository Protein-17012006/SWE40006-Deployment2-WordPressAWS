# Builds the CodeDeploy-format revision in build/WordPress, zips it and uploads it to S3 (tutorial Steps 2-3).
# "aws deploy push" needs the CodeDeploy service, which this Free-plan account cannot use (docs/error-log.md #3).
#   -ThemeSlug <slug>  also applies the tutorial Step 5 colour change (#fff -> #768331) to that theme.
#   -NoPush            build only (no AWS calls).
param([string]$ThemeSlug = '', [switch]$NoPush, [string]$Listing = '')
. "$PSScriptRoot\..\infra\config.ps1"
. "$PSScriptRoot\..\infra\lib.ps1"
if ($NoPush) { Set-Location $A2.Root; New-Item -ItemType Directory -Force -Path $A2.Build | Out-Null } else { Initialize-A2 }
try {
    $version = (Get-Content codedeploy\wordpress-version.txt -Raw).Trim()
    $zip = Join-Path $A2.Build "wordpress-$version.zip"
    if (-not (Test-Path $zip)) {
        Write-Step "Download WordPress $version from the WordPress/WordPress GitHub mirror (the tutorial's source)"
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/WordPress/WordPress/archive/refs/tags/$version.zip" -OutFile $zip
    }
    $target = Join-Path $A2.Build 'WordPress'
    $extract = Join-Path $A2.Build 'extract'
    Remove-Item -Recurse -Force $target, $extract -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    & "$env:SystemRoot\System32\tar.exe" -xf $zip -C $extract
    if ($LASTEXITCODE -ne 0) { throw 'tar could not extract the WordPress archive' }
    Move-Item (Join-Path $extract "WordPress-$version") $target
    Remove-Item -Recurse -Force $extract

    Write-Step 'Overlay the AppSpec, hook scripts, Apache settings and the footer plugin'
    Copy-Item codedeploy\appspec.yml $target
    Copy-Item -Recurse codedeploy\scripts (Join-Path $target 'scripts')
    Copy-Item -Recurse codedeploy\config (Join-Path $target 'config')
    New-Item -ItemType Directory -Force -Path (Join-Path $target 'wp-content\mu-plugins') | Out-Null
    Copy-Item codedeploy\wp-content\mu-plugins\a2-served-by.php (Join-Path $target 'wp-content\mu-plugins')

    if ($ThemeSlug) {
        Write-Step "Tutorial Step 5: change #fff to #768331 in theme $ThemeSlug"
        $dir = Join-Path $target "wp-content\themes\$ThemeSlug"
        $file = Join-Path $dir 'theme.json'
        if (-not (Test-Path $file)) { $file = Join-Path $dir 'style.css' }
        $text = [IO.File]::ReadAllText($file)
        $count = [regex]::Matches($text, '#fff(fff)?\b', 'IgnoreCase').Count
        if ($count -eq 0) { throw "no #fff or #ffffff colour in $file" }
        [IO.File]::WriteAllText($file, [regex]::Replace($text, '#fff(fff)?\b', '#768331', 'IgnoreCase'), (New-Object System.Text.UTF8Encoding $false))
        Add-Listing "Replaced $count occurrence(s) of #fff/#ffffff with #768331 in wp-content/themes/$ThemeSlug/$(Split-Path $file -Leaf)"
    }

    Write-Step 'Line-ending check: files that run on Linux must not contain CR'
    $linux = @(Get-Item (Join-Path $target 'appspec.yml')) + @(Get-ChildItem (Join-Path $target 'scripts'), (Join-Path $target 'config') -File)
    $bad = @($linux | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains("`r") })
    if ($bad.Count) { throw "CR characters found in: $(($bad | ForEach-Object { $_.Name }) -join ', ')" }
    Add-Listing "Revision ready in build/WordPress: WordPress $version, $((Get-ChildItem $target -Recurse -File).Count) files"

    if (-not $NoPush) {
        Write-Step 'Zip the revision (forward-slash paths, Unix modes) and upload it to the revision bucket'
        Add-Listing 'PS> python codedeploy\zip-revision.py'
        $zipOut = & python codedeploy\zip-revision.py
        if ($LASTEXITCODE -ne 0) { throw 'zip-revision.py failed' }
        Add-Listing ([string[]]$zipOut)
        $null = Invoke-AwsShow s3 cp build\WordPressApp.zip "s3://$($A2.BucketDeploy)/$($A2.RevisionKey)" --only-show-errors
        $null = Invoke-AwsShow s3 ls "s3://$($A2.BucketDeploy)/" --human-readable
    }
} finally {
    if ($Listing) { Save-Listing $Listing }
}
