#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  SERVICES=""
  DOCKER_HOST_SERVICES=()
  DOCKER_MODE=1
  ARRAY_VALIDATED=""
  DOCKERCMD_VALIDATED=""
  DOCKERALLOK=""
  DOCKER_CMD1=""
  DOCKER_CMD1_LOG=""
  DOCKER_CMD2=""
  DOCKER_CMD2_LOG=""
}

@test "service_array_setup: empty SERVICES and DOCKER_HOST_SERVICES sets ARRAY_VALIDATED=NO and DOCKERALLOK=NO" {
  SERVICES=""
  DOCKER_HOST_SERVICES=()
  DOCKER_MODE=1
  service_array_setup
  [ "$ARRAY_VALIDATED" = "NO" ]
  [ "$DOCKERALLOK" = "NO" ]
}

@test "service_array_setup: local SERVICES set enables ARRAY_VALIDATED=YES" {
  SERVICES="plex radarr"
  DOCKER_MODE=1
  service_array_setup
  [ "$ARRAY_VALIDATED" = "YES" ]
  [ "$DOCKERALLOK" = "YES" ]
}

@test "service_array_setup: remote DOCKER_HOST_SERVICES set enables ARRAY_VALIDATED=YES" {
  DOCKER_HOST_SERVICES=("host1:sonarr")
  DOCKER_MODE=1
  service_array_setup
  [ "$ARRAY_VALIDATED" = "YES" ]
  [ "$DOCKERALLOK" = "YES" ]
}

@test "service_array_setup: DOCKER_MODE=1 configures pause and unpause commands" {
  SERVICES="plex"
  DOCKER_MODE=1
  service_array_setup
  [ "$DOCKERCMD_VALIDATED" = "YES" ]
  [ "$DOCKER_CMD1" = "pause" ]
  [ "$DOCKER_CMD1_LOG" = "Pausing" ]
  [ "$DOCKER_CMD2" = "unpause" ]
  [ "$DOCKER_CMD2_LOG" = "Unpausing" ]
  [ "$DOCKERALLOK" = "YES" ]
}

@test "service_array_setup: DOCKER_MODE=2 configures stop and start commands" {
  SERVICES="plex"
  DOCKER_MODE=2
  service_array_setup
  [ "$DOCKERCMD_VALIDATED" = "YES" ]
  [ "$DOCKER_CMD1" = "stop" ]
  [ "$DOCKER_CMD1_LOG" = "Stopping" ]
  [ "$DOCKER_CMD2" = "start" ]
  [ "$DOCKER_CMD2_LOG" = "Starting" ]
  [ "$DOCKERALLOK" = "YES" ]
}

@test "service_array_setup: invalid DOCKER_MODE sets DOCKERCMD_VALIDATED=NO and DOCKERALLOK=NO" {
  SERVICES="plex"
  DOCKER_MODE=99
  service_array_setup
  [ "$DOCKERCMD_VALIDATED" = "NO" ]
  [ "$DOCKERALLOK" = "NO" ]
}

@test "service_array_setup: valid array and valid docker mode sets DOCKERALLOK=YES" {
  SERVICES="plex"
  DOCKER_MODE=1
  service_array_setup
  [ "$ARRAY_VALIDATED" = "YES" ]
  [ "$DOCKERCMD_VALIDATED" = "YES" ]
  [ "$DOCKERALLOK" = "YES" ]
}
