#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  true >"$TMP_OUTPUT"
  EMAIL_SUBJECT_PREFIX=""
  PARITY_FILES=()
  CONTENT_FILES=()
}

@test "sanity_check: all parity and content files present exits 0" {
  touch "$BATS_TEST_TMPDIR/snapraid.parity"
  touch "$BATS_TEST_TMPDIR/snapraid.content"
  PARITY_FILES=("$BATS_TEST_TMPDIR/snapraid.parity")
  CONTENT_FILES=("$BATS_TEST_TMPDIR/snapraid.content")

  run sanity_check
  [ "$status" -eq 0 ]
  [[ "$output" =~ "All parity files found." ]]
  [[ "$output" =~ "All content files found." ]]
}

@test "sanity_check: missing parity file writes error and exits 1" {
  touch "$BATS_TEST_TMPDIR/snapraid.content"
  PARITY_FILES=("$BATS_TEST_TMPDIR/missing.parity")
  CONTENT_FILES=("$BATS_TEST_TMPDIR/snapraid.content")

  run sanity_check
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ERROR - Parity file" ]]
  run grep -q "ERROR - Parity file" "$TMP_OUTPUT"
  [ "$status" -eq 0 ]
}

@test "sanity_check: missing content file writes error and exits 1" {
  touch "$BATS_TEST_TMPDIR/snapraid.parity"
  PARITY_FILES=("$BATS_TEST_TMPDIR/snapraid.parity")
  CONTENT_FILES=("$BATS_TEST_TMPDIR/missing.content")

  run sanity_check
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ERROR - Content file" ]]
  run grep -q "ERROR - Content file" "$TMP_OUTPUT"
  [ "$status" -eq 0 ]
}

@test "sanity_check: multiple parity files with second missing exits 1" {
  touch "$BATS_TEST_TMPDIR/p1.parity"
  touch "$BATS_TEST_TMPDIR/c1.content"
  PARITY_FILES=("$BATS_TEST_TMPDIR/p1.parity" "$BATS_TEST_TMPDIR/p2_missing.parity")
  CONTENT_FILES=("$BATS_TEST_TMPDIR/c1.content")

  run sanity_check
  [ "$status" -eq 1 ]
  [[ "$output" =~ "p2_missing.parity" ]]
}

@test "sanity_check: multiple content files with second missing exits 1" {
  touch "$BATS_TEST_TMPDIR/p1.parity"
  touch "$BATS_TEST_TMPDIR/c1.content"
  PARITY_FILES=("$BATS_TEST_TMPDIR/p1.parity")
  CONTENT_FILES=("$BATS_TEST_TMPDIR/c1.content" "$BATS_TEST_TMPDIR/c2_missing.content")

  run sanity_check
  [ "$status" -eq 1 ]
  [[ "$output" =~ "c2_missing.content" ]]
}
