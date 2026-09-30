#!/bin/bash
# Puts every vCPU under load for the Task 2.3 scale-out test (stress-ng, or yes(1) as a fallback).
#   bash a2/stress.sh <minutes>
set -euo pipefail
minutes="${1:-20}"
if command -v stress-ng >/dev/null; then
  nohup stress-ng --cpu 0 --timeout "${minutes}m" >/dev/null 2>&1 </dev/null &
  echo "$(hostname -s): stress-ng started on $(nproc) vCPU(s) for ${minutes} minutes"
else
  for _ in $(seq "$(nproc)"); do
    nohup timeout "${minutes}m" yes >/dev/null 2>&1 </dev/null &
  done
  echo "$(hostname -s): yes(1) started on $(nproc) vCPU(s) for ${minutes} minutes (stress-ng is not installed)"
fi
