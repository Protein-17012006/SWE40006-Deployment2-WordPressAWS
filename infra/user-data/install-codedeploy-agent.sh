#!/bin/bash
# EC2 user data for CodeDeployDemo: install the CodeDeploy agent
# ("Install the CodeDeploy agent for Amazon Linux or RHEL"). Agent v2 needs no Ruby; v1.8 is the fallback.
set -euxo pipefail
REGION="ap-southeast-1"
BASE="https://aws-codedeploy-${REGION}.s3.${REGION}.amazonaws.com"
cd /tmp
if curl -fsSLo install "${BASE}/latestv2/install"; then
  echo "Installing CodeDeploy agent v2"
else
  echo "latestv2 is not available in ${REGION}; installing agent v1.8, which needs Ruby"
  dnf install -y ruby
  curl -fsSLo install "${BASE}/latest/install"
fi
chmod +x ./install
./install auto
systemctl enable --now codedeploy-agent
