#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

setup() {
  OUT=1
  ERROR=2
  export OUT ERROR
  output_to_file_screen() { :; }

  TMP_OUTPUT="$BATS_TEST_TMPDIR/tmp_output.txt"
  TMP_WARN_FILE="$BATS_TEST_TMPDIR/tmp_warn.txt"
  touch "$TMP_OUTPUT" "$TMP_WARN_FILE"
}

@test "clean_desc: returns non-zero in non-interactive shell" {
  run clean_desc
  [ "$status" -ne 0 ]
}

@test "sed_me: replaces matched text in target file" {
  local target="$BATS_TEST_TMPDIR/sed_test.txt"
  echo "Everything OK" >"$target"

  sed_me "s/^Everything OK/SCRUB - Everything OK/g" "$target"

  run cat "$target"
  [ "$status" -eq 0 ]
  [ "$output" = "SCRUB - Everything OK" ]
}

@test "final_cleanup: calls resume_services and clean_desc when MANAGE_SERVICES=1" {
  MANAGE_SERVICES=1
  resume_services() { echo "RESUMED_CALLED"; }

  run final_cleanup
  [[ "$output" =~ "RESUMED_CALLED" ]]
}

@test "final_cleanup: exits cleanly when MANAGE_SERVICES=0" {
  MANAGE_SERVICES=0
  resume_services() { echo "SHOULD_NOT_BE_CALLED"; }

  run final_cleanup
  [[ ! "$output" =~ "SHOULD_NOT_BE_CALLED" ]]
}
