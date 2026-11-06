#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub side-effects
mklog() { :; }
output_to_file_screen() { :; }
close_output_and_wait() { :; }

setup() {
  export PATH="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock:$PATH"
  MOCK_CURL_LOG="$BATS_TEST_TMPDIR/curl_mock.log"
  MOCK_APPRISE_LOG="$BATS_TEST_TMPDIR/apprise_mock.log"
  export MOCK_CURL_LOG MOCK_APPRISE_LOG
  rm -f "$MOCK_CURL_LOG" "$MOCK_APPRISE_LOG"

  APPRISE_BIN="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock/apprise"
  TELEGRAM=0
  DISCORD=0
  APPRISE=0
  INFO_MESSAGE=""
  INFO_MESSAGE_DISCORD=""
}

teardown() {
  rm -f "$MOCK_CURL_LOG" "$MOCK_APPRISE_LOG" /tmp/snapraid_info_msg.txt
}

@test "show_snapraid_info: sets INFO_MESSAGE and INFO_MESSAGE_DISCORD using command output" {
  local fixture
  fixture="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/fixtures/smart_report.txt"

  show_snapraid_info "cat $fixture" "SnapRAID SMART Report"

  [[ "$INFO_MESSAGE" =~ "SnapRAID SMART Report - \`\`\`" ]]
  [[ "$INFO_MESSAGE" =~ "DATA" ]]
  [[ "$INFO_MESSAGE_DISCORD" =~ "SnapRAID SMART Report - " ]]
  [[ "$INFO_MESSAGE_DISCORD" =~ "DATA" ]]
}

@test "notify_snapraid_info: sends telegram notification when TELEGRAM=1" {
  TELEGRAM=1
  TELEGRAM_TOKEN="bot123456"
  TELEGRAM_CHAT_ID="987654321"
  INFO_MESSAGE="SMART Report: All drives healthy"

  notify_snapraid_info

  [ -f "$MOCK_CURL_LOG" ]
  run grep "https://api.telegram.org/botbot123456/sendMessage" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "chat_id=987654321" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "text=SMART Report: All drives healthy" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_snapraid_info: sends discord notification under 2000 chars" {
  DISCORD=1
  DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
  INFO_MESSAGE_DISCORD="SMART Report OK"

  notify_snapraid_info

  [ -f "$MOCK_CURL_LOG" ]
  run grep "https://discord.com/api/webhooks/123/abc" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
  run grep "SMART Report OK" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_snapraid_info: sends discord warning when output exceeds 2000 chars" {
  DISCORD=1
  DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/abc"
  INFO_MESSAGE_DISCORD="$(printf 'x%.0s' {1..2050})"

  notify_snapraid_info

  [ -f "$MOCK_CURL_LOG" ]
  run grep "exceeds Discord's 2000 character limit" "$MOCK_CURL_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_snapraid_info: sends apprise notification with service URL formatting" {
  APPRISE=1
  APPRISE_URL=("tgram://bottoken/123" "discord://webhook_id/token")
  INFO_MESSAGE="SMART Report Info"

  notify_snapraid_info

  [ -f "$MOCK_APPRISE_LOG" ]
  run grep "tgram://bottoken/123?format=markdown" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  run grep "discord://webhook_id/token" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
}

@test "notify_snapraid_info: sends apprise attachment when output exceeds 2000 chars" {
  APPRISE=1
  APPRISE_URL=("prowl://apikey")
  INFO_MESSAGE="$(printf 'y%.0s' {1..2050})"

  notify_snapraid_info

  [ -f "$MOCK_APPRISE_LOG" ]
  run grep -- "-a /tmp/snapraid_info_msg.txt" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  run grep "The output is attached" "$MOCK_APPRISE_LOG"
  [ "$status" -eq 0 ]
  # Temp file should be cleaned up after notify_snapraid_info finishes
  [ ! -f /tmp/snapraid_info_msg.txt ]
}
