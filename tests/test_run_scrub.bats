#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

# Restore real run_scrub from sourced functions to bypass test_helper stub
# shellcheck source=/dev/null
source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/.sourced_functions.bash"

# Re-stub side-effecting functions overwritten by .sourced_functions.bash
mklog() { :; }
mklog_noconfig() { :; }
output_to_file_screen() { :; }
close_output_and_wait() { :; }
notify_success() { :; }
notify_warning() { :; }

setup() {
  SNAPRAID_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/snapraid"
  SNAPRAID_CONF="/dev/null"
  MOCK_SNAPRAID_LOG="${BATS_TEST_TMPDIR:-/tmp}/snapraid_mock.log"
  export SNAPRAID_BIN SNAPRAID_CONF MOCK_SNAPRAID_LOG
  rm -f "$MOCK_SNAPRAID_LOG"

  OUT=1
  ERROR=2
  export OUT ERROR

  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  SCRUB_COUNT_FILE="$BATS_TEST_TMPDIR/scrub_count"
  echo "3" >"$SCRUB_COUNT_FILE"

  SCRUB_NEW=0
  SCRUB_PERCENT=5
  SCRUB_AGE=10
  SCRUB_MARKER="SCRUB -"
  JOBS_DONE="DIFF"
}

@test "run_scrub: standard scrub executes snapraid and updates markers" {
  cat "$(dirname "$BATS_TEST_FILENAME")/fixtures/scrub_ok.txt" >"$TMP_OUTPUT"

  run_scrub
  [ "$JOBS_DONE" = "DIFF + SCRUB" ]
  [ ! -f "$SCRUB_COUNT_FILE" ]

  # Check that Everything OK was converted to SCRUB - Everything OK
  run grep "^SCRUB - Everything OK" "$TMP_OUTPUT"
  [ "$status" -eq 0 ]

  # Verify mock snapraid arguments
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep -- "-p 5 -o 10 -q scrub" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}

@test "run_scrub: SCRUB_NEW=1 runs both new blocks and previous blocks" {
  SCRUB_NEW=1
  cat "$(dirname "$BATS_TEST_FILENAME")/fixtures/scrub_ok.txt" >"$TMP_OUTPUT"

  run run_scrub
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SCRUB New Blocks" ]]
  [[ "$output" =~ "SCRUB Previous Blocks" ]]

  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep -- "-p new -q scrub" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
  run grep -- "-p 5 -o 10 -q scrub" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}

@test "run_scrub: marks 'Nothing to do' with SCRUB marker" {
  echo "Nothing to do" >"$TMP_OUTPUT"

  run run_scrub
  [ "$status" -eq 0 ]

  run grep "^SCRUB - Nothing to do" "$TMP_OUTPUT"
  [ "$status" -eq 0 ]
}
