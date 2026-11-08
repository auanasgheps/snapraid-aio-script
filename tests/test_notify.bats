#!/usr/bin/env bats

# Load real notify_success / notify_warning — do NOT use test_helper.bash which stubs them.
source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub network and mail side-effects
curl() { :; }
trim_log() { cat; }
send_mail() { :; }
mklog() { :; }

setup() {
  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  true >"$TMP_OUTPUT"
  NOTIFY_OUTPUT="test notification"
  SUBJECT="Test subject"

  # Apprise mock: touches a sentinel file when invoked
  APPRISE_SENTINEL="$BATS_TEST_TMPDIR/apprise_called"
  export APPRISE_SENTINEL
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/apprise" <<'EOF'
#!/usr/bin/env bash
touch "${APPRISE_SENTINEL}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/apprise"
  APPRISE_BIN="$BATS_TEST_TMPDIR/bin/apprise"

  # Notification defaults — all off
  APPRISE=0
  APPRISE_URL=("fake://url")
  APPRISE_ON_ERROR_ONLY=0
  APPRISE_EMAIL=0
  APPRISE_EMAIL_ATTACH_DO=0
  APPRISE_ATTACH=0
  HEALTHCHECKS=0
  TELEGRAM=0
  DISCORD=0
  EMAIL_ADDRESS=""
  HOOK_NOTIFICATION=""
}

teardown() { :; }

# --- notify_success ---

@test "notify_success: APPRISE=0 — apprise not called" {
  APPRISE=0
  notify_success
  [ ! -e "$APPRISE_SENTINEL" ]
}

@test "notify_success: APPRISE=1, APPRISE_ON_ERROR_ONLY=0 — apprise called" {
  APPRISE=1
  APPRISE_ON_ERROR_ONLY=0
  notify_success
  [ -e "$APPRISE_SENTINEL" ]
}

@test "notify_success: APPRISE=1, APPRISE_ON_ERROR_ONLY=1 — apprise suppressed" {
  APPRISE=1
  APPRISE_ON_ERROR_ONLY=1
  notify_success
  [ ! -e "$APPRISE_SENTINEL" ]
}

@test "notify_success: APPRISE_EMAIL=1 — sets APPRISE_EMAIL_ATTACH_DO=0" {
  APPRISE_EMAIL=1
  notify_success
  [ "$APPRISE_EMAIL_ATTACH_DO" -eq 0 ]
}

# --- notify_warning ---

@test "notify_warning: APPRISE=1, APPRISE_ON_ERROR_ONLY=1 — apprise still called (warnings always fire)" {
  APPRISE=1
  APPRISE_ON_ERROR_ONLY=1
  notify_warning
  [ -e "$APPRISE_SENTINEL" ]
}

@test "notify_warning: APPRISE_EMAIL=1 — sets APPRISE_EMAIL_ATTACH_DO=1" {
  APPRISE_EMAIL=1
  notify_warning
  [ "$APPRISE_EMAIL_ATTACH_DO" -eq 1 ]
}

@test "notify_success: APPRISE=1 with unexecutable APPRISE_BIN logs error instead of command not found" {
  APPRISE=1
  APPRISE_ON_ERROR_ONLY=0
  APPRISE_BIN="/nonexistent/apprise"

  run notify_success
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Error: Apprise binary not found or not executable" ]]
  [[ ! "$output" =~ "command not found" ]]
}

@test "notify_warning: APPRISE=1 with unexecutable APPRISE_BIN logs warning instead of command not found" {
  APPRISE=1
  APPRISE_BIN="/nonexistent/apprise"

  run notify_warning
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Error: Apprise binary not found or not executable" ]]
  [[ ! "$output" =~ "command not found" ]]
}
