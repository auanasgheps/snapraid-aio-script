#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

@test "get_counts: clean diff produces all-zero counts" {
  cp "$FIXTURES_DIR/diff_clean.txt" "$TMP_OUTPUT"
  get_counts || true
  [ "$ADD_COUNT"    -eq 0 ]
  [ "$DEL_COUNT"    -eq 0 ]
  [ "$UPDATE_COUNT" -eq 0 ]
  [ "$MOVE_COUNT"   -eq 0 ]
  [ "$EQ_COUNT"     -eq 0 ]
  [ "$COPY_COUNT"   -eq 0 ]
}

@test "get_counts: 5 adds only — ADD_COUNT=5, others zero" {
  cp "$FIXTURES_DIR/diff_adds_only.txt" "$TMP_OUTPUT"
  get_counts || true
  [ "$ADD_COUNT"    -eq 5 ]
  [ "$DEL_COUNT"    -eq 0 ]
  [ "$UPDATE_COUNT" -eq 0 ]
  [ "$EQ_COUNT"     -eq 5 ]
}

@test "get_counts: IGNORE_PATTERN filters matching add entries" {
  # Write a fixture with one .tmp add that should be ignored
  printf 'add /data/d1/cache/file.tmp\nadd /data/d1/normal.mkv\n   10 equal\n   0 copied\n' > "$TMP_OUTPUT"
  IGNORE_PATTERN=("*.tmp")
  get_counts
  # Only the .mkv survives; .tmp is ignored
  [ "$ADD_COUNT" -eq 1 ]
}
