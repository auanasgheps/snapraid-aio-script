#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "search_conf_files: non-existent directory returns 1" {
  run search_conf_files "/nonexistent/path/that/does/not/exist"
  [ "$status" -eq 1 ]
}

@test "search_conf_files: directory with no matching files returns 1" {
  local dir="$BATS_TEST_TMPDIR/empty_snapraid"
  mkdir -p "$dir"
  run search_conf_files "$dir"
  [ "$status" -eq 1 ]
}

@test "search_conf_files: exactly one matching file returns 0 and sets SNAPRAID_CONF" {
  local dir="$BATS_TEST_TMPDIR/one_conf"
  mkdir -p "$dir"
  touch "$dir/omv-snapraid-abc123.conf"
  # Call without 'run' so variable side-effects persist
  search_conf_files "$dir"
  [ $? -eq 0 ]
  [ "$SNAPRAID_CONF" = "$dir/omv-snapraid-abc123.conf" ]
}

@test "search_conf_files: multiple matching files returns 2" {
  local dir="$BATS_TEST_TMPDIR/multi_conf"
  mkdir -p "$dir"
  touch "$dir/omv-snapraid-aaa.conf"
  touch "$dir/omv-snapraid-bbb.conf"
  run search_conf_files "$dir"
  [ "$status" -eq 2 ]
}
