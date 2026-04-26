#!/usr/bin/env bats
# ==============================================================================
# OKnav Test Suite - common.inc.sh Unit Tests
# ==============================================================================
# Tests for shared utilities in common.inc.sh
#
# Run: bats tests/common.bats
# ==============================================================================

load test_helper

# ==============================================================================
# Variable Export Tests
# ==============================================================================

@test "VERSION is defined and not empty" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; echo "$VERSION"'
  [[ -n "$output" ]]
}

@test "VERSION matches expected format (semver)" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; echo "$VERSION"'
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "TEMP_DIR is defined" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; echo "$TEMP_DIR"'
  [[ -n "$output" ]]
}

@test "TEMP_DIR is a valid directory path" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; echo "$TEMP_DIR"'
  # Either XDG_RUNTIME_DIR or /tmp
  [[ "$output" == /tmp || "$output" =~ ^/run/user/ ]]
}

@test "HOSTNAME is captured from system" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; echo "$HOSTNAME"'
  [[ -n "$output" ]]
  # Should match actual hostname
  [[ "$output" == "$(hostname)" ]]
}

@test "DEBUG defaults to 0" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; echo "$DEBUG"'
  [[ "$output" == "0" ]]
}

# ==============================================================================
# error() Function Tests
# ==============================================================================

@test "error() outputs to stderr" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; error "test message" 2>&1'
  assert_output_contains "test message"
}

@test "error() includes SCRIPT_NAME prefix" {
  export SCRIPT_NAME="mytest"
  source_common
  run bash -c 'export SCRIPT_NAME=mytest; source '"${PROJECT_DIR}"'/common.inc.sh; error "test message" 2>&1'
  assert_output_contains "mytest:"
}

@test "error() includes error icon" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; error "test message" 2>&1'
  assert_output_contains "✗"
}

# ==============================================================================
# warn() Function Tests
# ==============================================================================

@test "warn() outputs to stderr" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; warn "warning message" 2>&1'
  assert_output_contains "warning message"
}

@test "warn() includes warning icon" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; warn "warning message" 2>&1'
  assert_output_contains "▲"
}

# ==============================================================================
# debug() Function Tests
# ==============================================================================

@test "debug() is silent when DEBUG=0" {
  run bash -c 'export SCRIPT_NAME=test DEBUG=0; source '"${PROJECT_DIR}"'/common.inc.sh; debug "debug message" 2>&1'
  [[ -z "$output" ]]
}

@test "debug() outputs when DEBUG=1" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; DEBUG=1; debug "debug message" 2>&1'
  assert_output_contains "debug message"
}

@test "debug() includes 'DEBUG:' label when enabled" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; DEBUG=1; debug "debug message" 2>&1'
  assert_output_contains "DEBUG:"
}

# ==============================================================================
# die() Function Tests
# ==============================================================================

@test "die() exits with specified code" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; die 42'
  ((status == 42))
}

@test "die() exits with code 1 by default" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; die'
  ((status == 1))
}

@test "die() prints error message to stderr" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; die 1 "fatal error" 2>&1'
  assert_output_contains "fatal error"
}

@test "die() with only exit code prints nothing" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; die 0 2>&1'
  [[ -z "$output" ]]
}

# ==============================================================================
# VERBOSE / DEBUG Gating Tests
# ==============================================================================
# common.inc.sh:73 declares VERBOSE=1 DEBUG=0 by default. info/success/vecho/warn
# require VERBOSE=1; debug requires DEBUG=1 independently. error always outputs.

@test "info() is silent when VERBOSE=0" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=0; info "hello" 2>&1'
  [[ -z "$output" ]]
}

@test "info() outputs to stderr when VERBOSE=1 (default)" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; info "hello info" 2>&1'
  assert_output_contains "hello info"
  assert_output_contains "◉"
}

@test "success() is silent when VERBOSE=0" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=0; success "ok" 2>&1'
  [[ -z "$output" ]]
}

@test "success() outputs when VERBOSE=1 with check icon" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; success "all good" 2>&1'
  assert_output_contains "all good"
  assert_output_contains "✓"
}

@test "vecho() is silent when VERBOSE=0" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=0; vecho "verbose msg"'
  [[ -z "$output" ]]
}

@test "vecho() outputs to stdout (not stderr) when VERBOSE=1" {
  # Capture stdout only; redirect stderr to /dev/null to verify vecho writes stdout.
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; vecho "verbose stdout" 2>/dev/null'
  assert_output_contains "verbose stdout"
}

@test "warn() outputs even when VERBOSE=0 (no gate)" {
  # warn() is intentionally ungated in common.inc.sh:101 — warnings always
  # surface regardless of VERBOSE. This pin documents that current behaviour.
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=0; warn "warn msg" 2>&1'
  assert_output_contains "warn msg"
}

@test "error() outputs even when VERBOSE=0" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=0; error "err msg" 2>&1'
  assert_output_contains "err msg"
}

@test "debug() with DEBUG=1 VERBOSE=0 still outputs (independent gate)" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=0; DEBUG=1; debug "dbg msg" 2>&1'
  assert_output_contains "dbg msg"
  assert_output_contains "DEBUG:"
}

@test "debug() with DEBUG=0 VERBOSE=1 stays silent" {
  run bash -c 'export SCRIPT_NAME=test; source '"${PROJECT_DIR}"'/common.inc.sh; VERBOSE=1; DEBUG=0; debug "dbg" 2>&1'
  [[ -z "$output" ]]
}

# ==============================================================================
# remblanks() Function Tests
# ==============================================================================

@test "remblanks() removes blank lines from stdin" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; echo -e "line1\n\nline2" | remblanks'
  [[ "${lines[0]}" == "line1" ]]
  [[ "${lines[1]}" == "line2" ]]
  ((${#lines[@]} == 2))
}

@test "remblanks() removes comment lines from stdin" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; echo -e "line1\n# comment\nline2" | remblanks'
  [[ "${lines[0]}" == "line1" ]]
  [[ "${lines[1]}" == "line2" ]]
  ((${#lines[@]} == 2))
}

@test "remblanks() removes lines with only whitespace" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; echo -e "line1\n   \nline2" | remblanks'
  [[ "${lines[0]}" == "line1" ]]
  [[ "${lines[1]}" == "line2" ]]
  ((${#lines[@]} == 2))
}

@test "remblanks() removes indented comments" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; echo -e "line1\n  # indented comment\nline2" | remblanks'
  [[ "${lines[0]}" == "line1" ]]
  [[ "${lines[1]}" == "line2" ]]
  ((${#lines[@]} == 2))
}

@test "remblanks() processes arguments instead of stdin" {
  source_common
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; remblanks "content line"'
  assert_output_contains "content line"
}

@test "remblanks() handles mixed content correctly" {
  source_common
  input=$'server1\n# excluded\n\nserver2\n  # also excluded\nserver3'
  run bash -c 'source '"${PROJECT_DIR}"'/common.inc.sh; echo '"'$input'"' | remblanks'
  ((${#lines[@]} == 3))
  [[ "${lines[0]}" == "server1" ]]
  [[ "${lines[1]}" == "server2" ]]
  [[ "${lines[2]}" == "server3" ]]
}

#fin
