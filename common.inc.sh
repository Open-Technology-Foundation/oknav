#!/bin/bash
# ==============================================================================
# OKnav System - Common Include File
# ==============================================================================
# Shared configuration and utility functions for OKnav scripts.
# Must be sourced (not executed) by oknav and ok_master.
#
# Exports:
#   VERSION        - OKnav version string (readonly)
#   TEMP_DIR       - Secure temporary directory path (readonly)
#   DEBUG          - Debug mode flag (0=off, 1=on, exported integer)
#   HOSTNAME       - Current machine hostname
#   ALIAS_TO_FQDN  - Associative array: alias -> FQDN
#   ALIAS_OPTIONS  - Associative array: alias -> options string
#   ALIAS_LIST     - Indexed array: ordered list of aliases
#
# Functions:
#   error()             - Print error message to stderr
#   warn()              - Print warning message to stderr
#   debug()             - Print debug message (if DEBUG=1)
#   die()               - Print error and exit with code
#   remblanks()         - Strip comments and blank lines from input
#   find_hosts_conf()   - Locate hosts.conf in /etc/oknav/ or script directory
#   load_hosts_conf()   - Parse hosts.conf into arrays
#   resolve_alias()     - Resolve alias to FQDN with constraint checking
#   is_excluded()       - Check if alias has (exclude) option
#   get_local_only_host() - Get required hostname for local-only alias
#
# Requires:
#   SCRIPT_NAME - Must be set by sourcing script before source
# ==============================================================================
#shellcheck disable=SC2155,SC2034
set -eu
shopt -s inherit_errexit

# Global configuration
declare -r VERSION='2.2.2'

# Set up runtime directory for temporary files
# Prefers XDG_RUNTIME_DIR (typically /run/user/UID), falls back to /tmp
declare -r RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
if [[ ! -d "$RUNTIME_DIR" ]] || [[ ! -w "$RUNTIME_DIR" ]]; then
  # Fall back to /tmp if runtime dir not available
  declare -r TEMP_DIR=/tmp
else
  declare -r TEMP_DIR="$RUNTIME_DIR"
fi

#------------------------------------------------------------------------
declare -ix VERBOSE=1 DEBUG=0

# Color definitions
if [[ -t 1 && -t 2 ]]; then
  readonly -- RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' CYAN=$'\033[0;36m' BOLD=$'\033[1m' NC=$'\033[0m'
else
  readonly -- RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

# Utility functions
_msg() {
  local -- status="${FUNCNAME[1]}" prefix="$SCRIPT_NAME:" msg
  case "$status" in
    vecho)   : ;;
    info)    prefix+=" ${CYAN}◉${NC}" ;;
    warn)    prefix+=" ${YELLOW}▲${NC}" ;;
    success) prefix+=" ${GREEN}✓${NC}" ;;
    error)   prefix+=" ${RED}✗${NC}" ;;
    debug)   prefix+=" ${YELLOW}DEBUG:${NC}" ;;
  esac
  for msg in "$@"; do printf '%s %s\n' "$prefix" "$msg"; done
}

# vecho() -
vecho() { ((VERBOSE)) || return 0; _msg "$@"; }

# info() -
info() { ((VERBOSE)) || return 0; >&2 _msg "$@"; }

# warn() - Print warning message to stderr
# Args: message
warn() { ((VERBOSE)) || return 0; >&2 _msg "$@"; }

# debug() - Print debug message to stderr
# Args: message
debug() { ((DEBUG)) || return 0; >&2 _msg "$@"; }

# success() -
success() { ((VERBOSE)) || return 0; >&2 _msg "$@" || return 0; }

# error() - Print error message to stderr
# Args: message
error() { >&2 _msg "$@"; }

