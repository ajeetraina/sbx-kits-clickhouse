#!/usr/bin/env bash
set -euo pipefail

# set-host.sh — set the ClickHouse connection target in spec.yaml, keeping every
# copy of a value in sync. In the v0.39.0 grammar there is no `args` templating,
# so the host lives in THREE places (env var, credential inject domain, network
# allow entry) and the user lives in TWO (env var, inject username). This script
# is the single source of truth so those literals never drift — a drift the
# validator won't catch but the engine rejects at run time.
#
# Usage:
#   scripts/set-host.sh <host> [--user U] [--port P] [--database D] [--secure true|false]
#
# Examples:
#   scripts/set-host.sh myco.us-east-1.aws.clickhouse.cloud
#   scripts/set-host.sh ch.internal.example.com --user analyst --port 8123 --secure false
#
# The password is NOT handled here — it never belongs in the spec. Set it with:
#   sbx secret set -g clickhouse

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

[ $# -ge 1 ] || { echo "error: missing <host>" >&2; usage 1; }
case "$1" in -h|--help) usage 0 ;; esac

HOST="$1"; shift
USER_VAL=""; PORT=""; DATABASE=""; SECURE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --user)     USER_VAL="${2:?--user needs a value}"; shift 2 ;;
    --port)     PORT="${2:?--port needs a value}"; shift 2 ;;
    --database) DATABASE="${2:?--database needs a value}"; shift 2 ;;
    --secure)   SECURE="${2:?--secure needs a value}"; shift 2 ;;
    *) echo "error: unknown flag: $1" >&2; usage 1 ;;
  esac
done

# --- validate inputs -------------------------------------------------------
printf '%s' "$HOST" | grep -Eq '^[A-Za-z0-9._-]+$' \
  || { echo "error: host '$HOST' is not a bare hostname (no scheme, no port, no path)" >&2; exit 1; }
[ -z "$PORT" ]   || printf '%s' "$PORT"   | grep -Eq '^[0-9]+$'          || { echo "error: --port must be numeric" >&2; exit 1; }
[ -z "$USER_VAL" ] || printf '%s' "$USER_VAL" | grep -Eq '^[A-Za-z0-9._-]+$' || { echo "error: --user has invalid characters" >&2; exit 1; }
[ -z "$SECURE" ] || case "$SECURE" in true|false) ;; *) echo "error: --secure must be 'true' or 'false'" >&2; exit 1 ;; esac

SPEC="$(cd "$(dirname "$0")/.." && pwd)/spec.yaml"
[ -f "$SPEC" ] || { echo "error: spec.yaml not found at $SPEC" >&2; exit 1; }

# --- edit (anchored, comment-preserving) -----------------------------------
# Each substitution targets one keyed line so shared values like "default"
# (user vs database) never collide. The allow-list host has no key, so it is
# anchored on its inline "# runtime: the warehouse" comment.
H="$HOST" perl -pi -e 's{^(\s*CLICKHOUSE_HOST:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"
H="$HOST" perl -pi -e 's{^(\s*- domain:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"
H="$HOST" perl -pi -e 's{^(\s*- ")[^"]*("\s*#\s*runtime: the warehouse.*)$}{$1.$ENV{H}.$2}e' "$SPEC"

if [ -n "$USER_VAL" ]; then
  H="$USER_VAL" perl -pi -e 's{^(\s*CLICKHOUSE_USER:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"
  H="$USER_VAL" perl -pi -e 's{^(\s*username:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"
fi
[ -z "$PORT" ]     || H="$PORT"     perl -pi -e 's{^(\s*CLICKHOUSE_PORT:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"
[ -z "$DATABASE" ] || H="$DATABASE" perl -pi -e 's{^(\s*CLICKHOUSE_DATABASE:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"
[ -z "$SECURE" ]   || H="$SECURE"   perl -pi -e 's{^(\s*CLICKHOUSE_SECURE:\s*")[^"]*(".*)$}{$1.$ENV{H}.$2}e' "$SPEC"

# --- verify the host landed in exactly the three required places -----------
count="$(grep -c -F "\"$HOST\"" "$SPEC" || true)"
if [ "$count" -ne 3 ]; then
  echo "warning: expected host to appear 3 times, found $count — inspect spec.yaml" >&2
fi

echo "Updated $SPEC:"
grep -nE '^[[:space:]]*(CLICKHOUSE_(HOST|PORT|USER|DATABASE|SECURE):|- domain:|username:|- ".*# runtime: the warehouse)' "$SPEC" \
  | sed 's/^/  /'

# --- re-validate so a drifted/invalid spec never survives this script ------
if command -v sbx >/dev/null 2>&1; then
  echo
  sbx kit validate "$(dirname "$SPEC")"
else
  echo
  echo "note: sbx not on PATH — skipped 'sbx kit validate'"
fi

echo
echo "Next: store the password (never goes in the spec):"
echo "  sbx secret set -g clickhouse"
