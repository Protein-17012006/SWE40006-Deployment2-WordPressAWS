# WordPress on AWS — SWE40006 Deployment Activity 2

WordPress deployed to Amazon EC2 from the AWS CodeDeploy tutorial's revision (appspec + hook scripts). It was then:
- put behind an **Application Load Balancer**;
- moved onto **Amazon RDS for MariaDB**;
- backed up to **Amazon S3** as an AMI object and restored;
- run in an **Auto Scaling group**.

Task 2, sub-tasks 2.1–2.4, Singapore Region `ap-southeast-1`.

| Public URL | What it serves |
|---|---|
| http://a2-wordpress-alb-1358921474.ap-southeast-1.elb.amazonaws.com/ | The load balancer, in front of an Auto Scaling group (2–4 instances launched from the AMI restored from S3) |
| http://13.251.15.190/WordPress/ | The Task 2.1 instance `CodeDeployDemo` (Elastic IP) |

> Between submission and grading the environment is **paused** to save AWS credit, and the load balancer shows a "paused" page. `infra/resume-for-grading.ps1` starts everything again in about 15 minutes.

## Architecture

- **Deployment:** `CodeDeployDemo` (t3.micro, Amazon Linux 2023) receives the revision `s3://sws01199-a2-codedeploy/WordPressApp.zip`. The AWS CodeDeploy service is not available on the Free-plan account used, so `infra/remote/deploy-revision.sh` runs the revision's appspec hooks in CodeDeploy's lifecycle order.
- **Load balancer:** `a2-wordpress-alb` forwards to `a2-wordpress-tg`; `/` redirects to `/WordPress/`.
- **Auto Scaling:** `a2-wordpress-asg` (min 2, max 4, target tracking on 50 % average CPU) launches instances from the launch template `a2-wordpress-lt`. Its AMI was restored from `s3://sws01199-a2-backups/ami-….bin`.
- **Database and settings:** every web server uses `a2-wordpress-db` (RDS for MariaDB, private, TLS). Settings and secrets come from SSM Parameter Store (`/swe40006/wordpress/*`).
- **Network security:**
  - Only the load balancer and the tutorial instance accept HTTP from the internet.
  - The database accepts MariaDB connections only from the web tiers.
  - SSH is allowed only from the student's IP.

## Repository layout

| Path | Contents |
|---|---|
| `codedeploy/` | The CodeDeploy revision overlay: `appspec.yml`, hook `scripts/`, Apache `config/`, the footer plugin, the pinned WordPress version and `build-revision.ps1` |
| `infra/` | Numbered AWS CLI scripts (Windows PowerShell 5.1) for every step, `deploy.ps1`, pause/resume/teardown, `policies/` JSON, and `remote/`/`user-data/` shell scripts |
| `tests/` | PHP unit tests for the footer plugin, PowerShell helper tests, lint (CR check, `bash -n`, ShellCheck, `php -l`) and a secret scan |
| `docs/` | Design spec, implementation plan, error log and architecture diagram |

## Run it

