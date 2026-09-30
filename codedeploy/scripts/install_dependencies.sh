#!/bin/bash
# BeforeInstall: Apache, PHP 8 and the MariaDB client; the MariaDB server only while the database is local.
# Replaces the tutorial's "amazon-linux-extras install php7.4" (Amazon Linux 2 only; end of support 2026-06-30).
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

packages=(httpd php php-fpm php-mysqlnd php-gd php-mbstring php-xml mariadb105)
if [ "$DB_HOST" = "localhost" ]; then
  packages+=(mariadb105-server)
fi
dnf install -y "${packages[@]}"

# Load generator for the Task 2.3 scale-out test; optional, so it never blocks a deployment.
dnf install -y stress-ng || echo "stress-ng is not available; the scaling test will fall back to yes(1)"
