# Source this in CI steps containing multiple independent tests.
# Preserve pipefail, but collect errors and finish after the last test.
set +e
set -uo pipefail
ci_failures=0

_ci_on_error() {
  local status="$1" line="$2" command="$3"
  ci_failures=$((ci_failures + 1))
  printf '::error title=CI test command failed::exit=%s line=%s: %s\n' "$status" "$line" "$command"
}
trap '_ci_on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

ci_fail_marker() {
  _ci_on_error 1 "$LINENO" "$*"
}

ci_finish() {
  trap - ERR
  if (( ci_failures > 0 )); then
    printf '::error title=CI suite failed::%s failed commands or assertions\n' "$ci_failures"
    return 1
  fi
}