# die() - Print error message and exit with code
# Args: exit_code [error_message]
# Returns: exits with provided code (default: 1)
die() { (($# > 1)) && error "${@:2}"; exit "${1:-0}"; }


#---------------------------------------------------------------------------
# remblanks() - Strip comments and blank lines from input
# Args: [string...] - Optional string arguments to process
# Stdin: If no args, reads from stdin (pipe mode)
# Returns: Filtered output without comment lines (^#) or blank lines
remblanks() {
  if (($#)); then
    # Arguments provided - process as string
    echo "$*" | grep -v '^[[:blank:]]*#\|^[[:blank:]]*$'
  else
    # No arguments - read from stdin (pipe mode)
    grep -v '^[[:blank:]]*#\|^[[:blank:]]*$'
  fi
}

# Determine current hostname for server filtering
HOSTNAME=$(hostname) || die 1 'Cannot determine hostname'

# ==============================================================================
# hosts.conf Parsing Functions
# ==============================================================================
# Configuration file format:
#   FQDN  alias [alias2...] [(options)]
#
# Options (comma-separated in parentheses):
#   local-only:HOSTNAME  - Restrict access to specified host
#   exclude              - Exclude from cluster operations
#
# Example:
#   server0.example.com  srv0 server0
#   devbox.local         dev  (local-only:workstation)
#   backup.local         bak  (exclude)
# ==============================================================================

# Global arrays for hosts.conf data
declare -gA ALIAS_TO_FQDN=()      # alias -> FQDN mapping
declare -gA ALIAS_OPTIONS=()      # alias -> options string
declare -ga ALIAS_LIST=()         # ordered list of aliases
declare -gA FQDN_PRIMARY_ALIAS=() # fqdn -> first (primary) alias

# find_hosts_conf() - Locate hosts.conf in standard locations
# Args: none
# Stdout: Path to hosts.conf if found
# Returns: 0 if found, 1 if not found
# Search order:
#   1. /etc/oknav/hosts.conf (system config)
#   2. $SCRIPT_DIR/hosts.conf (dev/local config)
find_hosts_conf() {
  local -- config
  for config in "/etc/oknav/hosts.conf" "${SCRIPT_DIR:-$(dirname "$0")}/hosts.conf"; do
    [[ -f "$config" ]] && { echo "$config"; return 0; }
  done
  return 1
}

# load_hosts_conf() - Parse hosts.conf into global arrays
# Args: [hosts_conf_path] - Path to hosts.conf (default: auto-detect via find_hosts_conf)
# Returns: 0 on success, dies on error
# Side effects: Populates ALIAS_TO_FQDN, ALIAS_OPTIONS, ALIAS_LIST
load_hosts_conf() {
  local -- hosts_file="${1:-}"
  local -- line fqdn aliases options alias
  local -- options_re='[(]([^)]+)[)][[:space:]]*$'

  # Auto-detect hosts.conf if not provided
  if [[ -z "$hosts_file" ]]; then
    hosts_file=$(find_hosts_conf) || die 1 "hosts.conf not found in /etc/oknav/ or script directory"
  fi

  # Clear previous data
  ALIAS_TO_FQDN=()
  ALIAS_OPTIONS=()
  ALIAS_LIST=()
  FQDN_PRIMARY_ALIAS=()

  [[ -f "$hosts_file" ]] || die 1 "hosts.conf not found: ${hosts_file@Q}"

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue ||:

    # Extract options if present: (option1,option2)
    options=''
    if [[ "$line" =~ $options_re ]]; then
      options="${BASH_REMATCH[1]}"
      line="${line%\(*}"  # Remove options from line
    fi

    # Trim trailing whitespace
    line="${line%"${line##*[![:space:]]}"}"

    # Split: first field is FQDN, rest are aliases
    read -r fqdn aliases <<< "$line"
    [[ -n "$fqdn" ]] || continue

    # Register each alias (first alias becomes primary)
    local -- first_alias=''
    for alias in $aliases; do
      ALIAS_TO_FQDN["$alias"]="$fqdn"
      ALIAS_OPTIONS["$alias"]="$options"
      ALIAS_LIST+=("$alias")
      [[ -z "$first_alias" ]] && first_alias="$alias"
    done
    # Store primary (first) alias for this FQDN
    [[ -n "$first_alias" ]] && FQDN_PRIMARY_ALIAS["$fqdn"]="$first_alias"
  done < "$hosts_file"

  ((${#ALIAS_TO_FQDN[@]})) || die 1 'No valid entries in hosts.conf'
  debug "Loaded ${#ALIAS_TO_FQDN[@]} aliases from ${hosts_file@Q}"
}

# resolve_alias() - Resolve alias to FQDN with constraint checking
# Args: alias
# Stdout: FQDN
# Returns: 0 on success, 1 if not found, 2 if constraint violated
resolve_alias() {
  local -- alias="$1"
  local -- fqdn options required_host
  local -- local_only_re='local-only:([^,)]+)'

  fqdn="${ALIAS_TO_FQDN[$alias]:-}"
  [[ -n "$fqdn" ]] || return 1

  options="${ALIAS_OPTIONS[$alias]:-}"

  # Check local-only constraint
  if [[ "$options" =~ $local_only_re ]]; then
    required_host="${BASH_REMATCH[1]}"
    if [[ "$HOSTNAME" != "$required_host" ]]; then
      error "$alias: restricted to host ${required_host@Q} (current: $HOSTNAME)"
      return 2
    fi
  fi

  echo "$fqdn"
}

# is_excluded() - Check if alias has exclude option
# Args: alias
# Returns: 0 if excluded, 1 if not
is_excluded() {
  local -- alias="$1"
  local -- options="${ALIAS_OPTIONS[$alias]:-}"
  [[ "$options" == *exclude* ]]
}

# is_oknav() - Check if alias is designated for cluster operations
# Args: alias
# Returns: 0 if oknav-enabled, 1 if not
# Note: Only the primary (first) alias for each FQDN is included
is_oknav() {
  local -- alias="$1"
  local -- options="${ALIAS_OPTIONS[$alias]:-}"
  local -- fqdn="${ALIAS_TO_FQDN[$alias]:-}"

  # Must have oknav option
  [[ "$options" == *oknav* ]] || return 1

  # Must be the primary (first) alias for this FQDN
  [[ "${FQDN_PRIMARY_ALIAS[$fqdn]:-}" == "$alias" ]]
}

# get_local_only_host() - Get required hostname for local-only alias
# Args: alias
# Stdout: hostname or empty string
# Returns: 0 always
get_local_only_host() {
  local -- alias="$1"
  local -- options="${ALIAS_OPTIONS[$alias]:-}"
  local -- local_only_re='local-only:([^,)]+)'
  if [[ "$options" =~ $local_only_re ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

#fin
