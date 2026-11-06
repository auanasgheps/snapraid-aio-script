#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"

@test "extract_snapraid_info: simple conf — 1 parity, 2 content files" {
  SNAPRAID_CONF="$FIXTURES_DIR/snapraid_conf_simple.conf"
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 1 ]
  [ "${#CONTENT_FILES[@]}" -eq 2 ]
  [ "${PARITY_FILES[0]}" = "/mnt/parity1/snapraid.parity" ]
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

@test "extract_snapraid_info: advanced conf — extracts multi-line, comma-split, and z-parity" {
  SNAPRAID_CONF="$FIXTURES_DIR/snapraid_conf_advanced.conf"
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 5 ]
  [ "${PARITY_FILES[0]}" = "/mnt/parity1/snapraid.parity" ]
  [ "${PARITY_FILES[1]}" = "/mnt/parity2/snapraid.2-parity" ]
  [ "${PARITY_FILES[2]}" = "/mnt/parity3a/snapraid.3-parity" ]
  [ "${PARITY_FILES[3]}" = "/mnt/parity3b/snapraid.3-parity" ]
  [ "${PARITY_FILES[4]}" = "/mnt/parityz/snapraid.z-parity" ]

  [ "${#CONTENT_FILES[@]}" -eq 3 ]
  [ "${CONTENT_FILES[0]}" = "/mnt/disk1/.snapraid.content" ]
  [ "${CONTENT_FILES[1]}" = "/mnt/disk2/.snapraid.content" ]
  [ "${CONTENT_FILES[2]}" = "/var/snapraid.content" ]
}

@test "extract_snapraid_info: ignores commented lines starting with # and ;" {
  SNAPRAID_CONF="$BATS_TEST_TMPDIR/comments.conf"
  cat <<'EOF' >"$SNAPRAID_CONF"
# parity /mnt/commented_hash/snapraid.parity
; parity /mnt/commented_semi/snapraid.parity
parity /mnt/real/snapraid.parity
# content /mnt/commented_hash/snapraid.content
; content /mnt/commented_semi/snapraid.content
content /mnt/real/snapraid.content
EOF
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 1 ]
  [ "${PARITY_FILES[0]}" = "/mnt/real/snapraid.parity" ]
  [ "${#CONTENT_FILES[@]}" -eq 1 ]
  [ "${CONTENT_FILES[0]}" = "/mnt/real/snapraid.content" ]
}

@test "extract_snapraid_info: trims leading and trailing whitespace from file paths" {
  SNAPRAID_CONF="$BATS_TEST_TMPDIR/spaces.conf"
  cat <<'EOF' >"$SNAPRAID_CONF"
parity   /mnt/padded_parity/snapraid.parity   
content /mnt/padded_content/snapraid.content   
EOF
  extract_snapraid_info
  [ "${PARITY_FILES[0]}" = "/mnt/padded_parity/snapraid.parity" ]
  [ "${CONTENT_FILES[0]}" = "/mnt/padded_content/snapraid.content" ]
}

@test "extract_snapraid_info: full 6-parity conf — extracts all 6 parity levels" {
  SNAPRAID_CONF="$FIXTURES_DIR/snapraid_conf_6_parity.conf"
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 6 ]
  [ "${PARITY_FILES[0]}" = "/mnt/parity1/snapraid.parity" ]
  [ "${PARITY_FILES[1]}" = "/mnt/parity2/snapraid.2-parity" ]
  [ "${PARITY_FILES[2]}" = "/mnt/parity3/snapraid.3-parity" ]
  [ "${PARITY_FILES[3]}" = "/mnt/parity4/snapraid.4-parity" ]
  [ "${PARITY_FILES[4]}" = "/mnt/parity5/snapraid.5-parity" ]
  [ "${PARITY_FILES[5]}" = "/mnt/parity6/snapraid.6-parity" ]

  [ "${#CONTENT_FILES[@]}" -eq 3 ]
  [ "${CONTENT_FILES[0]}" = "/mnt/disk1/.snapraid.content" ]
  [ "${CONTENT_FILES[1]}" = "/mnt/disk2/.snapraid.content" ]
  [ "${CONTENT_FILES[2]}" = "/var/snapraid.content" ]
}

@test "extract_snapraid_info: tab-separated parity and content entries" {
  SNAPRAID_CONF="$BATS_TEST_TMPDIR/tabs.conf"
  printf "parity\t/mnt/tab_parity1/snapraid.parity\n" >"$SNAPRAID_CONF"
  printf "2-parity\t/mnt/tab_parity2/snapraid.2-parity\n" >>"$SNAPRAID_CONF"
  printf "3-parity\t/mnt/tab_parity3/snapraid.3-parity\n" >>"$SNAPRAID_CONF"
  printf "content\t/mnt/tab_content/snapraid.content\n" >>"$SNAPRAID_CONF"

  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 3 ]
  [ "${PARITY_FILES[0]}" = "/mnt/tab_parity1/snapraid.parity" ]
  [ "${PARITY_FILES[1]}" = "/mnt/tab_parity2/snapraid.2-parity" ]
  [ "${PARITY_FILES[2]}" = "/mnt/tab_parity3/snapraid.3-parity" ]
  [ "${#CONTENT_FILES[@]}" -eq 1 ]
  [ "${CONTENT_FILES[0]}" = "/mnt/tab_content/snapraid.content" ]
}

@test "extract_snapraid_info: rejects false keyword matches like parity_data or indented comments" {
  SNAPRAID_CONF="$BATS_TEST_TMPDIR/false_matches.conf"
  cat <<'EOF' >"$SNAPRAID_CONF"
   # parity /mnt/commented/snapraid.parity
   ; 2-parity /mnt/commented/snapraid.2-parity
data parity_disk /mnt/data1
disk parity /mnt/data2
parity_extra /mnt/invalid/snapraid.parity
parity /mnt/valid/snapraid.parity
content /mnt/valid/snapraid.content
content_extra /mnt/invalid/snapraid.content
EOF
  extract_snapraid_info
  [ "${#PARITY_FILES[@]}" -eq 1 ]
  [ "${PARITY_FILES[0]}" = "/mnt/valid/snapraid.parity" ]
  [ "${#CONTENT_FILES[@]}" -eq 1 ]
  [ "${CONTENT_FILES[0]}" = "/mnt/valid/snapraid.content" ]
}
