#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub functions to isolate main()
output_to_file_screen() { :; }
close_output_and_wait() { :; }
check_root() { :; }
check_and_install() {
  echo "install: $1" >>"${MOCK_INSTALL_LOG}"
}
check_and_install_apprise() {
  echo "install_apprise" >>"${MOCK_INSTALL_LOG}"
  APPRISE_BIN="$BATS_TEST_TMPDIR/bin/apprise"
  export APPRISE_BIN
}
mklog() { :; }
mklog_noconfig() { :; }
notify_warning() { :; }
notify_success() { :; }
send_mail() { :; }
curl() {
  echo "curl: $*" >>"${MOCK_CURL_LOG}"
}

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

  MOCK_CURL_LOG="${BATS_TEST_TMPDIR}/curl_main.log"
  MOCK_APPRISE_LOG="${BATS_TEST_TMPDIR}/apprise_main.log"
  MOCK_INSTALL_LOG="${BATS_TEST_TMPDIR}/install_main.log"
  export MOCK_CURL_LOG MOCK_APPRISE_LOG MOCK_INSTALL_LOG
  rm -f "$MOCK_CURL_LOG" "$MOCK_APPRISE_LOG" "$MOCK_INSTALL_LOG"
  touch "$MOCK_CURL_LOG" "$MOCK_APPRISE_LOG" "$MOCK_INSTALL_LOG"

  # Create mock apprise binary that records arguments
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/apprise" <<'EOF'
#!/usr/bin/env bash
echo "apprise: $*" >>"${MOCK_APPRISE_LOG}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/apprise"

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
HEALTHCHECKS_ID="dummy-id"
HEALTHCHECKS_URL="https://hc-ping.com/"
TELEGRAM=0
TELEGRAM_TOKEN="dummy-token"
TELEGRAM_CHAT_ID="dummy-chat"
DISCORD=0
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/dummy"
APPRISE=0
APPRISE_EMAIL=0
APPRISE_URL=("apprise://dummy-url")
APPRISE_ON_ERROR_ONLY=0
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
  run grep -- "--force-zero" "$MOCK_SNAPRAID_LOG"
  [ "$status" -ne 0 ]
}

@test "main: executes full workflow with --force-zero CLI flag passed to snapraid sync" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"

  run main --config "$CONF_FILE" --force-zero
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SnapRAID SYNC" ]]
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep -- "-h --force-zero -q sync" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}

@test "main: executes full workflow with FORCE_ZERO=1 in config passed to snapraid sync" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^FORCE_ZERO=.*/FORCE_ZERO=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SnapRAID SYNC" ]]
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep -- "-h --force-zero -q sync" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
}

@test "main: executes full workflow with --force-zero and PREHASH=0" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^PREHASH=.*/PREHASH=0/' "$CONF_FILE"

  run main --config "$CONF_FILE" --force-zero
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SnapRAID SYNC" ]]
  [ -f "$MOCK_SNAPRAID_LOG" ]
  run grep -- "--force-zero -q sync" "$MOCK_SNAPRAID_LOG"
  [ "$status" -eq 0 ]
  run grep -- "-h" "$MOCK_SNAPRAID_LOG"
  [ "$status" -ne 0 ]
}

# ==============================================================================
# Notification Initialization Matrix Tests
# ==============================================================================

# --- Category 1: Apprise alone with other notification channels disabled ---

@test "main: notification init - APPRISE=0, APPRISE_EMAIL=0 skips apprise entirely" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  run grep "apprise:" "$MOCK_APPRISE_LOG"
  [ "$status" -ne 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  [[ ! "$output" =~ "Apprise service notification is enabled." ]]
}

@test "main: notification init - APPRISE=1, APPRISE_EMAIL=0, ON_ERROR_ONLY=0 installs apprise and sends job started" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  run grep "apprise: -b SnapRAID Script Job started apprise://dummy-url" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Apprise service notification is enabled." ]]
}

@test "main: notification init - APPRISE=1, APPRISE_EMAIL=0, ON_ERROR_ONLY=1 installs apprise but suppresses job started" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_ON_ERROR_ONLY=.*/APPRISE_ON_ERROR_ONLY=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Apprise service notification is enabled." ]]
}

@test "main: notification init - APPRISE=0, APPRISE_EMAIL=1 installs apprise without job started ping" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE_EMAIL=.*/APPRISE_EMAIL=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Apprise service notification is enabled." ]]
}

@test "main: notification init - APPRISE=1, APPRISE_EMAIL=1, ON_ERROR_ONLY=0 installs apprise and sends job started" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_EMAIL=.*/APPRISE_EMAIL=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started apprise://dummy-url" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Apprise service notification is enabled." ]]
}

@test "main: notification init - APPRISE=1, APPRISE_EMAIL=1, ON_ERROR_ONLY=1 installs apprise but suppresses job started" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_EMAIL=.*/APPRISE_EMAIL=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_ON_ERROR_ONLY=.*/APPRISE_ON_ERROR_ONLY=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Apprise service notification is enabled." ]]
}

# --- Category 2: Apprise with multiple URLs ---

@test "main: notification init - APPRISE=1 sends job started to multiple URLs" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"
  sed -i 's|^APPRISE_URL=.*|APPRISE_URL=("apprise://service1" "apprise://service2" "apprise://service3")|' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started apprise://service1" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started apprise://service2" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started apprise://service3" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

