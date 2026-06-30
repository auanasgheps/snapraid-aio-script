#!/usr/bin/env bash
# Loaded by every .bats file via: load 'helpers/test_helper'
# Sources all script functions, stubs side-effects, and provides setup/teardown.

source "$(dirname "${BASH_SOURCE[0]}")/load_functions.bash"

# ---- Stub side-effecting functions ----
# These override the sourced versions and must be declared AFTER load_functions.

mklog()                 { :; }
mklog_noconfig()        { :; }
output_to_file_screen() { :; }
close_output_and_wait() { :; }
notify_success()        { :; }
notify_warning()        { :; }

# Sentinel for chk_scrub_settings tests: mirrors real run_scrub which deletes the counter file.
run_scrub() {
  RUN_SCRUB_CALLED=1
  rm -f "$SCRUB_COUNT_FILE"
}

# ---- Per-test setup ----
setup() {
  # Isolate all disk state to a per-test temp directory (auto-cleaned by bats)
  SYNC_WARN_FILE="$BATS_TEST_TMPDIR/sync_warn_count"
  SCRUB_COUNT_FILE="$BATS_TEST_TMPDIR/scrub_count"
  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  SNAPRAID_LOG="$BATS_TEST_TMPDIR/snapraid.log"

  # Reset config variables to script defaults
  DEL_THRESHOLD=500
  UP_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  SYNC_WARN_THRESHOLD=-1
  SCRUB_DELAYED_RUN=0
  SCRUB_PERCENT=5
  SCRUB_AGE=10
  SCRUB_NEW=0
  PREHASH=1
  RETENTION_DAYS=0

  # Reset computed state
  CHK_FAIL=0
  DO_SYNC=0
  ADD_COUNT=0
  DEL_COUNT=0
  UPDATE_COUNT=0
  MOVE_COUNT=0
  COPY_COUNT=0
  EQ_COUNT=0
  ADD_DEL_RATIO=0
  JOBS_DONE=""
  RUN_SCRUB_CALLED=0
  IGNORE_PATTERN=()

  # Pre-create count files with 0 so sed doesn't exit 2 on missing files
  echo "0" > "$SYNC_WARN_FILE"
  echo "0" > "$SCRUB_COUNT_FILE"
  true > "$TMP_OUTPUT"
}

teardown() { :; }
