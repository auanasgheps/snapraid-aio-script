#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub non-network side effects
trim_log() { cat; }
send_mail() { :; }
mklog() { :; }

setup() {
  MOCK_CURL_LOG="$BATS_TEST_TMPDIR/curl_mock.log"
  export MOCK_CURL_LOG
  rm -f "$MOCK_CURL_LOG"

  # Prepend mock directory to PATH
  PATH="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock:$PATH"
  export PATH

  HEALTHCHECKS=0
  HEALTHCHECKS_URL="https://hc-ping.com/"
  HEALTHCHECKS_ID="test-uuid"
  TELEGRAM=0
  TELEGRAM_TOKEN="123456:TOKEN"
  TELEGRAM_CHAT_ID="999999"
  DISCORD=0
  DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/test/hook"
  APPRISE=0
  APPRISE_EMAIL=0
  EMAIL_ADDRESS=""
  HOOK_NOTIFICATION=""
  SUBJECT="Test Subject"
  NOTIFY_OUTPUT="Test Notification Message"
}

@test "notify_channels: healthchecks success sends to /0 endpoint" {
  HEALTHCHECKS=1
  NOTIFY_OUTPUT="Array synced successfully"
  notify_success
  [ -f "$MOCK_CURL_LOG" ]
  run grep "https://hc-ping.com/test-uuid/0" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep -- "--data-raw Array synced successfully" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_channels: healthchecks warning sends to /fail endpoint" {
  HEALTHCHECKS=1
  NOTIFY_OUTPUT="Array sync failed"
  notify_warning
  [ -f "$MOCK_CURL_LOG" ]
  run grep "https://hc-ping.com/test-uuid/fail" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep -- "--data-raw Array sync failed" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_channels: telegram notification sends formatted JSON payload" {
  TELEGRAM=1
  NOTIFY_OUTPUT="Threshold warning"
  notify_warning
  [ -f "$MOCK_CURL_LOG" ]
  run grep "https://api.telegram.org/bot123456:TOKEN/sendMessage" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep '{"chat_id": "999999", "text": "Threshold warning"}' "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_channels: discord notification sends payload to webhook url" {
  DISCORD=1
  NOTIFY_OUTPUT="Sync finished"
  notify_success
  [ -f "$MOCK_CURL_LOG" ]
  run grep "https://discord.com/api/webhooks/test/hook" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep 'content' "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

