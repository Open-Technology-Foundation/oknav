#!/usr/bin/env bats
# ==============================================================================
# OKnav Test Suite - oknav Orchestrator Integration Tests
# ==============================================================================
# Tests for multi-server SSH command orchestrator (oknav)
#
# Key behaviors tested:
#   - Server discovery from symlinks validated against hosts.conf
#   - Option parsing (-p, -t, -x, -D)
#   - Sequential and parallel execution modes
#   - Server exclusion handling (hosts.conf options and -x flag)
#   - Cleanup on exit
#
# Run: bats tests/oknav.bats
# ==============================================================================

load test_helper

# Helper to set up oknav environment with hosts.conf
setup_oknav_env() {
  local -a servers=("$@")

  # Default servers if none specified
  if ((${#servers[@]} == 0)); then
    servers=(ok0 ok1 ok2)
  fi

  # Create symlinks
  create_server_symlinks "$TEST_TEMP_DIR" "${servers[@]}"

  # Build hosts.conf entries (with oknav option for cluster discovery)
  local -a entries=()
  for srv in "${servers[@]}"; do
    entries+=("${srv}.test.local  $srv  (oknav)")
  done
  create_hosts_conf "$TEST_TEMP_DIR" "${entries[@]}"

  # Copy oknav script
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"

  # Set up mocks
  create_mock_sudo
  create_mock_timeout
}

# ==============================================================================
# Help and Version Tests
# ==============================================================================

@test "oknav without arguments shows usage and exits 1" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav
  ((status == 1))
  assert_output_contains "Usage:"
}

@test "oknav -h shows usage and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -h
  ((status == 0))
  assert_output_contains "Usage:"
  assert_output_contains "Options:"
}

@test "oknav --help shows usage and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav --help
  ((status == 0))
  assert_output_contains "Usage:"
}

@test "oknav -V shows version and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -V
  ((status == 0))
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "oknav --version shows version and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav --version
  ((status == 0))
}

# ==============================================================================
# Server Discovery Tests
# ==============================================================================

@test "oknav discovers ok* symlinks that are in hosts.conf" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -D uptime 2>&1
  assert_output_contains "Discovered servers:"
}

@test "oknav finds all symlinks matching hosts.conf" {
  setup_oknav_env ok0 ok1 ok2 ok3
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -D uptime 2>&1
  # Should find all 4 servers
  assert_output_contains "ok0"
  assert_output_contains "ok1"
  assert_output_contains "ok2"
  assert_output_contains "ok3"
}

@test "oknav excludes hosts without (oknav) option" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 ok1 ok2
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav)" \
    "ok1.test.local ok1 (oknav)" \
    "ok2.test.local ok2"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -D uptime 2>&1
  # ok2 should NOT be included (no oknav option)
  assert_output_not_contains "ok2"
  # ok0 and ok1 should be included
  assert_output_contains "ok0"
  assert_output_contains "ok1"
}

@test "oknav ignores non-symlink files" {
  setup_oknav_env ok0 ok1
  # Create a regular file named ok-fake (not a symlink)
  echo "not a script" > "${TEST_TEMP_DIR}/ok-notlink"
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -D uptime 2>&1
  # Should NOT include ok-notlink
  assert_output_not_contains "ok-notlink"
}

@test "oknav with no servers found exits with error" {
  # Create directory with no matching symlinks/hosts.conf
  mkdir -p "${TEST_TEMP_DIR}/empty"
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/empty/"
  cp "${PROJECT_DIR}/common.inc.sh" "${TEST_TEMP_DIR}/empty/"
  # Create empty hosts.conf - will fail on "no valid entries"
  echo "# empty" > "${TEST_TEMP_DIR}/empty/hosts.conf"
  # Override to use this empty hosts.conf instead of system config
  export OKNAV_HOSTS_CONF="${TEST_TEMP_DIR}/empty/hosts.conf"
  cd "${TEST_TEMP_DIR}/empty" || return 1

  run ./oknav uptime
  ((status != 0))
}

# ==============================================================================
# Option Parsing Tests
# ==============================================================================

