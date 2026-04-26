#!/usr/bin/env bats
# ==============================================================================
# OKnav Test Suite - Relay Failover Tests
# ==============================================================================
# Tests for ok_master's relay failover logic.
#
# ok_master invokes /usr/bin/ssh by hardcoded absolute path, so the actual
# fallback exec path cannot be mocked via PATH. These tests verify:
#   1. get_relay() priority resolution (--relay > OKNAV_RELAY > conf file)
#   2. Debug output (-D) shows the resolved RELAY value
#   3. --no-relay disables relay regardless of other settings
#   4. OKNAV_RELAY=none disables relay
#
# Run: bats tests/relay.bats
# ==============================================================================

load test_helper

# Helper: invoke ok_master via symlink with debug output, hosts.conf in place,
# and an optional pre-set environment. Returns whatever ok_master prints to
# stderr (debug output is on stderr).
run_relay_debug() {
  local symlink_name="$1"
  shift

  create_server_symlinks "$TEST_TEMP_DIR" "$symlink_name"
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local  ${symlink_name}"

  cd "$TEST_TEMP_DIR" || return 1
  # 1s timeout because ok_master will try /usr/bin/ssh and fail; we only need
  # the debug output emitted before the SSH invocation.
  run timeout 1s "./${symlink_name}" -D "$@" 2>&1 || true
}

# ==============================================================================
# Default Behavior (no relay configured)
# ==============================================================================

@test "no relay configured shows RELAY = <none> in debug output" {
  # Skip if system has /etc/oknav/relay.conf — path is hardcoded in ok_master
  # so we can't isolate this test from system config without main code changes.
  # See NOTES-IMPROVEMENTS.md for the related improvement (env override).
  [[ -f /etc/oknav/relay.conf ]] && skip "system /etc/oknav/relay.conf present (hardcoded path; see NOTES-IMPROVEMENTS.md)"
  unset OKNAV_RELAY
  run_relay_debug ok0 uptime
  assert_output_contains 'RELAY   = <none>'
}

# ==============================================================================
# --relay / -R Flag
# ==============================================================================

@test "--relay flag is shown in debug output" {
  unset OKNAV_RELAY
  run_relay_debug ok0 --relay relay.example.com uptime
  assert_output_contains 'RELAY   = relay.example.com'
}

@test "-R short flag sets RELAY in debug output" {
  unset OKNAV_RELAY
  run_relay_debug ok0 -R relay.example.com uptime
  assert_output_contains 'RELAY   = relay.example.com'
}

@test "--relay flag overrides OKNAV_RELAY env" {
  export OKNAV_RELAY=env-relay.example.com
  run_relay_debug ok0 --relay flag-relay.example.com uptime
  assert_output_contains 'RELAY   = flag-relay.example.com'
  unset OKNAV_RELAY
}

# ==============================================================================
# OKNAV_RELAY Environment Variable
# ==============================================================================

@test "OKNAV_RELAY env sets RELAY in debug output" {
  export OKNAV_RELAY=env-relay.example.com
  run_relay_debug ok0 uptime
  assert_output_contains 'RELAY   = env-relay.example.com'
  unset OKNAV_RELAY
}

@test "OKNAV_RELAY=none disables relay (RELAY = <none>)" {
  export OKNAV_RELAY=none
  run_relay_debug ok0 uptime
  assert_output_contains 'RELAY   = <none>'
  unset OKNAV_RELAY
}

# ==============================================================================
# --no-relay Flag
# ==============================================================================

@test "--no-relay shows RELAY = <disabled> in debug output" {
  unset OKNAV_RELAY
  run_relay_debug ok0 --no-relay uptime
  assert_output_contains 'RELAY   = <disabled>'
}

@test "--no-relay overrides --relay flag" {
  unset OKNAV_RELAY
  run_relay_debug ok0 --relay relay.example.com --no-relay uptime
  assert_output_contains 'RELAY   = <disabled>'
}

@test "--no-relay overrides OKNAV_RELAY env" {
  export OKNAV_RELAY=env-relay.example.com
  run_relay_debug ok0 --no-relay uptime
  assert_output_contains 'RELAY   = <disabled>'
  unset OKNAV_RELAY
}

# ==============================================================================
# Option Parsing
# ==============================================================================

@test "--relay without argument exits with code 22" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local  ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 --relay
  ((status == 22))
}

@test "-R without argument exits with code 22" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local  ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 -R
  ((status == 22))
}

# ==============================================================================
# Help Text
# ==============================================================================

@test "ok_master --help mentions --relay option" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local  ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 --help
  ((status == 0))
  assert_output_contains "--relay"
  assert_output_contains "--no-relay"
}

@test "ok_master --help documents OKNAV_RELAY priority" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0
  create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local  ok0"
  cd "$TEST_TEMP_DIR" || return 1
  run ./ok0 --help
  ((status == 0))
  assert_output_contains "OKNAV_RELAY"
}

#fin
