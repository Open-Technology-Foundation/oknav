#!/bin/bash
# ==============================================================================
# OKnav Test Suite - Test Helper
# ==============================================================================
# Shared setup, teardown, mocks, and utilities for bats tests.
# Sourced by all .bats files via: load test_helper
#
# Provides:
#   - TEST_DIR, FIXTURES_DIR, PROJECT_DIR paths
#   - MOCK_BIN directory for mock executables
#   - setup/teardown functions for test isolation
#   - Mock creation utilities
#   - Custom assertions
# ==============================================================================

# Paths
export TEST_DIR="${BATS_TEST_DIRNAME}"
export FIXTURES_DIR="${TEST_DIR}/fixtures"
export PROJECT_DIR="${TEST_DIR}/.."

# Temporary directories (created per-test)
export TEST_TEMP_DIR=""
export MOCK_BIN=""
export MOCK_LOG=""

# Store original values for restoration
export ORIG_PATH="${PATH}"
export ORIG_HOSTNAME="${HOSTNAME:-}"

# ==============================================================================
# Setup and Teardown
# ==============================================================================

# setup() - Called before each test
# Creates isolated temp directory and mock bin directory
setup() {
  # Create unique temp directory for this test
  TEST_TEMP_DIR=$(mktemp -d "${BATS_TMPDIR}/oknav-test-XXXXXX")
  MOCK_BIN="${TEST_TEMP_DIR}/mock-bin"
  MOCK_LOG="${TEST_TEMP_DIR}/mock.log"

  mkdir -p "$MOCK_BIN"

  # Prepend mock bin to PATH
  export PATH="${MOCK_BIN}:${ORIG_PATH}"

  # Set SCRIPT_NAME for common.inc.sh (required before sourcing)
  export SCRIPT_NAME="test"
}

