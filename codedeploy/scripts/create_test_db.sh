#!/bin/bash
# ApplicationStart: create the WordPress database and user on the local MariaDB server.
# The tutorial creates a database called "test" and connects as root with no password.
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

if [ "$DB_HOST" != "localhost" ]; then
  echo "WordPress uses Amazon RDS (${DB_HOST}); no local database to create"
  exit 0
fi

db_name="$(param db_name)"
db_user="$(param db_user)"
db_password="$(param db_password)"
mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';
ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "database ${db_name} and user ${db_user}@localhost are ready"
