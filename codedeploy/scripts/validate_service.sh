#!/bin/bash
# ValidateService (new): the deployment only succeeds if WordPress answers through Apache and PHP.
set -euo pipefail

url="http://localhost/WordPress/wp-login.php"
for attempt in $(seq 1 12); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)"
  case "$code" in
    2??|3??) echo "WordPress answered HTTP ${code} on attempt ${attempt}"; exit 0 ;;
  esac
  echo "attempt ${attempt}: HTTP ${code:-none}, retrying in 5 s"
  sleep 5
done
echo "WordPress did not answer with 2xx/3xx within 60 s" >&2
exit 1
