#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "trim_log: collapses TOUCH block keeping only boundary lines" {
  input=$(
    cat <<'EOF'
Header line before touch
Running TOUCH job to timestamp [Wed Sep 16 09:00:00 2026]
touching file /mnt/disk1/file1
touching file /mnt/disk2/file2
TOUCH finished [0m 10s]
Footer line after touch
EOF
  )
  run trim_log <<<"$input"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Header line before touch" ]
  [ "${lines[1]}" = "Running TOUCH job to timestamp [Wed Sep 16 09:00:00 2026]" ]
  [ "${lines[2]}" = "TOUCH finished [0m 10s]" ]
  [ "${lines[3]}" = "Footer line after touch" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "trim_log: collapses DIFF block keeping only boundary lines" {
  input=$(
    cat <<'EOF'
Header line before diff
### SnapRAID DIFF [Wed Sep 16 09:00:00 2026]
add /mnt/disk1/movie.mkv
remove /mnt/disk2/old.iso
10 equal
0 copied
DIFF finished [1m 20s]
Footer line after diff
EOF
  )
  run trim_log <<<"$input"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Header line before diff" ]
  [ "${lines[1]}" = "### SnapRAID DIFF [Wed Sep 16 09:00:00 2026]" ]
  [ "${lines[2]}" = "DIFF finished [1m 20s]" ]
  [ "${lines[3]}" = "Footer line after diff" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "trim_log: deletes SnapRAID noise lines" {
  input=$(
    cat <<'EOF'
Normal output before
Unexpected disk disconnection notice
WARNING! You cannot modify files during a sync.
Rerun the sync command when finished.
Normal output after
EOF
  )
  run trim_log <<<"$input"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Normal output before" ]
  [ "${lines[1]}" = "Normal output after" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "trim_log: preserves lines outside the filtered blocks" {
  input=$(
    cat <<'EOF'
SnapRAID Script Job started [date]
Running SnapRAID version 12.4
SUMMARY: Equal [10] - Added [2] - Deleted [0] - Moved [0] - Copied [0] - Updated [1]
### SnapRAID SCRUB [date]
Everything OK
All jobs ended.
EOF
  )
  run trim_log <<<"$input"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  [ "${lines[2]}" = "SUMMARY: Equal [10] - Added [2] - Deleted [0] - Moved [0] - Copied [0] - Updated [1]" ]
  [ "${lines[4]}" = "Everything OK" ]
}
