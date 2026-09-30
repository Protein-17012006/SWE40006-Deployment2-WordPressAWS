# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the hook scripts that source this file
# Shared settings for the CodeDeploy hook scripts; sourced by each hook, never run directly.
set -euo pipefail

A2_REGION="ap-southeast-1"
A2_PARAM_PREFIX="/swe40006/wordpress"
WP_DIR="/var/www/html/WordPress"
RDS_CA_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
RDS_CA_FILE="/etc/pki/rds/global-bundle.pem"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# param NAME prints the value of ${A2_PARAM_PREFIX}/NAME (SecureString values are decrypted).
param() {
  aws ssm get-parameter --region "$A2_REGION" --name "${A2_PARAM_PREFIX}/$1" \
    --with-decryption --query Parameter.Value --output text
}

# "localhost" while WordPress uses the MariaDB server on this instance, otherwise the RDS endpoint.
# A plain assignment, so a failed parameter read stops the hook (set -e) instead of silently picking a mode.
DB_HOST="$(param db_host)"
