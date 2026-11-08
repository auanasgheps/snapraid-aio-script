#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub side-effects
mklog() { :; }

setup() {
  export PATH="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock:$PATH"
  MOCK_APPRISE_LOG="$BATS_TEST_TMPDIR/apprise_mock.log"
  MOCK_MAIL_LOG="$BATS_TEST_TMPDIR/mail_mock.log"
  MOCK_MAIL_BODY="$BATS_TEST_TMPDIR/mail_body.txt"
  export MOCK_APPRISE_LOG MOCK_MAIL_LOG MOCK_MAIL_BODY
  rm -f "$MOCK_APPRISE_LOG" "$MOCK_MAIL_LOG" "$MOCK_MAIL_BODY"

  APPRISE_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/apprise"
  MAIL_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/mail"
  TMP_OUTPUT="$BATS_TEST_TMPDIR/snapraid.out"
  echo "test log content" >"$TMP_OUTPUT"

  SUBJECT="[COMPLETED] SnapRAID Job"
  EMAIL_ADDRESS=""
  FROM_EMAIL_ADDRESS="nas@example.com"
  APPRISE_EMAIL=0
  APPRISE_EMAIL_ATTACH=0
  APPRISE_EMAIL_ATTACH_DO=0
  APPRISE_EMAIL_URL="mailto://user:pass@smtp.example.com"
  HOOK_NOTIFICATION=""
}

teardown() {
  rm -f "$MOCK_APPRISE_LOG" "$MOCK_MAIL_LOG" "$MOCK_MAIL_BODY"
}

@test "send_mail: sends via Apprise email without attachment" {
  APPRISE_EMAIL=1

  run send_mail <<'EOF'
# Header
SnapRAID finished successfully.
EOF

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Sending email report using Apprise service" ]]
  [ -f "$MOCK_APPRISE_LOG" ]
  run grep -- "-vv -i html -t \[COMPLETED\] SnapRAID Job" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  run grep "$APPRISE_EMAIL_URL" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "send_mail: sends via Apprise email with attachment" {
  APPRISE_EMAIL=1
  APPRISE_EMAIL_ATTACH=1
  APPRISE_EMAIL_ATTACH_DO=1

  run send_mail <<'EOF'
SnapRAID with attachment.
EOF

  [ "$status" -eq 0 ]
  [ -f "$MOCK_APPRISE_LOG" ]
  run grep -- "-a $TMP_OUTPUT" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "send_mail: warns when APPRISE_EMAIL=1 and APPRISE_BIN is not set or not executable" {
  APPRISE_EMAIL=1
  APPRISE_BIN="/nonexistent/apprise"

  run send_mail <<'EOF'
Body text
EOF

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Error: Apprise binary not found or not executable" ]]
  [[ ! "$output" =~ "command not found" ]]
}

@test "send_mail: warns when MAIL_BIN is not set" {
  EMAIL_ADDRESS="admin@example.com"
  MAIL_BIN=""

  run send_mail <<'EOF'
Body text
EOF

  [ "$status" -eq 0 ]
  [[ "$output" =~ "No mail program set in MAIL_BIN" ]]
  [ ! -f "$MOCK_MAIL_LOG" ]
}

@test "send_mail: warns when MAIL_BIN binary does not exist" {
  EMAIL_ADDRESS="admin@example.com"
  MAIL_BIN="/nonexistent/path/to/mail"

  run send_mail <<'EOF'
Body text
EOF

  [ "$status" -eq 0 ]
  [[ "$output" =~ "not found, you must install it" ]]
  [ ! -f "$MOCK_MAIL_LOG" ]
}

@test "send_mail: sends email via MAIL_BIN with headers and recipient" {
  EMAIL_ADDRESS="admin@example.com"

  run send_mail <<'EOF'
Report body line 1
Report body line 2
EOF

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Sending email report to **admin@example.com**" ]]
  [ -f "$MOCK_MAIL_LOG" ]
  run grep "admin@example.com" "$MOCK_MAIL_LOG"
  [ "$status" -eq 0 ]
  run grep -- "-r nas@example.com" "$MOCK_MAIL_LOG"
  [ "$status" -eq 0 ]
  run grep "Content-Type: text/html" "$MOCK_MAIL_LOG"
  [ "$status" -eq 0 ]
}

@test "send_mail: invokes HOOK_NOTIFICATION script when executable" {
  local hook_script="$BATS_TEST_TMPDIR/notify_hook.sh"
  cat >"$hook_script" <<'EOF'
#!/bin/sh
echo "HOOK CALLED: $1 | $2" > "${BATS_TEST_TMPDIR}/hook.log"
EOF
  chmod +x "$hook_script"
  HOOK_NOTIFICATION="$hook_script"

  # Stub command_exists and runuser/sudo
  command_exists() { return 1; }
  sudo() {
    shift 2 # skip -u <user>
    "$@"
  }

  run send_mail <<'EOF'
Hook body text
EOF

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Notification user script is set" ]]
  [ -f "$BATS_TEST_TMPDIR/hook.log" ]
  run cat "$BATS_TEST_TMPDIR/hook.log"
  [[ "$output" =~ "HOOK CALLED: [COMPLETED] SnapRAID Job" ]]
}
