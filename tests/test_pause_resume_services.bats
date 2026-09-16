#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  MOCK_DOCKER_LOG="${BATS_TEST_TMPDIR:-/tmp}/docker_mock.log"
  MOCK_SSH_LOG="${BATS_TEST_TMPDIR:-/tmp}/ssh_mock.log"
  export MOCK_DOCKER_LOG MOCK_SSH_LOG
  rm -f "$MOCK_DOCKER_LOG" "$MOCK_SSH_LOG"

  # Prepend mock directory to PATH
  PATH="$(realpath "$(dirname "$BATS_TEST_FILENAME")")/mock:$PATH"
  export PATH

  DOCKER_LOCAL=0
  DOCKER_REMOTE=0
  DOCKER_USER="admin"
  DOCKER_DELAY=0
  SERVICES=""
  DOCKER_HOST_SERVICES=()
  DOCKER_CMD1=pause
  DOCKER_CMD1_LOG="Pausing"
  DOCKER_CMD2=unpause
  DOCKER_CMD2_LOG="Unpausing"
  SERVICES_STOPPED=0
}

@test "pause_services: local containers calls docker with DOCKER_CMD1 and sets SERVICES_STOPPED=1" {
  DOCKER_LOCAL=1
  SERVICES="plex sonarr"
  DOCKER_CMD1=pause
  pause_services
  [ "$SERVICES_STOPPED" -eq 1 ]
  [ -f "$MOCK_DOCKER_LOG" ]
  run grep "pause plex sonarr" "$MOCK_DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "resume_services: local containers calls docker with DOCKER_CMD2 and resets SERVICES_STOPPED=0" {
  DOCKER_LOCAL=1
  SERVICES="plex sonarr"
  DOCKER_CMD2=unpause
  SERVICES_STOPPED=1
  resume_services
  [ "$SERVICES_STOPPED" -eq 0 ]
  [ -f "$MOCK_DOCKER_LOG" ]
  run grep "unpause plex sonarr" "$MOCK_DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "resume_services: does nothing when SERVICES_STOPPED is 0" {
  DOCKER_LOCAL=1
  SERVICES="plex sonarr"
  SERVICES_STOPPED=0
  resume_services
  [ ! -f "$MOCK_DOCKER_LOG" ]
}

@test "pause_services: mode 2 stop command invokes docker stop" {
  DOCKER_LOCAL=1
  SERVICES="radarr"
  DOCKER_CMD1=stop
  pause_services
  [ "$SERVICES_STOPPED" -eq 1 ]
  run grep "stop radarr" "$MOCK_DOCKER_LOG"
  [ "$status" -eq 0 ]
}

@test "pause_services: remote container parses DOCKER_HOST_SERVICES and calls ssh" {
  DOCKER_REMOTE=1
  DOCKER_USER="snapuser"
  DOCKER_HOST_SERVICES=("nas1:plex,tautulli" "nas2:qbittorrent")
  DOCKER_CMD1=pause
  pause_services
  [ "$SERVICES_STOPPED" -eq 1 ]
  [ -f "$MOCK_SSH_LOG" ]
  run grep "snapuser@nas1 docker pause plex tautulli" "$MOCK_SSH_LOG"
  [ "$status" -eq 0 ]
  run grep "snapuser@nas2 docker pause qbittorrent" "$MOCK_SSH_LOG"
  [ "$status" -eq 0 ]
}

@test "resume_services: remote container calls ssh with DOCKER_CMD2 and resets SERVICES_STOPPED" {
  DOCKER_REMOTE=1
  DOCKER_USER="snapuser"
  DOCKER_HOST_SERVICES=("nas1:plex")
  DOCKER_CMD2=unpause
  SERVICES_STOPPED=1
  resume_services
  [ "$SERVICES_STOPPED" -eq 0 ]
  [ -f "$MOCK_SSH_LOG" ]
  run grep "snapuser@nas1 docker unpause plex" "$MOCK_SSH_LOG"
  [ "$status" -eq 0 ]
}
