#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub side-effects
mklog() { :; }
notify_warning() { :; }

setup() {
  CONFIG_FILE="/etc/snapraid-aio.conf"
  SNAPRAID_CONF=""
}

@test "pick_snapraid_conf_file: single config proceeds successfully" {
  search_conf_files() {
    SNAPRAID_CONF="/etc/snapraid/omv_array.conf"
    return 0
  }

  run pick_snapraid_conf_file
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Proceeding with the omv-snapraid .conf file: /etc/snapraid/omv_array.conf" ]]
}

@test "pick_snapraid_conf_file: multiple configs triggers warning and exits 1" {
  search_conf_files() {
    conf_files=("/etc/snapraid/array1.conf" "/etc/snapraid/array2.conf")
    return 2
  }

  run pick_snapraid_conf_file
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Stopping the script due to multiple SnapRAID configuration files" ]]
  [[ "$output" =~ "/etc/snapraid/array1.conf" ]]
  [[ "$output" =~ "/etc/snapraid/array2.conf" ]]
}

@test "pick_snapraid_conf_file: no config found triggers fatal warning and exits 1" {
  search_conf_files() {
    SNAPRAID_CONF="/etc/snapraid/missing.conf"
    return 1
  }

  run pick_snapraid_conf_file
  [ "$status" -eq 1 ]
  [[ "$output" =~ "SnapRAID configuration file not found. The script cannot be run!" ]]
}
