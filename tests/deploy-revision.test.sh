#!/bin/bash
# Unit tests for the appspec readers in infra/remote/deploy-revision.sh:  bash tests/deploy-revision.test.sh
set -u
cd "$(dirname "$0")/.."
# shellcheck source=../infra/remote/deploy-revision.sh
source infra/remote/deploy-revision.sh
set +e
failed=0

check() {  # $1 = test name, $2 = expected, $3 = actual
  if [ "$3" = "$2" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1: expected '$2', got '$3'"
    failed=1
  fi
}

hooks() { hooks_for "$1" codedeploy/appspec.yml | tr '\n' ' ' | sed 's/ $//'; }

check 'ApplicationStop runs the stop script' 'scripts/stop_server.sh' "$(hooks ApplicationStop)"
check 'BeforeInstall runs install_dependencies' 'scripts/install_dependencies.sh' "$(hooks BeforeInstall)"
check 'AfterInstall runs both scripts in appspec order' 'scripts/change_permissions.sh scripts/configure_wordpress.sh' "$(hooks AfterInstall)"
check 'ApplicationStart runs both scripts in appspec order' 'scripts/start_server.sh scripts/create_test_db.sh' "$(hooks ApplicationStart)"
check 'ValidateService runs the validation script' 'scripts/validate_service.sh' "$(hooks ValidateService)"
check 'an event without hooks runs nothing' '' "$(hooks Install)"
check 'files are installed to the appspec destination' '/var/www/html/WordPress' "$(destination_of codedeploy/appspec.yml)"

exit "$failed"
