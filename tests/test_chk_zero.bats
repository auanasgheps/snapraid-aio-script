#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  SNAPRAID_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/snapraid"
  SNAPRAID_CONF="/dev/null"
  MOCK_SNAPRAID_LOG="$BATS_TEST_TMPDIR/snapraid_mock.log"
  export SNAPRAID_BIN SNAPRAID_CONF MOCK_SNAPRAID_LOG
  rm -f "$MOCK_SNAPRAID_LOG"
}

@test "chk_zero: no zero sub-second timestamps skips touch" {
  export MOCK_SCENARIO=status_synced
  run chk_zero
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No zero sub-second timestamp file found." ]]
  [[ "$output" =~ "TOUCH finished [skipped]" ]]
  if [ -f "$MOCK_SNAPRAID_LOG" ]; then
    run grep "touch" "$MOCK_SNAPRAID_LOG"
    [ "$status" -ne 0 ]
  fi
}

@test "chk_zero: detects zero sub-second timestamps and executes touch" {
  export MOCK_SCENARIO=status_zero_subsecond
  run chk_zero
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 15 files with zero sub-second timestamp." ]]
  [[ "$output" =~ "Running TOUCH job to timestamp." ]]
  [[ "$output" =~ "TOUCH finished" ]]
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep "touch" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}

@test "chk_zero: matches singular 'with a zero sub-second timestamp' and executes touch" {
  export MOCK_SCENARIO=status_singular
  run chk_zero
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Found 1 files with a zero sub-second timestamp." ]]
  [[ "$output" =~ "Running TOUCH job to timestamp." ]]
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep "touch" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}