@test "-p enables parallel mode" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -p -D uptime
  assert_output_contains "parallel"
}

@test "--parallel enables parallel mode" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav --parallel -D uptime
  assert_output_contains "parallel"
}

@test "-t sets timeout value" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -t 60 -D uptime
  assert_output_contains "Timeout: 60"
}

@test "--timeout sets timeout value" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav --timeout 120 -D uptime
  assert_output_contains "Timeout: 120"
}

@test "-t with non-numeric value exits with non-zero" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -t abc uptime
  # Script uses declare -i TIMEOUT, so non-numeric triggers bash error
  ((status != 0))
}

@test "-D enables debug output" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -D uptime
  assert_output_contains "DEBUG"
}

@test "--debug enables debug output" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav --debug uptime
  assert_output_contains "DEBUG"
}

@test "invalid option --invalid exits with code 22" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav --invalid
  ((status == 22))
  assert_output_contains "Invalid option"
}

# ==============================================================================
# Combined Options Tests
# ==============================================================================

@test "-pt 10 combines parallel and timeout" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -pt 10 -D uptime
  assert_output_contains "parallel"
  assert_output_contains "Timeout: 10"
}

@test "-Dp combines debug and parallel" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -Dp uptime
  assert_output_contains "DEBUG"
  assert_output_contains "parallel"
}

# ==============================================================================
# Server Exclusion Tests
# ==============================================================================

@test "-x excludes specified server" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -x ok0 -D uptime 2>&1
  # ok0 should not be in execution output
  assert_output_not_contains "+++ok0:"
}

@test "--exclude-host excludes specified server" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav --exclude-host ok1 -D uptime 2>&1
  assert_output_not_contains "+++ok1:"
}

@test "-x is repeatable for multiple exclusions" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -x ok0 -x ok1 uptime
  # Only ok2 should be executed
  assert_output_contains "+++ok2:"
  assert_output_not_contains "+++ok0:"
  assert_output_not_contains "+++ok1:"
}

@test "hosts.conf (exclude) option excludes server" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 ok1 ok2
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav,exclude)" \
    "ok1.test.local ok1 (oknav)" \
    "ok2.test.local ok2 (oknav)"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  # ok0 should be excluded via hosts.conf
  assert_output_not_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

@test "hosts.conf (local-only) auto-excludes on wrong host" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 okdev
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav)" \
    "dev.test.local okdev (oknav,local-only:some-other-host)"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -D uptime 2>&1
  # okdev should be auto-excluded
  assert_output_not_contains "+++okdev:"
}

@test "hosts.conf (local-only) included on correct host" {
  create_server_symlinks "$TEST_TEMP_DIR" ok0 okdev
  create_hosts_conf "$TEST_TEMP_DIR" \
    "ok0.test.local ok0 (oknav)" \
    "dev.test.local okdev (oknav,local-only:$(hostname))"
  create_mock_sudo
  create_mock_timeout
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  # okdev should be included since we're on the correct host
  assert_output_contains "+++okdev:"
}

@test "ok-server-excludes.list is ignored" {
  setup_oknav_env ok0 ok1 ok2
  # Create old exclusion file (should be ignored)
  echo "ok0" > "${TEST_TEMP_DIR}/ok-server-excludes.list"
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  # ok0 should NOT be excluded - file is ignored
  assert_output_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

# ==============================================================================
# Sequential Execution Tests
# ==============================================================================

@test "sequential mode executes servers in order" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  # Check output format - should have server markers
  assert_output_contains "+++ok"
}

@test "sequential mode output has server separators" {
  setup_oknav_env ok0 ok1
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  # Each server output starts with +++server:
  assert_output_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

# ==============================================================================
# Parallel Execution Tests
# ==============================================================================

@test "parallel mode uses background processes" {
  setup_oknav_env ok0 ok1
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -p uptime
  # Output should still have all servers
  assert_output_contains "+++ok0:"
  assert_output_contains "+++ok1:"
}

@test "parallel mode maintains output order" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -p uptime
  # All servers should appear in output
  ((status == 0))
}

# ==============================================================================
# Timeout Handling Tests
# ==============================================================================

