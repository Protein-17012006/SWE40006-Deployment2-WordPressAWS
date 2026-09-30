#!/bin/bash
# Copies the WordPress database from the MariaDB server on CodeDeployDemo to Amazon RDS.
# Uploaded to ~/a2 (mode 700) and run by infra/22-db-migration.ps1:
#   bash a2/db-migrate.sh dump   <backup-bucket>
#   bash a2/db-migrate.sh import <rds-endpoint>   (uses ~/a2/rds-admin.cnf with the RDS master login)
#   bash a2/db-migrate.sh counts <rds-endpoint>
set -euo pipefail
cd "$(dirname "$0")"
REGION="ap-southeast-1"
TABLES=(wp_posts wp_users wp_options wp_terms wp_comments)
CA="$PWD/rds-global-bundle.pem"

param() {
  aws ssm get-parameter --region "$REGION" --name "/swe40006/wordpress/$1" \
    --with-decryption --query Parameter.Value --output text
}

# mariadb client logged in as the RDS master user, over TLS with server-certificate verification
rds() {
  [ -f "$CA" ] || curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o "$CA"
  mariadb --defaults-extra-file=rds-admin.cnf --ssl-ca="$CA" --ssl-verify-server-cert "$@"
}

case "${1:-}" in
  dump)
    file="wordpress-local-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
    sudo mysqldump --single-transaction --quick --default-character-set=utf8mb4 \
      --databases "$(param db_name)" | gzip > "$file"
    ls -l "$file"
    aws s3 cp "$file" "s3://$2/db/$file" --region "$REGION"
    ln -sf "$file" wordpress-local.sql.gz
    ;;
  import)
    db="$(param db_name)"
    user="$(param db_user)"
    password="$(param db_password)"
    rds -h "$2" -e "SELECT VERSION() AS rds_version; SHOW STATUS LIKE 'Ssl_cipher';"
    gunzip -c wordpress-local.sql.gz | rds -h "$2"
    rds -h "$2" <<SQL
CREATE USER IF NOT EXISTS '${user}'@'%' IDENTIFIED BY '${password}';
ALTER USER '${user}'@'%' IDENTIFIED BY '${password}';
GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${user}'@'%';
FLUSH PRIVILEGES;
SQL
    echo "imported the dump into ${db} on RDS and granted ${user}@'%'"
    ;;
  counts)
    db="$(param db_name)"
    printf '%-12s %8s %8s\n' table local rds
    for t in "${TABLES[@]}"; do
      local_rows="$(sudo mariadb -N -e "SELECT COUNT(*) FROM \`${db}\`.${t}")"
      rds_rows="$(rds -h "$2" -N -e "SELECT COUNT(*) FROM \`${db}\`.${t}")"
      printf '%-12s %8s %8s\n' "$t" "$local_rows" "$rds_rows"
    done
    ;;
  *)
    echo "usage: $0 dump <bucket> | import <rds-endpoint> | counts <rds-endpoint>" >&2
    exit 2
    ;;
esac
