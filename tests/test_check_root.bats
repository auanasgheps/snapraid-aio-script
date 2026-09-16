#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  EMAIL_SUBJECT_PREFIX=""
  SUBJECT=""
  NOTIFY_OUTPUT=""
}

@test "check_root: running as root succeeds silently" {
  # Stub id to return 0 (root)
  id() {
    if [ "$1" = "-u" ]; then
      echo 0
    else
      command id "$@"
    fi
  }
  run check_root
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_root: running as non-root triggers fatal error and exits 1" {
  # Stub id to return 1000 (non-root)
  id() {
    if [ "$1" = "-u" ]; then
      echo 1000
    else
      command id "$@"
    fi
  }
  run check_root
  [ "$status" -eq 1 ]
  [[ "$output" =~ "This script must be run as root. Exiting." ]]
}
