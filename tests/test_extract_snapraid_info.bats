#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

@test "extract_snapraid_info: simple conf — 1 parity, 2 content files" {
  SNAPRAID_CONF="$FIXTURES_DIR/snapraid_conf_simple.conf"
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}"  -eq 1 ]
  [ "${#CONTENT_FILES[@]}" -eq 2 ]
  [ "${PARITY_FILES[0]}"  = "/mnt/parity1/snapraid.parity" ]
  [ "${CONTENT_FILES[0]}" = "/mnt/disk1/.snapraid.content" ]
  [ "${CONTENT_FILES[1]}" = "/mnt/disk2/.snapraid.content" ]
}

@test "extract_snapraid_info: multi-parity conf — 3 parity files" {
  SNAPRAID_CONF="$FIXTURES_DIR/snapraid_conf_multi_parity.conf"
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 3 ]
  [ "${PARITY_FILES[0]}" = "/mnt/parity1/snapraid.parity" ]
  [ "${PARITY_FILES[1]}" = "/mnt/parity2/snapraid.parity" ]
  [ "${PARITY_FILES[2]}" = "/mnt/parity3/snapraid.parity" ]
}
