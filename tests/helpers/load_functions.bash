#!/usr/bin/env bash
# Strip the root-elevation block (lines 1-27) and the last 4 lines
# (blank, "# Set TRAP" comment, trap call, main "$@") before sourcing.
# This prevents the EXIT trap from registering in the test shell.

SCRIPT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/snapraid-aio-script.sh"

_tmp=$(mktemp)
awk '{lines[NR]=$0} END{for(i=28;i<=NR-4;i++){gsub(/\r/,"",lines[i]); print lines[i]}}' \
  "$SCRIPT_FILE" > "$_tmp"
# shellcheck disable=SC1090
source "$_tmp"
rm -f "$_tmp"
