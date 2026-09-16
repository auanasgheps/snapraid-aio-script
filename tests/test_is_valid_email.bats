#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "is_valid_email: valid standard email returns 0" {
  run is_valid_email "user@example.com"
  [ "$status" -eq 0 ]
}

@test "is_valid_email: valid email with subdomain returns 0" {
  run is_valid_email "user@mail.example.com"
  [ "$status" -eq 0 ]
}

@test "is_valid_email: valid email with plus tag returns 0" {
  run is_valid_email "user+alerts@example.com"
  [ "$status" -eq 0 ]
}

@test "is_valid_email: valid email with dots and underscores returns 0" {
  run is_valid_email "first.last_name@example.co.uk"
  [ "$status" -eq 0 ]
}

@test "is_valid_email: valid email with digits in domain and user returns 0" {
  run is_valid_email "user123@sub42.domain99.org"
  [ "$status" -eq 0 ]
}

@test "is_valid_email: empty string returns 1" {
  run is_valid_email ""
  [ "$status" -eq 1 ]
}

@test "is_valid_email: whitespace only returns 1" {
  run is_valid_email "   "
  [ "$status" -eq 1 ]
}

@test "is_valid_email: email with embedded space returns 1" {
  run is_valid_email "user @example.com"
  [ "$status" -eq 1 ]
}

@test "is_valid_email: missing @ returns 1" {
  run is_valid_email "userexample.com"
  [ "$status" -eq 1 ]
}

@test "is_valid_email: missing user before @ returns 1" {
  run is_valid_email "@example.com"
  [ "$status" -eq 1 ]
}

@test "is_valid_email: missing domain after @ returns 1" {
  run is_valid_email "user@"
  [ "$status" -eq 1 ]
}

@test "is_valid_email: single letter TLD returns 1" {
  run is_valid_email "user@domain.c"
  [ "$status" -eq 1 ]
}

@test "is_valid_email: no argument returns 1" {
  run is_valid_email
  [ "$status" -eq 1 ]
}
