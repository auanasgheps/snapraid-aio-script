#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "chk_scrub_settings: SCRUB_DELAYED_RUN=0 runs scrub immediately" {
  SCRUB_DELAYED_RUN=0
  # count=0 >= threshold=0, so run_scrub should be called
  chk_scrub_settings
  [ "$RUN_SCRUB_CALLED" -eq 1 ]
}

@test "chk_scrub_settings: counter below threshold — increments file, no scrub" {
  SCRUB_DELAYED_RUN=3
  # No count file — starts at 0, becomes 1
  chk_scrub_settings
  [ "$RUN_SCRUB_CALLED" -eq 0 ]
  [ "$(cat "$SCRUB_COUNT_FILE")" -eq 1 ]
}

@test "chk_scrub_settings: counter one below threshold — increments to threshold, no scrub yet" {
  SCRUB_DELAYED_RUN=3
  echo "2" > "$SCRUB_COUNT_FILE"
  chk_scrub_settings
  [ "$RUN_SCRUB_CALLED" -eq 0 ]
  [ "$(cat "$SCRUB_COUNT_FILE")" -eq 3 ]
}

@test "chk_scrub_settings: counter at threshold — runs scrub" {
  SCRUB_DELAYED_RUN=3
  echo "3" > "$SCRUB_COUNT_FILE"
  chk_scrub_settings
  [ "$RUN_SCRUB_CALLED" -eq 1 ]
}
