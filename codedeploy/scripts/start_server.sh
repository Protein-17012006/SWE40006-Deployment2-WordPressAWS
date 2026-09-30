#!/bin/bash
# ApplicationStart: start the web tier; run MariaDB only while WordPress uses the local database.
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

if [ "$DB_HOST" = "localhost" ]; then
  systemctl enable --now mariadb
elif systemctl cat mariadb.service >/dev/null 2>&1; then
  systemctl disable --now mariadb
  echo "WordPress uses Amazon RDS: the local MariaDB server is stopped and disabled"
fi
systemctl enable --now php-fpm
systemctl enable --now httpd
