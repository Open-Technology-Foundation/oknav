#!/usr/bin/env bats
# ==============================================================================
# OKnav Test Suite - ok_master Integration Tests
# ==============================================================================
# Tests for individual server SSH connection handler (ok_master)
#
# Note: ok_master uses /usr/bin/ssh (absolute path), so we test via:
#   1. Exit codes for option validation
#   2. Debug output (-D) for command construction verification
#   3. Help/version output verification
#
# Run: bats tests/ok_master.bats
# ==============================================================================

load test_helper

# Helper to run ok_master symlink with hosts.conf
# Uses debug output since we can't mock /usr/bin/ssh
run_ok_master_debug() {
  local symlink_name="$1"
  shift

  create_server_symlinks "$TEST_TEMP_DIR" "$symlink_name"
  # Create hosts.conf with test entries matching expected symlink names
  create_hosts_conf "$TEST_TEMP_DIR" \
    "server0.test.local  ok0" \
    "server1.test.local  ok1" \
    "server2.test.local  ok2" \
    "server3.test.local  ok3" \
    "server0-bali.test.local  ok0-bali" \
    "server0-batam.test.local  ok0-batam" \
    "devbox.test.local  okdev  (local-only:$(hostname))"

  cd "$TEST_TEMP_DIR" || return 1
  # Add -D to get debug output, but mock SSH to prevent actual connection
  # Since we can't mock /usr/bin/ssh, we'll check output and let it fail
  run timeout 1s "./${symlink_name}" -D "$@" 2>&1 || true
}

# ==============================================================================
# Help and Version Tests
# ==============================================================================

@test "ok_master -h shows usage and exits 0" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 -h
  ((status == 0))
  assert_output_contains "Usage:"
  assert_output_contains "Options:"
}

@test "ok_master --help shows usage and exits 0" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 --help
  ((status == 0))
  assert_output_contains "Usage:"
}

@test "ok_master -V shows version and exits 0" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 -V
  ((status == 0))
  # Output should contain version number (semver format)
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "ok_master --version shows version and exits 0" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 --version
  ((status == 0))
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ==============================================================================
# Server Name Resolution Tests (via debug output)
# ==============================================================================

@test "ok0 resolves to FQDN from hosts.conf (debug output)" {
  run_ok_master_debug ok0 uptime
  # Debug output shows SERVER=<fqdn>
  assert_output_contains 'SERVER="server0.test.local"'
}

@test "ok1 resolves to FQDN from hosts.conf (debug output)" {
  run_ok_master_debug ok1 uptime
  assert_output_contains 'SERVER="server1.test.local"'
}

@test "ok2 resolves to FQDN from hosts.conf (debug output)" {
  run_ok_master_debug ok2 uptime
  assert_output_contains 'SERVER="server2.test.local"'
}

@test "ok3 resolves to FQDN from hosts.conf (debug output)" {
  run_ok_master_debug ok3 uptime
  assert_output_contains 'SERVER="server3.test.local"'
}

@test "ok0-bali resolves to FQDN with suffix (debug output)" {
  run_ok_master_debug ok0-bali uptime
  assert_output_contains 'SERVER="server0-bali.test.local"'
}

@test "ok0-batam resolves to FQDN with suffix (debug output)" {
  run_ok_master_debug ok0-batam uptime
  assert_output_contains 'SERVER="server0-batam.test.local"'
}

@test "ALIAS is preserved in debug output" {
  run_ok_master_debug ok0 uptime
  assert_output_contains 'ALIAS="ok0"'
}

# ==============================================================================
# Ad-hoc Server Tests (not in hosts.conf)
# ==============================================================================

@test "alias not in hosts.conf uses alias as hostname (debug output)" {
  create_server_symlinks "$TEST_TEMP_DIR" ok99
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  # With -D, we can see that SERVER is set to the alias itself
  run timeout 1s ./ok99 -D uptime 2>&1 || true
  # SERVER should be "ok99" (the alias, since not in hosts.conf)
  assert_output_contains 'SERVER="ok99"'
}