# teardown() - Called after each test
# Cleans up temp directories and restores environment
teardown() {
  # Restore original PATH
  export PATH="${ORIG_PATH}"

  # Restore hostname
  export HOSTNAME="${ORIG_HOSTNAME}"

  # Clear hosts.conf override
  unset OKNAV_HOSTS_CONF

  # Clean up temp directory
  if [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# ==============================================================================
# Mock Creation Utilities
# ==============================================================================

# create_mock_ssh() - Create mock SSH that logs calls
# Usage: create_mock_ssh [exit_code] [output]
create_mock_ssh() {
  local exit_code="${1:-0}"
  local output="${2:-}"

  # Export MOCK_LOG so subprocesses can use it
  export MOCK_LOG

  cat > "${MOCK_BIN}/ssh" <<EOF
#!/bin/bash
echo "SSH_CALL: \$*" >> "$MOCK_LOG"
${output:+echo "$output"}
exit $exit_code
EOF
  chmod +x "${MOCK_BIN}/ssh"
}

# create_mock_sudo() - Create mock sudo that executes command without privilege
# Usage: create_mock_sudo
create_mock_sudo() {
  # Export MOCK_LOG so subprocesses can use it
  export MOCK_LOG

  cat > "${MOCK_BIN}/sudo" <<EOF
#!/bin/bash
# Mock sudo: log and execute without actual privilege escalation
echo "SUDO_CALL: \$*" >> "$MOCK_LOG"
# Execute the command (first arg after sudo)
"\$@"
EOF
  chmod +x "${MOCK_BIN}/sudo"
}

# create_mock_timeout() - Create mock timeout command
# Usage: create_mock_timeout [exit_code]
create_mock_timeout() {
  local exit_code="${1:-0}"

  # Export MOCK_LOG so subprocesses can use it
  export MOCK_LOG

  cat > "${MOCK_BIN}/timeout" <<EOF
#!/bin/bash
echo "TIMEOUT_CALL: \$*" >> "$MOCK_LOG"
shift  # Remove timeout duration
"\$@"  # Execute remaining command
exit $exit_code
EOF
  chmod +x "${MOCK_BIN}/timeout"
}

# create_mock_hostname() - Create mock hostname command
# Usage: create_mock_hostname <hostname>
create_mock_hostname() {
  local hostname="$1"

  cat > "${MOCK_BIN}/hostname" <<EOF
#!/bin/bash
echo "$hostname"
EOF
  chmod +x "${MOCK_BIN}/hostname"
}

# create_server_symlinks() - Create ok* symlinks for testing
# Usage: create_server_symlinks <target_dir> [servers...]
# Example: create_server_symlinks "$TEST_TEMP_DIR" ok0 ok1 ok2
create_server_symlinks() {
  local target_dir="$1"
  shift
  local servers=("$@")

  # Default to ok0, ok1, ok2 if no servers specified
  if ((${#servers[@]} == 0)); then
    servers=(ok0 ok1 ok2)
  fi

  # Copy ok_master to target dir
  cp "${PROJECT_DIR}/ok_master" "${target_dir}/"
  cp "${PROJECT_DIR}/common.inc.sh" "${target_dir}/"

  # Create symlinks
  for server in "${servers[@]}"; do
    ln -sf ok_master "${target_dir}/${server}"
  done
}

# create_hosts_conf() - Create a hosts.conf file for testing
# Usage: create_hosts_conf <target_dir> [entry...]
# Each entry is a full line: "fqdn alias1 [alias2...] [(options)]"
# Example: create_hosts_conf "$TEST_TEMP_DIR" "server0.test.local ok0" "devbox.local okdev (local-only:testhost)"
# NOTE: Also exports OKNAV_HOSTS_CONF to override system config lookup
create_hosts_conf() {
  local target_dir="$1"
  shift
  local entries=("$@")

  # Default entries if none provided (with oknav for cluster tests)
  if ((${#entries[@]} == 0)); then
    entries=(
      "server0.test.local  ok0  (oknav)"
      "server1.test.local  ok1  (oknav)"
      "server2.test.local  ok2  (oknav)"
    )
  fi

  # Write entries to hosts.conf
  {
    echo "# Test hosts.conf"
    printf '%s\n' "${entries[@]}"
  } > "${target_dir}/hosts.conf"

  # Export override so tests use this hosts.conf instead of /etc/oknav/hosts.conf
  export OKNAV_HOSTS_CONF="${target_dir}/hosts.conf"
}

# ==============================================================================
# Assertion Helpers
# ==============================================================================

# assert_output_contains() - Check if output contains substring
# Usage: assert_output_contains "expected string"
assert_output_contains() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  fi
}

# assert_output_not_contains() - Check if output does NOT contain substring
# Usage: assert_output_not_contains "unexpected string"
assert_output_not_contains() {
  local unexpected="$1"
  if [[ "$output" == *"$unexpected"* ]]; then
    echo "Expected output NOT to contain: $unexpected"
    echo "Actual output: $output"
    return 1
  fi
}

# assert_line_contains() - Check if specific line contains substring
# Usage: assert_line_contains <line_number> "expected string"
assert_line_contains() {
  local line_num="$1"
  local expected="$2"
  if [[ "${lines[$line_num]}" != *"$expected"* ]]; then
    echo "Expected line $line_num to contain: $expected"
    echo "Actual line: ${lines[$line_num]}"
    return 1
  fi
}

# assert_mock_called() - Check if mock was called with specific args
# Usage: assert_mock_called "SSH_CALL" "expected args"
assert_mock_called() {
  local call_type="$1"
  local expected_args="$2"

  if [[ ! -f "$MOCK_LOG" ]]; then
    echo "Mock log not found: $MOCK_LOG"
    return 1
  fi

  if ! grep -q "${call_type}:.*${expected_args}" "$MOCK_LOG"; then
    echo "Expected mock call: ${call_type}: ... ${expected_args}"
    echo "Actual calls:"
    cat "$MOCK_LOG"
    return 1
  fi
}

# assert_mock_not_called() - Check that mock was NOT called
# Usage: assert_mock_not_called "SSH_CALL"
assert_mock_not_called() {
  local call_type="$1"

  if [[ -f "$MOCK_LOG" ]] && grep -q "${call_type}:" "$MOCK_LOG"; then
    echo "Expected no mock calls of type: ${call_type}"
    echo "But found:"
    grep "${call_type}:" "$MOCK_LOG"
    return 1
  fi
}

# assert_file_exists() - Check if file exists
# Usage: assert_file_exists "/path/to/file"
assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Expected file to exist: $file"
    return 1
  fi
}

# assert_file_not_exists() - Check that file does NOT exist
# Usage: assert_file_not_exists "/path/to/file"
assert_file_not_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "Expected file NOT to exist: $file"
    return 1
  fi
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# source_common() - Source common.inc.sh in test context
# Sets required SCRIPT_NAME before sourcing
source_common() {
  export SCRIPT_NAME="${1:-test}"
  # shellcheck source=../common.inc.sh
  source "${PROJECT_DIR}/common.inc.sh"
}

# run_ok_master() - Run ok_master via symlink with mocked SSH
# Usage: run_ok_master <symlink_name> [args...]
# Example: run_ok_master ok0 -D uptime
run_ok_master() {
  local symlink_name="$1"
  shift

  create_server_symlinks "$TEST_TEMP_DIR"
  create_mock_ssh

  # Export environment for subprocess
  export PATH MOCK_LOG

  # Run via symlink (cd required for script to find common.inc.sh)
  cd "$TEST_TEMP_DIR" || return 1
  run "./${symlink_name}" "$@"
}

# run_oknav() - Run oknav orchestrator with mocked commands
# Usage: run_oknav [args...]
run_oknav() {
  create_server_symlinks "$TEST_TEMP_DIR"
  create_mock_sudo
  create_mock_timeout

  # Copy oknav script
  cp "${PROJECT_DIR}/oknav" "${TEST_TEMP_DIR}/"

  # Export environment for subprocess
  export PATH MOCK_LOG

  cd "$TEST_TEMP_DIR" || return 1
  run "./oknav" "$@"
}

#fin
