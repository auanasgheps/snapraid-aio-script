#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "chk_updated: zero updates sets DO_SYNC=1" {
  UPDATE_COUNT=0
  chk_updated
  [ "$DO_SYNC" -eq 1 ]
}

@test "chk_updated: updates below threshold sets DO_SYNC=1" {
  UPDATE_COUNT=10
  UP_THRESHOLD=500
  chk_updated
  [ "$DO_SYNC" -eq 1 ]
}

@test "chk_updated: updates at threshold sets CHK_FAIL=1" {
  UPDATE_COUNT=500
  UP_THRESHOLD=500
  chk_updated
  [ "$CHK_FAIL" -eq 1 ]
  [ "$DO_SYNC" -eq 0 ]
}
