#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

setup() {
  SNAPRAID_LOG="$BATS_TEST_TMPDIR/snapraid.log"
  PRIORITY=""
  LOGMESSAGE=""
}

@test "mklog: writes formatted INFO entry to SNAPRAID_LOG" {
  mklog "INFO: SnapRAID DIFF started"
  [ -f "$SNAPRAID_LOG" ]
  log_content=$(cat "$SNAPRAID_LOG")
  [[ "$log_content" =~ ^\[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
  [[ "$log_content" =~ INFO:\ \'SnapRAID\ DIFF\ started\'$ ]]
}

@test "mklog: writes formatted WARN entry to SNAPRAID_LOG" {
  mklog "WARN: Parity file not found!"
  log_content=$(cat "$SNAPRAID_LOG")
  [[ "$log_content" =~ WARN:\ \'Parity\ file\ not\ found!\'$ ]]
}

@test "mklog: writes formatted DEBUG entry to SNAPRAID_LOG" {
  mklog "DEBUG: verbose trace details"
  log_content=$(cat "$SNAPRAID_LOG")
  [[ "$log_content" =~ DEBUG:\ \'verbose\ trace\ details\'$ ]]
}

@test "mklog: appends multiple log messages in order" {
  mklog "INFO: First line"
  mklog "WARN: Second line"
  run wc -l <"$SNAPRAID_LOG"
  [ "$output" -eq 2 ]
  line1=$(sed -n '1p' "$SNAPRAID_LOG")
  line2=$(sed -n '2p' "$SNAPRAID_LOG")
  [[ "$line1" =~ INFO:\ \'First\ line\'$ ]]
  [[ "$line2" =~ WARN:\ \'Second\ line\'$ ]]
}
