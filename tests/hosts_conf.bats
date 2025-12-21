#!/usr/bin/env bats
# ==============================================================================
# OKnav Test Suite - hosts.conf Parsing Unit Tests
# ==============================================================================
# Tests for hosts.conf parsing functions in common.inc.sh
#
# Functions tested:
#   load_hosts_conf()      - Parse hosts.conf into arrays
#   resolve_alias()        - Resolve alias to FQDN with constraint checking
#   is_excluded()          - Check if alias has (exclude) option
#   get_local_only_host()  - Get required hostname for local-only alias
#
# Run: bats tests/hosts_conf.bats
# ==============================================================================

load test_helper

# ==============================================================================
# load_hosts_conf() Tests
# ==============================================================================

@test "load_hosts_conf parses simple entry" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.test.local  srv"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${ALIAS_TO_FQDN[srv]}"
  '
  ((status == 0))
  [[ "$output" == "server.test.local" ]]
}

@test "load_hosts_conf parses multiple aliases" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.test.local  srv server s"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${ALIAS_TO_FQDN[srv]}|${ALIAS_TO_FQDN[server]}|${ALIAS_TO_FQDN[s]}"
  '
  ((status == 0))
  [[ "$output" == "server.test.local|server.test.local|server.test.local" ]]
}

@test "load_hosts_conf parses local-only option" {
  create_hosts_conf "$TEST_TEMP_DIR" "dev.local  okdev  (local-only:workstation)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${ALIAS_OPTIONS[okdev]}"
  '
  ((status == 0))
  [[ "$output" == "local-only:workstation" ]]
}

@test "load_hosts_conf parses exclude option" {
  create_hosts_conf "$TEST_TEMP_DIR" "backup.local  bak  (exclude)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${ALIAS_OPTIONS[bak]}"
  '
  ((status == 0))
  [[ "$output" == "exclude" ]]
}

@test "load_hosts_conf handles combined options" {
  create_hosts_conf "$TEST_TEMP_DIR" "special.local  sp  (local-only:myhost,exclude)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${ALIAS_OPTIONS[sp]}"
  '
  ((status == 0))
  [[ "$output" == "local-only:myhost,exclude" ]]
}

@test "load_hosts_conf ignores comments" {
  cat > "${TEST_TEMP_DIR}/hosts.conf" <<'EOF'
# This is a comment
server1.local  s1
  # Indented comment
server2.local  s2
EOF

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    export OKNAV_HOSTS_CONF="'"$TEST_TEMP_DIR"'/hosts.conf"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${#ALIAS_TO_FQDN[@]}"
  '
  ((status == 0))
  [[ "$output" == "2" ]]
}

@test "load_hosts_conf ignores blank lines" {
  cat > "${TEST_TEMP_DIR}/hosts.conf" <<'EOF'
server1.local  s1

server2.local  s2

EOF

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    export OKNAV_HOSTS_CONF="'"$TEST_TEMP_DIR"'/hosts.conf"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${#ALIAS_TO_FQDN[@]}"
  '
  ((status == 0))
  [[ "$output" == "2" ]]
}

@test "load_hosts_conf fails on missing file" {
  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf "/nonexistent/hosts.conf"
  '
  ((status != 0))
  assert_output_contains "hosts.conf not found"
}

@test "load_hosts_conf fails on empty file" {
  echo "" > "${TEST_TEMP_DIR}/hosts.conf"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    export OKNAV_HOSTS_CONF="'"$TEST_TEMP_DIR"'/hosts.conf"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
  '
  ((status != 0))
  assert_output_contains "No valid entries"
}

@test "load_hosts_conf populates ALIAS_LIST in order" {
  cat > "${TEST_TEMP_DIR}/hosts.conf" <<'EOF'
server1.local  s1
server2.local  s2
server3.local  s3
EOF

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    export OKNAV_HOSTS_CONF="'"$TEST_TEMP_DIR"'/hosts.conf"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    echo "${ALIAS_LIST[*]}"
  '
  ((status == 0))
  [[ "$output" == "s1 s2 s3" ]]
}

# ==============================================================================
# resolve_alias() Tests
# ==============================================================================

@test "resolve_alias returns FQDN for valid alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "myserver.example.com  myserv"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    resolve_alias myserv
  '
  ((status == 0))
  [[ "$output" == "myserver.example.com" ]]
}

@test "resolve_alias returns 1 for unknown alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  known"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    resolve_alias unknown
  '
  ((status == 1))
}

