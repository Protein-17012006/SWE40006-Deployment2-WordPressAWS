#!/bin/bash
# shellcheck disable=SC2016  # the commands are shown and run literally; $ expansions happen inside bash -c
# Text record of the Task 2.4 command-line session on CodeDeployDemo (the student's screenshots show the same
# commands typed live). Uploaded to ~/a2 and run by infra/24-ssh-session.ps1:
#   bash a2/ssh-demo.sh <rds-endpoint> <codedeploy-bucket>
set -uo pipefail
rds_host="$1"
bucket="$2"

show() {  # prints a shell prompt with the command, then runs it
  printf '\n[ec2-user@%s ~]$ %s\n' "$(hostname -s)" "$1"
  bash -c "$1"
}

show 'hostnamectl | grep -E "Static hostname|Operating System|Kernel|Architecture"'
show 'uptime; free -h; df -h /'
show 'TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60"); for p in instance-id placement/availability-zone public-ipv4 iam/info; do printf "%s: " "$p"; curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/$p"; echo; done'
show 'systemctl is-active httpd php-fpm amazon-ssm-agent; systemctl is-active mariadb codedeploy-agent'
show 'curl -sI http://localhost/WordPress/ | head -4'
show 'sudo grep ELB-HealthChecker /var/log/httpd/access_log | tail -3'
show "export MYSQL_PWD=\$(aws ssm get-parameter --name /swe40006/wordpress/db_password --with-decryption --query Parameter.Value --output text); mariadb -h ${rds_host} -u wpuser --ssl-ca=/etc/pki/rds/global-bundle.pem --ssl-verify-server-cert -e \"SHOW STATUS LIKE 'Ssl_cipher'; SELECT ID, post_date, post_title FROM wordpress.wp_posts WHERE post_type='post' AND post_status='publish' ORDER BY ID;\""
show 'aws sts get-caller-identity --query Arn --output text'
show "aws s3 ls s3://${bucket}/"
show 'aws ssm get-parameter --name /swe40006/wordpress/db_host --query Parameter.Value --output text'
show 'sudo tail -n 5 /opt/a2-deploy/history.log'
show 'sudo ls /opt/a2-deploy/'
show 'sudo tail -n 12 /opt/a2-deploy/last-deployment.log'
