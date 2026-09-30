#!/bin/bash
# In-place deployment of a CodeDeploy-format revision (appspec.yml + hook scripts) on this instance.
# AWS CodeDeploy is not available on this AWS Free-plan account (docs/error-log.md #3), so this script does what
# the CodeDeploy agent does for an EC2 in-place deployment, reading the hooks from the revision's appspec.yml:
#   ApplicationStop (previous revision) -> DownloadBundle -> BeforeInstall -> Install -> AfterInstall
#   -> ApplicationStart -> ValidateService
# Usage (uploaded to ~/a2 by infra/deploy.ps1):  sudo bash a2/deploy-revision.sh s3://<bucket>/<key> '<description>'
set -euo pipefail

ROOT=/opt/a2-deploy
REGION=ap-southeast-1

# hooks_for EVENT APPSPEC: the script locations listed under hooks/EVENT, in appspec order
hooks_for() {
  awk -v ev="$1" '
    /^hooks:/ { inhooks = 1; next }
    inhooks && /^[^ ]/ { inhooks = 0 }
    inhooks && /^  [A-Za-z]+:/ { current = $1; sub(/:$/, "", current); next }
    inhooks && current == ev && $2 == "location:" { print $3 }
  ' "$2"
}

# destination_of APPSPEC: the destination of the first files entry
destination_of() {
  awk '$1 == "destination:" { print $2; exit }' "$1"
}

# run_event EVENT DIR: runs the event's hook scripts from the revision in DIR; stops at the first failure
run_event() {
  local event="$1" dir="$2" script start
  while read -r script; do
    start=$SECONDS
    if timeout 900 bash "$dir/$script"; then
      printf '%-17s %-10s %s (%d s)\n' "$event" Succeeded "$script" $((SECONDS - start))
    else
      printf '%-17s %-10s %s (%d s)\n' "$event" Failed "$script" $((SECONDS - start))
      return 1
    fi
  done < <(hooks_for "$event" "$dir/appspec.yml")
}

main() {
  DEPLOY_BUNDLE="$1"
  DEPLOY_DESCRIPTION="${2:-}"
  DEPLOY_ID="d-$(date -u +%Y%m%dT%H%M%SZ)"
  DEPLOY_STATUS=Failed
  local work="$ROOT/$DEPLOY_ID" dest
  mkdir -p "$work"
  trap 'echo "$(date -u +%FT%TZ) $DEPLOY_ID $DEPLOY_STATUS $DEPLOY_DESCRIPTION" >> "$ROOT/history.log"' EXIT
  echo "Deployment $DEPLOY_ID: $DEPLOY_DESCRIPTION"
  # The CodeDeploy service is unavailable on this account, so its agent would only log errors.
  systemctl disable --now codedeploy-agent >/dev/null 2>&1 || true

  if [ -e "$ROOT/current/appspec.yml" ]; then
    run_event ApplicationStop "$ROOT/current"
  fi
  aws s3 cp "$DEPLOY_BUNDLE" "$work/revision.zip" --region "$REGION" --only-show-errors
  python3 -m zipfile -e "$work/revision.zip" "$work/archive"
  printf '%-17s %-10s %s\n' DownloadBundle Succeeded "$DEPLOY_BUNDLE"
  run_event BeforeInstall "$work/archive"
  dest="$(destination_of "$work/archive/appspec.yml")"
  mkdir -p "$dest"
  cp -a "$work/archive/." "$dest/"
  printf '%-17s %-10s %s\n' Install Succeeded "$(find "$work/archive" -type f | wc -l) files copied to $dest"
  run_event AfterInstall "$work/archive"
  run_event ApplicationStart "$work/archive"
  run_event ValidateService "$work/archive"
  ln -sfn "$work/archive" "$ROOT/current"
  DEPLOY_STATUS=Succeeded
  echo "Deployment $DEPLOY_ID: $DEPLOY_STATUS"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  mkdir -p "$ROOT"
  main "$@" 2>&1 | tee "$ROOT/last-deployment.log"
fi
