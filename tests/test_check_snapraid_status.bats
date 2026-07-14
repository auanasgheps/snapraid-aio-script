#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  SNAPRAID_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/snapraid"
  SNAPRAID_CONF="/dev/null"
  BYPASS_SYNC_ERROR=false
  SNAPRAID_STATUS=""
  export MOCK_SCENARIO=status_synced
}

@test "check_snapraid_status: synced array sets SNAPRAID_STATUS=0" {
  export MOCK_SCENARIO=status_synced
  check_snapraid_status
  [ "$SNAPRAID_STATUS" -eq 0 ]
}

@test "check_snapraid_status: not-synced array without bypass sets SNAPRAID_STATUS=1" {
  export MOCK_SCENARIO=status_not_synced
  check_snapraid_status
  [ "$SNAPRAID_STATUS" -eq 1 ]
}

@test "check_snapraid_status: not-synced array with bypass sets SNAPRAID_STATUS=0" {
  export MOCK_SCENARIO=status_not_synced
  BYPASS_SYNC_ERROR=true
  check_snapraid_status
  [ "$SNAPRAID_STATUS" -eq 0 ]
}

@test "check_snapraid_status: unknown status sets SNAPRAID_STATUS=2" {
  export MOCK_SCENARIO=status_unknown
  check_snapraid_status
  [ "$SNAPRAID_STATUS" -eq 2 ]
}

@test "check_snapraid_status: unknown status with bypass still sets SNAPRAID_STATUS=2" {
  export MOCK_SCENARIO=status_unknown
  BYPASS_SYNC_ERROR=true
  check_snapraid_status
  [ "$SNAPRAID_STATUS" -eq 2 ]
}