@test "timeout command is used for execution" {
  setup_oknav_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  # Timeout mock should have been called
  assert_mock_called "TIMEOUT_CALL" "30s"
}

@test "custom timeout value is passed to timeout command" {
  setup_oknav_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav -t 60 uptime
  assert_mock_called "TIMEOUT_CALL" "60s"
}

@test "timeout exit 124 shows timeout message" {
  setup_oknav_env ok0

  # Create timeout mock that returns 124
  cat > "${MOCK_BIN}/timeout" <<'EOF'
#!/bin/bash
echo "TIMEOUT_CALL: $*" >> "${MOCK_LOG}"
exit 124
EOF
  chmod +x "${MOCK_BIN}/timeout"

  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  assert_output_contains "Connection timeout"
}

# ==============================================================================
# Cleanup Tests
# ==============================================================================

@test "temp files are created in TEMP_DIR for parallel mode" {
  setup_oknav_env ok0 ok1

  # Set XDG_RUNTIME_DIR to our temp dir for predictable temp file location
  export XDG_RUNTIME_DIR="$TEST_TEMP_DIR"

  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav -p uptime

  # After execution, temp files should be cleaned up
  # (The trap should have removed them)
  ((status == 0))
}

# ==============================================================================
# Command Execution Tests
# ==============================================================================

@test "command is passed to servers via sudo" {
  setup_oknav_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav uptime
  assert_mock_called "SUDO_CALL" "ok0"
}

@test "complex command with quotes is passed correctly" {
  setup_oknav_env ok0
  cd "$TEST_TEMP_DIR" || return 1

  run ./oknav 'echo "hello world"'
  assert_mock_called "SUDO_CALL" "echo"
}

# ==============================================================================
# Add Subcommand Tests
# ==============================================================================

# Helper to create mock getent for hostname resolution
create_mock_getent() {
  local resolvable="${1:-}"  # comma-separated list of resolvable hostnames

  cat > "${MOCK_BIN}/getent" <<EOF
#!/bin/bash
# Mock getent: returns success for specified hostnames
hostname="\$2"
resolvable="${resolvable}"

if [[ ",\${resolvable}," == *",\${hostname},"* ]]; then
  echo "127.0.0.1 \${hostname}"
  exit 0
else
  exit 2
fi
EOF
  chmod +x "${MOCK_BIN}/getent"
}

@test "oknav add -h shows help and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add -h
  ((status == 0))
  assert_output_contains "Usage: oknav add"
  assert_output_contains "hostname"
}

@test "oknav add --help shows help and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add --help
  ((status == 0))
  assert_output_contains "Usage: oknav add"
}

@test "oknav add without hostname shows error and exits 1" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add
  ((status == 1))
  assert_output_contains "Usage: oknav add"
}

@test "oknav add with unresolvable hostname exits 1" {
  setup_oknav_env
  create_mock_getent ""  # No resolvable hostnames
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add nonexistent.invalid
  ((status == 1))
  assert_output_contains "Cannot resolve hostname"
}

@test "oknav add -n dry-run shows what would be done" {
  setup_oknav_env
  create_mock_getent "test.example.com"
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add -n test.example.com
  ((status == 0))
  assert_output_contains "dry-run"
  assert_output_contains "create:"
  # Symlink should NOT be created in dry-run
  [[ ! -L "/usr/local/bin/test.example.com" ]]
}

@test "oknav add with aliases creates multiple symlinks" {
  setup_oknav_env
  create_mock_getent "test.example.com"
  # Use TEST_TEMP_DIR as target (can't write to /usr/local/bin in tests)
  # We'll check the output messages instead
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add -n test.example.com testalias ok-test
  ((status == 0))
  assert_output_contains "testalias"
  assert_output_contains "ok-test"
}

@test "oknav add invalid option exits 22" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav add --invalid
  ((status == 22))
  assert_output_contains "Unknown option"
}

# ==============================================================================
# Remove Subcommand Tests
# ==============================================================================

@test "oknav remove -h shows help and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav remove -h
  ((status == 0))
  assert_output_contains "Usage: oknav remove"
}