@test "resolve_alias returns 2 when local-only constraint violated" {
  create_hosts_conf "$TEST_TEMP_DIR" "dev.local  okdev  (local-only:required-host)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    resolve_alias okdev
  '
  ((status == 2))
  assert_output_contains "restricted to host"
}

@test "resolve_alias succeeds when local-only constraint satisfied" {
  create_hosts_conf "$TEST_TEMP_DIR" "dev.local  okdev  (local-only:$(hostname))"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    resolve_alias okdev
  '
  ((status == 0))
  [[ "$output" == "dev.local" ]]
}

@test "resolve_alias ignores exclude option (no constraint)" {
  create_hosts_conf "$TEST_TEMP_DIR" "backup.local  bak  (exclude)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    resolve_alias bak
  '
  ((status == 0))
  [[ "$output" == "backup.local" ]]
}

# ==============================================================================
# is_excluded() Tests
# ==============================================================================

@test "is_excluded returns true for excluded alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "backup.local  bak  (exclude)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_excluded bak && echo "yes" || echo "no"
  '
  [[ "$output" == "yes" ]]
}

@test "is_excluded returns false for non-excluded alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  srv"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_excluded srv && echo "yes" || echo "no"
  '
  [[ "$output" == "no" ]]
}

@test "is_excluded detects exclude in combined options" {
  create_hosts_conf "$TEST_TEMP_DIR" "special.local  sp  (local-only:host,exclude)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_excluded sp && echo "yes" || echo "no"
  '
  [[ "$output" == "yes" ]]
}

# ==============================================================================
# is_oknav() Tests
# ==============================================================================

@test "is_oknav returns true for oknav alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  srv  (oknav)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_oknav srv && echo "yes" || echo "no"
  '
  [[ "$output" == "yes" ]]
}

@test "is_oknav returns false for non-oknav alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  srv"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_oknav srv && echo "yes" || echo "no"
  '
  [[ "$output" == "no" ]]
}

@test "is_oknav returns true for first (primary) alias with oknav" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  ok0 okusi0  (oknav)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_oknav ok0 && echo "yes" || echo "no"
  '
  [[ "$output" == "yes" ]]
}

@test "is_oknav returns false for secondary alias even with oknav" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  ok0 okusi0  (oknav)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_oknav okusi0 && echo "yes" || echo "no"
  '
  [[ "$output" == "no" ]]
}

@test "is_oknav detects oknav in combined options" {
  create_hosts_conf "$TEST_TEMP_DIR" "dev.local  okdev  (oknav,local-only:host)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    is_oknav okdev && echo "yes" || echo "no"
  '
  [[ "$output" == "yes" ]]
}

# ==============================================================================
# get_local_only_host() Tests
# ==============================================================================

@test "get_local_only_host returns hostname for local-only alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "dev.local  okdev  (local-only:workstation)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    get_local_only_host okdev
  '
  ((status == 0))
  [[ "$output" == "workstation" ]]
}

@test "get_local_only_host returns empty for non-local-only alias" {
  create_hosts_conf "$TEST_TEMP_DIR" "server.local  srv"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    result=$(get_local_only_host srv)
    echo "result:${result}:end"
  '
  ((status == 0))
  [[ "$output" == "result::end" ]]
}

@test "get_local_only_host extracts hostname from combined options" {
  create_hosts_conf "$TEST_TEMP_DIR" "special.local  sp  (local-only:myhost,exclude)"

  run bash -c '
    export SCRIPT_NAME=test SCRIPT_DIR="'"$TEST_TEMP_DIR"'"
    source "'"${PROJECT_DIR}"'/common.inc.sh"
    load_hosts_conf
    get_local_only_host sp
  '
  ((status == 0))
  [[ "$output" == "myhost" ]]
}

#fin
