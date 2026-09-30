# Error log — Deployment Activity 2

Errors met while building and deploying, and how each was resolved (newest last).

| # | Date | Task | Error (exact message) | Cause | Fix |
|---|------|------|-----------------------|-------|-----|
| 1 | 2026-09-30 | 1 | `winget upgrade --id Amazon.AWSCLI` → MSI exit code 1603; log: "Error 1714. The older version of AWS Command Line Interface v2 cannot be removed. System Error 1612." | AWS CLI 2.31.31 had been installed by the AWS Toolkit for VS Code from a Temp folder that no longer exists, and its cached MSI (`C:\Windows\Installer\8eaef57.msi`) was gone, so Windows Installer could not find a source to remove the old version | Downloaded `AWSCLIV2-2.31.31.msi` (same ProductCode and PackageCode as the registered product), placed it in the registered source folder as `AWSCLIV2.msi`, re-ran the upgrade (installed 2.37.6), then removed the temporary copy |
| 2 | 2026-09-30 | 3 | `aws ec2 describe-vpcs --filters Name=isDefault,Values=true` run from PowerShell → "An error occurred (InvalidParameterValue) when calling the DescribeVpcs operation: The filter 'null' is invalid" | PowerShell parses an unquoted `a,b` argument as an array and passes it to native programs as two separate arguments, so the AWS CLI received `Name=isDefault` and `Values=true` as two filters | Quoted every comma shorthand argument (`'Name=isDefault,Values=true'`) in all scripts and commands, and added an AST-based test in `tests/lib.tests.ps1` that fails on any unquoted comma list in `infra/` or `codedeploy/` scripts |
