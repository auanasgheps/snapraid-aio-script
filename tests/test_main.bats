#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub functions to isolate main()
output_to_file_screen() { :; }
close_output_and_wait() { :; }
check_root() { :; }
check_and_install() { :; }
check_and_install_apprise() { :; }
mklog() { :; }
mklog_noconfig() { :; }
notify_warning() { :; }
notify_success() { :; }
send_mail() { :; }
curl() { :; }

setup() {
  export PATH="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock:$PATH"
  OUT=1
  ERROR=2
  export OUT ERROR

  SNAPRAID_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/snapraid"
  MOCK_SNAPRAID_LOG="${BATS_TEST_TMPDIR}/snapraid_mock.log"
  export SNAPRAID_BIN MOCK_SNAPRAID_LOG
  rm -f "$MOCK_SNAPRAID_LOG"

  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  TMP_WARN_FILE="$BATS_TEST_TMPDIR/snapraid.warn"
  SYNC_WARN_FILE="$BATS_TEST_TMPDIR/sync_warn_count"
  SCRUB_COUNT_FILE="$BATS_TEST_TMPDIR/scrub_count"
  SNAPRAID_LOG="$BATS_TEST_TMPDIR/snapraid.log"
  export TMP_OUTPUT TMP_WARN_FILE SYNC_WARN_FILE SCRUB_COUNT_FILE SNAPRAID_LOG

  SNAPRAID_CONF_FILE="$BATS_TEST_TMPDIR/snapraid.conf"
  cat >"$SNAPRAID_CONF_FILE" <<'EOF'
parity /dev/null
content /dev/null
data d1 /dev/null
EOF

  CONF_FILE="$BATS_TEST_TMPDIR/script-config.conf"
  cat >"$CONF_FILE" <<EOF
CONFIG_VERSION="$SNAPSCRIPTVERSION"
SNAPRAID_CONF="$SNAPRAID_CONF_FILE"
SNAPRAID_LOG="$SNAPRAID_LOG"
EMAIL_ADDRESS=""
CHECK_UPDATES=0
HEALTHCHECKS=0
TELEGRAM=0
DISCORD=0
APPRISE=0
APPRISE_EMAIL=0
MANAGE_SERVICES=0
CUSTOM_HOOK=0
SPINDOWN=0
DEL_THRESHOLD=500
UP_THRESHOLD=500
ADD_DEL_THRESHOLD=0
SYNC_WARN_THRESHOLD=-1
SCRUB_DELAYED_RUN=0
SCRUB_PERCENT=5
SCRUB_AGE=10
SCRUB_NEW=0
PREHASH=1
FORCE_ZERO=0
RETENTION_DAYS=0
VERBOSITY=0
SMART_LOG=0
SNAP_STATUS=0
EOF
}

@test "main: exits 1 when CONFIG_FILE does not exist" {
  run main --config "/nonexistent/config.conf"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Script configuration file not found!" ]]
}

@test "main: exits 1 on CONFIG_VERSION mismatch" {
  sed -i 's/^CONFIG_VERSION=.*/CONFIG_VERSION="0.0"/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Please update your config file to the latest version" ]]
}

@test "main: exits 1 when snapraid process is already running" {
  pgrep() { return 0; }

  run main --config "$CONF_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "The script has detected SnapRAID is already running" ]]
}

@test "main: exits 1 when SNAPRAID_BIN is empty" {
  pgrep() { return 1; }
  SNAPRAID_BIN=""

  run main --config "$CONF_FILE"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "SnapRAID binary not found in PATH" ]]
}

@test "main: --dry-run stops execution before SYNC" {
  pgrep() { return 1; }

  run main --config "$CONF_FILE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SnapRAID DIFF" ]]
  [[ "$output" =~ "[DRY RUN] Exiting without running SYNC, SCRUB, spindown, or sending notifications." ]]
}

@test "main: executes full workflow (DIFF -> SYNC -> SCRUB)" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SnapRAID DIFF" ]]
  [[ "$output" =~ "SnapRAID SYNC" ]]
  [[ "$output" =~ "SnapRAID SCRUB" ]]
  [[ "$output" =~ "All jobs ended" ]]
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep "diff" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
  run grep "sync" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
  run grep "scrub" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}
