#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

# Override stubs to record invocations
notify_success() {
  NOTIFY_SUCCESS_CALLED=1
}

notify_warning() {
  NOTIFY_WARNING_CALLED=1
}

setup() {
  SYNC_MARKER="SYNC -"
  SCRUB_MARKER="SCRUB -"
  EMAIL_SUBJECT_PREFIX=""
  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  true >"$TMP_OUTPUT"

  DEL_THRESHOLD=500
  UP_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  ADD_DEL_RATIO=0

  CHK_FAIL=0
  DO_SYNC=0
  JOBS_DONE="DIFF"
  ADD_COUNT=0
  DEL_COUNT=0
  UPDATE_COUNT=0
  MOVE_COUNT=0
  COPY_COUNT=0
  EQ_COUNT=0

  NOTIFY_SUCCESS_CALLED=0
  NOTIFY_WARNING_CALLED=0
  SUBJECT=""
  NOTIFY_OUTPUT=""
  MSG=""
}

@test "prepare_output: clean run triggers notify_success with [COMPLETED]" {
  JOBS_DONE="DIFF"
  CHK_FAIL=0
  prepare_output
  [ "$NOTIFY_SUCCESS_CALLED" -eq 1 ]
  [ "$NOTIFY_WARNING_CALLED" -eq 0 ]
  [[ "$SUBJECT" =~ \[COMPLETED\]\ DIFF\ Jobs ]]
}

@test "prepare_output: SYNC and SCRUB with valid markers triggers notify_success" {
  JOBS_DONE="DIFF + SYNC + SCRUB"
  CHK_FAIL=0
  echo "SYNC - Everything OK" >>"$TMP_OUTPUT"
  echo "SCRUB - Everything OK" >>"$TMP_OUTPUT"
  prepare_output
  [ "$NOTIFY_SUCCESS_CALLED" -eq 1 ]
  [ "$NOTIFY_WARNING_CALLED" -eq 0 ]
  [[ "$SUBJECT" =~ \[COMPLETED\]\ DIFF\ \+\ SYNC\ \+\ SCRUB\ Jobs ]]
}

@test "prepare_output: SYNC in JOBS_DONE without SYNC_MARKER triggers [SEVERE WARNING]" {
  JOBS_DONE="DIFF + SYNC"
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [ "$NOTIFY_SUCCESS_CALLED" -eq 0 ]
  [[ "$SUBJECT" =~ \[SEVERE\ WARNING\]\ SYNC\ job\ ran\ but\ did\ not\ complete\ successfully ]]
}

@test "prepare_output: SCRUB in JOBS_DONE without SCRUB_MARKER triggers [SEVERE WARNING]" {
  JOBS_DONE="DIFF + SCRUB"
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [ "$NOTIFY_SUCCESS_CALLED" -eq 0 ]
  [[ "$SUBJECT" =~ \[SEVERE\ WARNING\]\ SCRUB\ job\ ran\ but\ did\ not\ complete\ successfully ]]
}

@test "prepare_output: CHK_FAIL with deleted threshold reached (no sync) sets deleted violation" {
  CHK_FAIL=1
  DEL_COUNT=600
  DEL_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  DO_SYNC=0
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Deleted files (600) / (500) violation" ]]
}

@test "prepare_output: CHK_FAIL with deleted threshold and ratio violation (no sync)" {
  CHK_FAIL=1
  DEL_COUNT=600
  DEL_THRESHOLD=500
  ADD_DEL_THRESHOLD=0.5
  ADD_DEL_RATIO=0.10
  DO_SYNC=0
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Multiple violations - Deleted files (600) / (500) and add/delete ratio (0.10) / (0.5)" ]]
}

@test "prepare_output: CHK_FAIL with deleted threshold reached (forced sync) sets forced sync violation" {
  CHK_FAIL=1
  DEL_COUNT=600
  DEL_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  DO_SYNC=1
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Forced sync with deleted files (600) / (500) violation" ]]
}

@test "prepare_output: CHK_FAIL with updated threshold reached (no sync) sets changed files violation" {
  CHK_FAIL=1
  UPDATE_COUNT=600
  UP_THRESHOLD=500
  DO_SYNC=0
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Changed files (600) / (500) violation" ]]
}

@test "prepare_output: CHK_FAIL with updated threshold reached (forced sync) sets forced sync violation" {
  CHK_FAIL=1
  UPDATE_COUNT=600
  UP_THRESHOLD=500
  DO_SYNC=1
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Forced sync with changed files (600) / (500) violation" ]]
}

@test "prepare_output: CHK_FAIL with both deleted and updated violations (no sync)" {
  CHK_FAIL=1
  DEL_COUNT=600
  DEL_THRESHOLD=500
  UPDATE_COUNT=700
  UP_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  DO_SYNC=0
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Multiple violations - Deleted files (600) / (500) and changed files (700) / (500)" ]]
}

@test "prepare_output: CHK_FAIL with both deleted and updated violations (forced sync)" {
  CHK_FAIL=1
  DEL_COUNT=600
  DEL_THRESHOLD=500
  UPDATE_COUNT=700
  UP_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  DO_SYNC=1
  prepare_output
  [ "$NOTIFY_WARNING_CALLED" -eq 1 ]
  [[ "$SUBJECT" =~ "Sync forced with multiple violations - Deleted files (600) / (500) and changed files (700) / (500)" ]]
}