# --- Category 3: Interactions between Apprise and other channels ---

@test "main: notification init - HEALTHCHECKS=1 with APPRISE=1 initializes both" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^HEALTHCHECKS=.*/HEALTHCHECKS=1/' "$CONF_FILE"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install: jq" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "https://hc-ping.com/dummy-id/start" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "main: notification init - HEALTHCHECKS=1 with APPRISE=0 skips apprise" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^HEALTHCHECKS=.*/HEALTHCHECKS=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "https://hc-ping.com/dummy-id/start" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  run grep "apprise:" "$MOCK_APPRISE_LOG"
  [ "$status" -ne 0 ]
}

@test "main: notification init - TELEGRAM=1 with APPRISE=1 initializes both" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^TELEGRAM=.*/TELEGRAM=1/' "$CONF_FILE"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install: jq" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "https://api.telegram.org/botdummy-token/sendMessage" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "main: notification init - TELEGRAM=1 with APPRISE=0 skips apprise" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^TELEGRAM=.*/TELEGRAM=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "https://api.telegram.org/botdummy-token/sendMessage" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
}

@test "main: notification init - DISCORD=1 with APPRISE=1 initializes both" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^DISCORD=.*/DISCORD=1/' "$CONF_FILE"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install: jq" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "https://discord.com/api/webhooks/dummy" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "main: notification init - DISCORD=1 with APPRISE=0 skips apprise" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^DISCORD=.*/DISCORD=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "https://discord.com/api/webhooks/dummy" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
}

@test "main: notification init - CHECK_UPDATES=1 with APPRISE=1 initializes both" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^CHECK_UPDATES=.*/CHECK_UPDATES=1/' "$CONF_FILE"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "main: notification init - CHECK_UPDATES=1 with APPRISE=0, APPRISE_EMAIL=1 initializes apprise" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^CHECK_UPDATES=.*/CHECK_UPDATES=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_EMAIL=.*/APPRISE_EMAIL=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -ne 0 ]
}

@test "main: notification init - CHECK_UPDATES=1 with APPRISE=0, APPRISE_EMAIL=0 skips apprise" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^CHECK_UPDATES=.*/CHECK_UPDATES=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
}

@test "main: notification init - ALL channels enabled initializes all services" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^HEALTHCHECKS=.*/HEALTHCHECKS=1/' "$CONF_FILE"
  sed -i 's/^TELEGRAM=.*/TELEGRAM=1/' "$CONF_FILE"
  sed -i 's/^DISCORD=.*/DISCORD=1/' "$CONF_FILE"
  sed -i 's/^CHECK_UPDATES=.*/CHECK_UPDATES=1/' "$CONF_FILE"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_EMAIL=.*/APPRISE_EMAIL=1/' "$CONF_FILE"

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "https://hc-ping.com/dummy-id/start" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "https://api.telegram.org/botdummy-token/sendMessage" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "https://discord.com/api/webhooks/dummy" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  run grep "apprise: -b SnapRAID Script Job started" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

# --- Category 4: Dry-run and failure modes ---

@test "main: notification init - --dry-run suppresses all notification checks and pings" {
  pgrep() { return 1; }
  sed -i 's/^HEALTHCHECKS=.*/HEALTHCHECKS=1/' "$CONF_FILE"
  sed -i 's/^TELEGRAM=.*/TELEGRAM=1/' "$CONF_FILE"
  sed -i 's/^DISCORD=.*/DISCORD=1/' "$CONF_FILE"
  sed -i 's/^CHECK_UPDATES=.*/CHECK_UPDATES=1/' "$CONF_FILE"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"
  sed -i 's/^APPRISE_EMAIL=.*/APPRISE_EMAIL=1/' "$CONF_FILE"

  run main --config "$CONF_FILE" --dry-run
  [ "$status" -eq 0 ]
  run grep "install_apprise" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  run grep "install: curl" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  run grep "install: jq" "$MOCK_INSTALL_LOG"
  [ "$status" -ne 0 ]
  [ ! -s "$MOCK_APPRISE_LOG" ]
  [ ! -s "$MOCK_CURL_LOG" ]
  [[ ! "$output" =~ "Apprise service notification is enabled." ]]
}

@test "main: notification init - check_and_install_apprise failure does not crash with command not found" {
  pgrep() { return 1; }
  export MOCK_DIFF_SCENARIO="diff_adds_only"
  sed -i 's/^APPRISE=.*/APPRISE=1/' "$CONF_FILE"

  # Stub check_and_install_apprise to simulate failure: returns 1 without exporting APPRISE_BIN
  check_and_install_apprise() {
    echo "install_apprise_failed" >>"${MOCK_INSTALL_LOG}"
    return 1
  }

  run main --config "$CONF_FILE"
  [ "$status" -eq 0 ]
  run grep "install_apprise_failed" "$MOCK_INSTALL_LOG"
  [ "$status" -eq 0 ]
  # Ensure no ': command not found' from attempting to invoke empty APPRISE_BIN
  [[ ! "$output" =~ "command not found" ]]
  [ ! -s "$MOCK_APPRISE_LOG" ]
}
