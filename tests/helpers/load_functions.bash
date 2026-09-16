#!/usr/bin/env bash
# Loads functions from snapraid-aio-script.sh into the test environment.
# Strips root self-elevation preamble and the trailing trap/main call.

SCRIPT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/snapraid-aio-script.sh"
SOURCED_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.sourced_functions.bash"

# Define command_exists helper since it resides in the preamble
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Regenerate .sourced_functions.bash if missing or older than snapraid-aio-script.sh
if [ ! -f "$SOURCED_FILE" ] || [ "$SCRIPT_FILE" -nt "$SOURCED_FILE" ]; then
  _tmp="${SOURCED_FILE}.tmp.$$"
  awk '
    /^# Identify the \*original\* caller/ { in_body = 1 }
    /^# Set TRAP/                         { in_body = 0 }
    in_body {
      gsub(/\r/, "")
      print
    }
  ' "$SCRIPT_FILE" >"$_tmp" && mv -f "$_tmp" "$SOURCED_FILE"
fi

# shellcheck disable=SC1090
source "$SOURCED_FILE"