# ==============================================================================
# Local-Only Restriction Tests
# ==============================================================================

@test "local-only alias on wrong host exits with message" {
  create_server_symlinks "$TEST_TEMP_DIR" okdev
  create_hosts_conf "$TEST_TEMP_DIR" "devbox.local okdev (local-only:some-other-host)"
  cd "$TEST_TEMP_DIR" || return 1
  run ./okdev uptime
  # Should exit 2 (constraint violation) with error message
  ((status == 2))
  assert_output_contains "restricted to host"
}

@test "local-only alias on correct host resolves (debug output)" {
  run_ok_master_debug okdev uptime
  # hosts.conf in run_ok_master_debug sets local-only to current hostname
  assert_output_contains 'SERVER="devbox.test.local"'
}

# ==============================================================================
# Option Parsing Tests (via debug output)
# ==============================================================================

@test "-r sets USER to root (debug output)" {
  run_ok_master_debug ok0 -r uptime
  assert_output_contains 'USER="root"'
}

@test "--root sets USER to root (debug output)" {
  run_ok_master_debug ok0 --root uptime
  assert_output_contains 'USER="root"'
}

@test "-u admin sets USER to admin (debug output)" {
  run_ok_master_debug ok0 -u admin uptime
  assert_output_contains 'USER="admin"'
}

@test "--user deploy sets USER to deploy (debug output)" {
  run_ok_master_debug ok0 --user deploy uptime
  assert_output_contains 'USER="deploy"'
}

@test "-D enables debug output" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run timeout 1s ./ok0 -D uptime 2>&1 || true
  # Debug output includes "Connection parameters"
  assert_output_contains "Connection parameters"
}

@test "invalid option -z exits with code 22" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 -z
  ((status == 22))
  assert_output_contains "Invalid option"
}

@test "invalid option --invalid exits with code 22" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 --invalid
  ((status == 22))
}

# ==============================================================================
# Combined Options Tests (via debug output)
# ==============================================================================

@test "-rd combines root and directory options (debug output)" {
  run_ok_master_debug ok0 -rd uptime
  assert_output_contains 'USER="root"'
  # -d option should set CURDIR
  assert_output_contains "CURDIR="
}

@test "-Dr combines debug and root (debug output)" {
  run_ok_master_debug ok0 -Dr uptime
  assert_output_contains "DEBUG"
  assert_output_contains 'USER="root"'
}

# ==============================================================================
# Directory Preservation Tests (-d option)
# ==============================================================================

@test "-d sets CURDIR to current directory (debug output)" {
  run_ok_master_debug ok0 -d uptime
  # CURDIR should contain the current directory path
  assert_output_contains "CURDIR="
  # CMD should include cd command
  assert_output_contains "cd"
}

@test "--dir sets CURDIR (debug output)" {
  run_ok_master_debug ok0 --dir uptime
  assert_output_contains "CURDIR="
}

# ==============================================================================
# Interactive Mode Tests (via debug output)
# ==============================================================================

@test "no command argument triggers interactive mode with -t option (debug output)" {
  run_ok_master_debug ok0
  # Interactive mode should add -t option for pseudo-terminal
  assert_output_contains 'SSHOPTS="-t"'
  # And CMD should be 'exec bash'
  assert_output_contains 'CMD="exec bash"'
}

@test "with command argument, SSHOPTS is empty (debug output)" {
  run_ok_master_debug ok0 uptime
  # Command mode should NOT have -t in SSHOPTS
  assert_output_contains 'SSHOPTS=""'
}

# ==============================================================================
# Command Passing Tests (via debug output)
# ==============================================================================

@test "single command appears in CMD (debug output)" {
  run_ok_master_debug ok0 uptime
  assert_output_contains 'CMD="uptime"'
}

@test "command with arguments appears in CMD (debug output)" {
  run_ok_master_debug ok0 ls -la /etc
  # CMD should contain the full command
  assert_output_contains "ls -la /etc"
}

#fin
