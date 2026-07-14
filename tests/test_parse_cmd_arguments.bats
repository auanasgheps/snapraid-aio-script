#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

@test "parse_cmd_arguments: --config sets CONFIG_FILE" {
  parse_cmd_arguments --config /tmp/myconf.conf
  [ "$CONFIG_FILE" = "/tmp/myconf.conf" ]
}

@test "parse_cmd_arguments: --force-sync sets FORCE_SYNC=true and SYNC_WARN_THRESHOLD=0" {
  parse_cmd_arguments --force-sync
  [ "$FORCE_SYNC" = "true" ]
  [ "$SYNC_WARN_THRESHOLD" -eq 0 ]
}

@test "parse_cmd_arguments: unknown flag exits with status 1" {
  run parse_cmd_arguments --badoption
  [ "$status" -eq 1 ]
}

@test "parse_cmd_arguments: --dry-run sets DRY_RUN=true" {
  DRY_RUN=false
  parse_cmd_arguments --dry-run
  [ "$DRY_RUN" = "true" ]
}

@test "parse_cmd_arguments: --dry-run does not set FORCE_SYNC" {
  FORCE_SYNC=false
  parse_cmd_arguments --dry-run
  [ "$FORCE_SYNC" = "false" ]
}

@test "parse_cmd_arguments: --dry-run combined with --force-sync sets both flags" {
  DRY_RUN=false
  FORCE_SYNC=false
  parse_cmd_arguments --dry-run --force-sync
  [ "$DRY_RUN" = "true" ]
  [ "$FORCE_SYNC" = "true" ]
}