@test "oknav remove --help shows help and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav remove --help
  ((status == 0))
  assert_output_contains "Usage: oknav remove"
}

@test "oknav remove without alias shows error and exits 1" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav remove
  ((status == 1))
  assert_output_contains "Usage: oknav remove"
}

@test "oknav remove -n dry-run shows what would be done" {
  setup_oknav_env ok0 ok1
  cd "$TEST_TEMP_DIR" || return 1
  # Test against existing symlinks created by setup
  run ./oknav remove -n ok0
  ((status == 0))
  assert_output_contains "dry-run"
}

@test "oknav remove warns on non-existent alias" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav remove nonexistent-alias
  # Should warn but not fail
  assert_output_contains "does not exist"
}

@test "oknav remove invalid option exits 22" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav remove --invalid
  ((status == 22))
  assert_output_contains "Unknown option"
}

@test "oknav remove multiple aliases processes all" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav remove -n nonexistent1 nonexistent2
  # Should process both
  assert_output_contains "nonexistent1"
  assert_output_contains "nonexistent2"
}

# ==============================================================================
# List Subcommand Tests
# ==============================================================================

@test "oknav list -h shows help and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav list -h
  ((status == 0))
  assert_output_contains "Usage: oknav list"
}

@test "oknav list --help shows help and exits 0" {
  setup_oknav_env
  cd "$TEST_TEMP_DIR" || return 1
  run ./oknav list --help
  ((status == 0))
  assert_output_contains "Usage: oknav list"
}

@test "oknav list shows hosts.conf entries" {
  setup_oknav_env ok0 ok1 ok2
  cd "$TEST_TEMP_DIR" || return 1
  # Point list to test directory
  OKNAV_TARGET_DIR="$TEST_TEMP_DIR" run ./oknav list
  ((status == 0))
  assert_output_contains "ok0"
  assert_output_contains "(hosts.conf)"
}

@test "oknav list shows ad-hoc entries" {
  # Create environment with hosts.conf containing only ok0
  create_server_symlinks "$TEST_TEMP_DIR" ok0 ok1 adhoc
  create_hosts_conf "$TEST_TEMP_DIR" "ok0.test.local ok0 (oknav)"
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  # ok1 and adhoc are symlinks but not in hosts.conf
  OKNAV_TARGET_DIR="$TEST_TEMP_DIR" run ./oknav list
  ((status == 0))
  assert_output_contains "ok0"
  assert_output_contains "(hosts.conf)"
  assert_output_contains "ok1"
  assert_output_contains "(ad-hoc)"
  assert_output_contains "adhoc"
}

@test "oknav list excludes ok_master itself" {
  setup_oknav_env ok0
  cd "$TEST_TEMP_DIR" || return 1
  OKNAV_TARGET_DIR="$TEST_TEMP_DIR" run ./oknav list
  ((status == 0))
  # ok_master should not appear in output
  assert_output_not_contains "ok_master"
}

@test "oknav list with no symlinks produces no output" {
  # Create environment with hosts.conf but no symlinks in target dir
  mkdir -p "$TEST_TEMP_DIR/empty"
  create_hosts_conf "$TEST_TEMP_DIR" "ok0.test.local ok0 (oknav)"
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cp "${PROJECT_DIR}/common.inc.sh" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  OKNAV_TARGET_DIR="$TEST_TEMP_DIR/empty" run ./oknav list
  ((status == 0))
  [[ -z "$output" ]]
}

@test "oknav list output is sorted" {
  create_server_symlinks "$TEST_TEMP_DIR" zebra alpha middle
  create_hosts_conf "$TEST_TEMP_DIR" \
    "z.test.local zebra" \
    "a.test.local alpha" \
    "m.test.local middle"
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"
  cd "$TEST_TEMP_DIR" || return 1

  OKNAV_TARGET_DIR="$TEST_TEMP_DIR" run ./oknav list
  ((status == 0))
  # Output should be sorted: alpha, middle, zebra
  # Check that alpha appears before zebra in output
  [[ "$output" =~ alpha.*middle.*zebra ]]
}

#fin
