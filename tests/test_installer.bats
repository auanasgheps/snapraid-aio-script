#!/usr/bin/env bats

source "$(realpath "$(dirname "$BATS_TEST_FILENAME")")/helpers/load_functions.bash"

# Stub mklog
mklog() { :; }

setup() {
  APT_LOG="$BATS_TEST_TMPDIR/apt.log"
  export APT_LOG
}

@test "check_and_install: warns and skips when dpkg command is not found" {
  command_exists() {
    [ "$1" != "dpkg" ]
  }

  run check_and_install "jq"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "WARNING: dpkg not found" ]]
}

@test "check_and_install: does nothing when package is already installed" {
  command_exists() { return 0; }
  dpkg-query() { echo "install ok installed"; }

  run check_and_install "jq"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_and_install: returns 1 when apt-get install fails" {
  command_exists() { return 0; }
  dpkg-query() { echo "unknown ok not-installed"; }
  apt-get() { return 1; }

  run check_and_install "fake-pkg"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ERROR: Failed to install fake-pkg" ]]
}

@test "check_and_install: installs successfully when apt-get succeeds" {
  command_exists() { return 0; }
  local count_file="$BATS_TEST_TMPDIR/dpkg_count"
  rm -f "$count_file"
  dpkg-query() {
    if [ ! -f "$count_file" ]; then
      touch "$count_file"
      echo "unknown ok not-installed"
    else
      echo "install ok installed"
    fi
  }
  apt-get() { return 0; }

  run check_and_install "jq"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "jq installed successfully" ]]
}

@test "as_user_login: prefers runuser when available" {
  command_exists() { [ "$1" = "runuser" ]; }
  runuser() {
    echo "RUNUSER: $*"
  }

  run as_user_login "testuser" "echo hello"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "RUNUSER: -l testuser -c echo hello" ]]
}

@test "as_user_login: falls back to su when runuser is missing" {
  command_exists() { return 1; }
  su() {
    echo "SU: $*"
  }

  run as_user_login "testuser" "echo hello"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "SU: - testuser -c echo hello" ]]
}

@test "check_and_install_apprise: returns 1 when pipx and apt-get are missing" {
  command_exists() { return 1; }

  run check_and_install_apprise
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Error: apt-get not found" ]]
}

@test "check_and_install_apprise: resolves immediately if apprise exists in PIPX_BIN_DIR" {
  command_exists() { return 0; }
  local fake_bin_dir="$BATS_TEST_TMPDIR/pipx_bin"
  mkdir -p "$fake_bin_dir"
  touch "$fake_bin_dir/apprise"
  chmod +x "$fake_bin_dir/apprise"

  as_user_login() {
    echo "$fake_bin_dir"
  }

  check_and_install_apprise
  [ "$APPRISE_BIN" = "$fake_bin_dir/apprise" ]
}

@test "check_and_install_apprise: resolves from user .local/bin/apprise" {
  command_exists() { return 0; }
  local fake_home="$BATS_TEST_TMPDIR/fake_home"
  mkdir -p "$fake_home/.local/bin"
  touch "$fake_home/.local/bin/apprise"
  chmod +x "$fake_home/.local/bin/apprise"

  user_home() { echo "$fake_home"; }
  as_user_login() { echo ""; }

  check_and_install_apprise
  [ "$APPRISE_BIN" = "$fake_home/.local/bin/apprise" ]
}

@test "check_and_install_apprise: installs via pipx if not initially found" {
  command_exists() { return 0; }
  local fake_home="$BATS_TEST_TMPDIR/fake_home"
  mkdir -p "$fake_home/.local/bin"
  user_home() { echo "$fake_home"; }

  local call_count=0
  as_user_login() {
    call_count=$((call_count + 1))
    if [[ "$2" == *"pipx install apprise"* ]]; then
      # simulate install creating the binary
      touch "$fake_home/.local/bin/apprise"
      chmod +x "$fake_home/.local/bin/apprise"
      return 0
    fi
    echo ""
  }

  AIO_CALLER_USER="customuser"
  check_and_install_apprise
  [ "$APPRISE_BIN" = "$fake_home/.local/bin/apprise" ]
}

@test "check_and_install_apprise: returns 1 when installation cannot resolve binary" {
  command_exists() { return 0; }
  user_home() { echo "$BATS_TEST_TMPDIR/nonexistent"; }
  as_user_login() { echo ""; }
  pipx() { return 1; }
  AIO_CALLER_USER="root"

  run check_and_install_apprise
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Error: could not resolve apprise binary" ]]
}
