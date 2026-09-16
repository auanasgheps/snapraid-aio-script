#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/test_helper.bash"

setup() {
  OMV_VERSION=-1
}

@test "check_omv_version: OMV 7 sets OMV_VERSION=7" {
  dpkg-query() {
    if [[ "$*" =~ \$\{Status\} ]]; then
      echo "install ok installed"
    elif [[ "$*" =~ \$\{Version\} ]]; then
      echo "7.4.1-1"
    fi
  }
  check_omv_version
  [ "$OMV_VERSION" -eq 7 ]
}

@test "check_omv_version: OMV 6 sets OMV_VERSION=6" {
  dpkg-query() {
    if [[ "$*" =~ \$\{Status\} ]]; then
      echo "install ok installed"
    elif [[ "$*" =~ \$\{Version\} ]]; then
      echo "6.9.16-1"
    fi
  }
  check_omv_version
  [ "$OMV_VERSION" -eq 6 ]
}

@test "check_omv_version: openmediavault not installed sets OMV_VERSION=0" {
  dpkg-query() {
    return 1
  }
  check_omv_version
  [ "$OMV_VERSION" -eq 0 ]
}