```powershell
aws login --profile swe40006-a2
powershell -ExecutionPolicy Bypass -File infra\00-preflight.ps1
# Task 2.1
powershell -ExecutionPolicy Bypass -File infra\10-iam.ps1
powershell -ExecutionPolicy Bypass -File infra\11-keypair.ps1
powershell -ExecutionPolicy Bypass -File infra\12-network.ps1
powershell -ExecutionPolicy Bypass -File infra\13-ec2-codedeploydemo.ps1
powershell -ExecutionPolicy Bypass -File infra\14-ssm-parameters.ps1
powershell -ExecutionPolicy Bypass -File infra\15-s3-buckets.ps1
powershell -ExecutionPolicy Bypass -File codedeploy\build-revision.ps1
powershell -ExecutionPolicy Bypass -File infra\deploy.ps1 -Description 'Deploy 1' -Listing deploy-1
powershell -ExecutionPolicy Bypass -File codedeploy\build-revision.ps1 -ThemeSlug twentytwentyfive   # tutorial Step 5
powershell -ExecutionPolicy Bypass -File infra\deploy.ps1 -Description 'Deploy 2' -Listing deploy-2
# Task 2.2
powershell -ExecutionPolicy Bypass -File infra\20-alb.ps1
powershell -ExecutionPolicy Bypass -File infra\21-rds.ps1
powershell -ExecutionPolicy Bypass -File infra\deploy.ps1 -Description 'Deploy 3' -Listing deploy-3 -SiteUrl http://<alb-dns>/WordPress
powershell -ExecutionPolicy Bypass -File infra\22-db-migration.ps1
powershell -ExecutionPolicy Bypass -File infra\deploy.ps1 -Description 'Deploy 4' -Listing deploy-4 -DbHost <rds-endpoint>
powershell -ExecutionPolicy Bypass -File infra\23-ami-s3-backup.ps1
# Task 2.3
powershell -ExecutionPolicy Bypass -File infra\30-asg.ps1 -Step create
powershell -ExecutionPolicy Bypass -File infra\30-asg.ps1 -Step tidy
powershell -ExecutionPolicy Bypass -File infra\31-scaling-tests.ps1 -Test manual
powershell -ExecutionPolicy Bypass -File infra\31-scaling-tests.ps1 -Test dynamic-start
powershell -ExecutionPolicy Bypass -File infra\31-scaling-tests.ps1 -Test dynamic-watch -Target 4
powershell -ExecutionPolicy Bypass -File infra\31-scaling-tests.ps1 -Test selfheal
# Task 2.4: a text record of the SSH session; allow-my-ip.ps1 when the home IP changes
powershell -ExecutionPolicy Bypass -File infra\24-ssh-session.ps1
powershell -ExecutionPolicy Bypass -File infra\allow-my-ip.ps1
# Grading
powershell -ExecutionPolicy Bypass -File infra\pause-for-grading.ps1
powershell -ExecutionPolicy Bypass -File infra\resume-for-grading.ps1
powershell -ExecutionPolicy Bypass -File infra\teardown.ps1 -DryRun
```

## Tests

```powershell
powershell -NoProfile -File tests\lint.ps1        # CR check, bash -n, ShellCheck, php -l, then the PHP unit tests
powershell -NoProfile -File tests\lib.tests.ps1   # PowerShell helper tests
```

## Changes from the CodeDeploy WordPress tutorial

| Tutorial | This repository | Why |
|---|---|---|
| Amazon Linux 2, `amazon-linux-extras install php7.4` | Amazon Linux 2023, `dnf install httpd php php-fpm … mariadb105` | Amazon Linux 2 reached end of support on 2026-06-30 |
| `stop_server.sh` assigns strings instead of running `pgrep` | One `pgrep -x` check per service | Every branch always fired and printed an error |
| Database `test`, user `root` with no password | Database `wordpress`, user `wpuser`, generated password in SSM Parameter Store | Security |
| `chmod -R 777`, then a manual `chmod -R 755` | `apache:apache`, directories 755, files 644, `wp-config.php` 640 | Least privilege, no manual step |
| The WordPress installer writes `wp-config.php` | `configure_wordpress.sh` renders it from Parameter Store on every deployment | "Re-install on RDS" becomes a parameter change plus a redeployment |
| Unpinned `master.zip` | The latest stable release tag (`codedeploy/wordpress-version.txt`) | `master` is a development snapshot |
| Step 5 edits `twentyfifteen/style.css` | The same `#fff` → `#768331` change in the active default theme | Twenty Fifteen is no longer the default theme, so a change to it would not be visible |
| No validation hook | A `ValidateService` hook checks that `wp-login.php` answers | A deployment only succeeds when WordPress works |
| CodeDeploy application and deployment group; `aws deploy push` and `create-deployment` | The same revision is zipped, uploaded with `aws s3 cp`, and deployed by `infra/remote/deploy-revision.sh` (CodeDeploy lifecycle order, started over SSH) | CodeDeploy returns `SubscriptionRequiredException` on AWS Free-plan accounts |

The report with screenshots is submitted separately on Canvas.
