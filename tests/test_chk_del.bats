#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "chk_del: zero deletes sets DO_SYNC=1" {
  DEL_COUNT=0
  chk_del
  [ "$DO_SYNC" -eq 1 ]
}

@test "chk_del: deletes below threshold sets DO_SYNC=1" {
  DEL_COUNT=3
  DEL_THRESHOLD=500
  chk_del
  [ "$DO_SYNC" -eq 1 ]
}

@test "chk_del: deletes at threshold with ADD_DEL_THRESHOLD=0 sets CHK_FAIL=1" {
  DEL_COUNT=500
  DEL_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  chk_del
  [ "$CHK_FAIL" -eq 1 ]
  [ "$DO_SYNC" -eq 0 ]
}

@test "chk_del: deletes above threshold but ratio exceeds ADD_DEL_THRESHOLD sets DO_SYNC=1" {
  DEL_COUNT=600
  DEL_THRESHOLD=500
  ADD_COUNT=550
  ADD_DEL_THRESHOLD=0.5
  chk_del
  [ "$DO_SYNC" -eq 1 ]
}

@test "chk_del: deletes above threshold and ratio below ADD_DEL_THRESHOLD sets CHK_FAIL=1" {
  DEL_COUNT=600
  DEL_THRESHOLD=500
  ADD_COUNT=100
  ADD_DEL_THRESHOLD=0.5
  chk_del
  [ "$CHK_FAIL" -eq 1 ]
  [ "$DO_SYNC" -eq 0 ]
}
