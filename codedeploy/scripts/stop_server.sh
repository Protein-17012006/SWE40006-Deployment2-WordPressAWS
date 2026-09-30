#!/bin/bash
# ApplicationStop: stop what the previous revision started.
# The tutorial's version never actually ran pgrep, so every branch always fired.
set -euo pipefail

stop_if_running() {  # $1 = process-name pattern for pgrep -x, $2 = systemd unit
  if pgrep -x "$1" >/dev/null; then
    systemctl stop "$2"
    echo "stopped $2"
  fi
}

stop_if_running httpd httpd
stop_if_running php-fpm php-fpm
stop_if_running 'mariadbd|mysqld' mariadb
