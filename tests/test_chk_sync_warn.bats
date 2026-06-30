#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "chk_sync_warn: SYNC_WARN_THRESHOLD=-1 (disabled) sets DO_SYNC=0" {
  SYNC_WARN_THRESHOLD=-1
  chk_sync_warn
  [ "$DO_SYNC" -eq 0 ]
}

@test "chk_sync_warn: SYNC_WARN_THRESHOLD=0 (always force) sets DO_SYNC=1" {
  SYNC_WARN_THRESHOLD=0
  chk_sync_warn
  [ "$DO_SYNC" -eq 1 ]
}

@test "chk_sync_warn: counter below threshold — increments file, DO_SYNC=0" {
  SYNC_WARN_THRESHOLD=3
  chk_sync_warn
  [ "$DO_SYNC" -eq 0 ]
  [ "$(cat "$SYNC_WARN_FILE")" -eq 1 ]
}

@test "chk_sync_warn: missing counter file treated as 0 — increments to 1, DO_SYNC=0" {
  SYNC_WARN_THRESHOLD=3
  rm -f "$SYNC_WARN_FILE"
  chk_sync_warn || true
  [ "$DO_SYNC" -eq 0 ]
  [ "$(cat "$SYNC_WARN_FILE")" -eq 1 ]
}

@test "chk_sync_warn: counter one below threshold — increments to threshold, DO_SYNC=0" {
  SYNC_WARN_THRESHOLD=3
  echo "2" > "$SYNC_WARN_FILE"
  chk_sync_warn
  [ "$DO_SYNC" -eq 0 ]
  [ "$(cat "$SYNC_WARN_FILE")" -eq 3 ]
}

@test "chk_sync_warn: counter at threshold — forces DO_SYNC=1" {
  SYNC_WARN_THRESHOLD=3
  echo "3" > "$SYNC_WARN_FILE"
  chk_sync_warn
  [ "$DO_SYNC" -eq 1 ]
}
