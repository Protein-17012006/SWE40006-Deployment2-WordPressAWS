#!/bin/bash
# AfterInstall: Apache owns the site; directories 755 and files 644.
# The tutorial's "chmod -R 777" (and its later manual "chmod -R 755") is not needed.
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

chown -R apache:apache "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} +
find "$WP_DIR" -type f -exec chmod 644 {} +
