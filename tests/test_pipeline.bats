#!/usr/bin/env bats
# End-to-end tests chaining get_counts -> chk_del / chk_updated using real fixture files.
# These cover the paths that inline unit tests can't: actual diff output parsing feeding
# the threshold checks.

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

@test "pipeline: dels_below_thresh fixture produces DO_SYNC=1" {
  cp "$FIXTURES_DIR/diff_dels_below_thresh.txt" "$TMP_OUTPUT"
  get_counts || true
  [ "$DEL_COUNT" -eq 3 ]
  chk_del
  [ "$DO_SYNC" -eq 1 ]
  [ "$CHK_FAIL" -eq 0 ]
}

@test "pipeline: dels_above_thresh fixture produces CHK_FAIL=1" {
  cp "$FIXTURES_DIR/diff_dels_above_thresh.txt" "$TMP_OUTPUT"
  DEL_THRESHOLD=500
  ADD_DEL_THRESHOLD=0
  get_counts || true
  [ "$DEL_COUNT" -eq 600 ]
  chk_del
  [ "$CHK_FAIL" -eq 1 ]
  [ "$DO_SYNC" -eq 0 ]
}

@test "pipeline: ratio_saves_sync fixture — 600 dels + 550 adds overrides threshold" {
  cp "$FIXTURES_DIR/diff_ratio_saves_sync.txt" "$TMP_OUTPUT"
  DEL_THRESHOLD=500
  ADD_DEL_THRESHOLD=0.5
  get_counts || true
  [ "$DEL_COUNT" -eq 600 ]
  [ "$ADD_COUNT" -eq 550 ]
  chk_del
  [ "$DO_SYNC" -eq 1 ]
  [ "$CHK_FAIL" -eq 0 ]
}

@test "pipeline: updates_above_thresh fixture produces CHK_FAIL=1" {
  cp "$FIXTURES_DIR/diff_updates_above_thresh.txt" "$TMP_OUTPUT"
  UP_THRESHOLD=2
  get_counts || true
  [ "$UPDATE_COUNT" -eq 3 ]
  chk_updated
  [ "$CHK_FAIL" -eq 1 ]
  [ "$DO_SYNC" -eq 0 ]
}
