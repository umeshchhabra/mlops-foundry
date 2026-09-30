#!/usr/bin/env bash
set -euo pipefail

timeout_minutes=15
interval_seconds=15
check_arguments=()
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./health/wait-for-stack.sh [--timeout-minutes NUMBER] [--interval-seconds NUMBER] [health-check options]

Pass --context, --namespace, --argocd-namespace, or --kserve-namespace through
to health/check-stack.py when using a non-default cluster layout.
EOF
}

while (($#)); do
  case "$1" in
    --timeout-minutes)
      timeout_minutes="${2:?--timeout-minutes requires a value}"
      shift 2
      ;;
    --interval-seconds)
      interval_seconds="${2:?--interval-seconds requires a value}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      check_arguments+=("$1")
      shift
      ;;
  esac
done

if ! [[ "$timeout_minutes" =~ ^[1-9][0-9]*$ && "$interval_seconds" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'Timeout and interval must be positive integers.' >&2
  exit 2
fi

deadline=$((SECONDS + timeout_minutes * 60))
while ((SECONDS < deadline)); do
  if python3 "$script_dir/check-stack.py" "${check_arguments[@]}" >/dev/null 2>&1; then
    printf '%s\n' 'Stack is healthy.'
    exit 0
  fi
  printf '%s\n' 'Stack is still reconciling...'
  sleep "$interval_seconds"
done

printf 'Stack did not become healthy within %s minutes.\n' "$timeout_minutes" >&2
python3 "$script_dir/check-stack.py" "${check_arguments[@]}"
