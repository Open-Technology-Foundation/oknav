#!/usr/bin/env bash
# ==============================================================================
# OKnav System - Common Include File
# ==============================================================================
# Shared configuration and utility functions for oknav and ok_master.
# Must be sourced (not executed): source common.inc.sh
#
# Exports (readonly):
#   VERSION              - OKnav version string
#   TEMP_DIR             - Secure temp directory (XDG_RUNTIME_DIR or /tmp)
#
# Exports (mutable):
#   VERBOSE              - Verbose output flag (default: 1)
#   DEBUG                - Debug mode flag (default: 0)
#   HOSTNAME             - Current machine hostname
#
# Arrays (populated by load_hosts_conf):
#   ALIAS_TO_FQDN        - Associative: alias → FQDN
#   ALIAS_OPTIONS        - Associative: alias → options string
#   ALIAS_LIST           - Indexed: ordered list of all aliases
#   FQDN_PRIMARY_ALIAS   - Associative: FQDN → primary (first) alias
#
# Functions:
#   vecho(), info(), warn(), success(), error() - Output messages
#   debug()              - Output if DEBUG=1
#   die()                - Print error and exit
#   remblanks()          - Strip comments and blank lines
#   find_hosts_conf()    - Locate hosts.conf file
#   load_hosts_conf()    - Parse hosts.conf into arrays
#   resolve_alias()      - Resolve alias to FQDN (checks constraints)
#   is_excluded()        - Check for (exclude) option
#   is_oknav()           - Check for (oknav) option (primary alias only)
#   get_local_only_host() - Extract hostname from (local-only:HOST)
#
# Requires: SCRIPT_NAME must be set before sourcing
# ==============================================================================
#shellcheck disable=SC2155,SC2034
set -eu
shopt -s inherit_errexit

# Global configuration
declare -r VERSION=2.3.0

# Set up runtime directory for temporary files
# Prefers XDG_RUNTIME_DIR (typically /run/user/UID), falls back to /tmp
declare -r RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
if [[ ! -d "$RUNTIME_DIR" ]] || [[ ! -w "$RUNTIME_DIR" ]]; then
  # Fall back to /tmp if runtime dir not available
  declare -r TEMP_DIR=/tmp
else
  declare -r TEMP_DIR="$RUNTIME_DIR"
fi

# ------------------------------------------------------------------------------
# Output Control
# ------------------------------------------------------------------------------
declare -ix VERBOSE=1 DEBUG=0

# Colors: enabled only when stdout and stderr are terminals
if [[ -t 1 && -t 2 ]]; then
  readonly -- RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' CYAN=$'\033[0;36m' BOLD=$'\033[1m' NC=$'\033[0m'
else
  readonly -- RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

# ------------------------------------------------------------------------------
# Messaging Functions
# All respect VERBOSE flag except error() which always outputs.
# Icons: ◉ info, ▲ warn, ✓ success, ✗ error
# ------------------------------------------------------------------------------
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

vecho()   { ((VERBOSE)) || return 0; _msg "$@"; }     # Verbose echo (stdout)
info()    { ((VERBOSE)) || return 0; >&2 _msg "$@"; } # Info message (stderr)
warn()    { ((VERBOSE)) || return 0; >&2 _msg "$@"; } # Warning (stderr)
success() { ((VERBOSE)) || return 0; >&2 _msg "$@"; } # Success (stderr)
debug()   { ((DEBUG)) || return 0; >&2 _msg "$@"; }   # Debug (stderr, if DEBUG=1)
error()   { >&2 _msg "$@"; }                          # Error (always, stderr)

# die() - Print error and exit
# Args: exit_code [message...]
# Default exit code: 1
die() { (($# > 1)) && error "${@:2}" ||:; exit "${1:-1}"; }


# ------------------------------------------------------------------------------
# remblanks() - Filter out comments and blank lines
# Args: [string...] or stdin
# ------------------------------------------------------------------------------
remblanks() {
  if (($#)); then
    echo "$*" | grep -v '^[[:blank:]]*#\|^[[:blank:]]*$'
  else
    grep -v '^[[:blank:]]*#\|^[[:blank:]]*$'
  fi
}

# Capture hostname for local-only constraint checking
HOSTNAME=$(hostname) || die 1 'Cannot determine hostname'

# ==============================================================================
# hosts.conf Parsing
# ==============================================================================
# Format: FQDN  alias [alias2...] [(options)]
#
# Options (comma-separated):
#   (oknav)              Include in cluster operations (primary alias only)
#   (exclude)            Exclude from cluster (with oknav)
#   (local-only:HOST)    Only accessible from specified host
#
# Example:
#   server0.example.com  ok0 server0   (oknav)
#   devbox.local         okdev         (oknav,local-only:workstation)
#   backup.local         bak           (oknav,exclude)
#   adhoc.example.com    adhoc         # Direct access only, not in cluster
# ==============================================================================

declare -gA ALIAS_TO_FQDN=()      # alias → FQDN
declare -gA ALIAS_OPTIONS=()      # alias → options string
declare -ga ALIAS_LIST=()         # Ordered list of all aliases
declare -gA FQDN_PRIMARY_ALIAS=() # FQDN → primary (first) alias

# ------------------------------------------------------------------------------
# find_hosts_conf() - Locate hosts.conf
# Search order: $OKNAV_HOSTS_CONF → /etc/oknav/ → $SCRIPT_DIR
# Returns: 0 found (path on stdout), 1 not found
# ------------------------------------------------------------------------------
find_hosts_conf() {
  # Environment override (for testing)
  if [[ -n "${OKNAV_HOSTS_CONF:-}" && -f "$OKNAV_HOSTS_CONF" ]]; then
    echo "$OKNAV_HOSTS_CONF"
    return 0
  fi
  local -- config
  for config in /etc/oknav/hosts.conf "${SCRIPT_DIR:-$(dirname "$0")}/hosts.conf"; do
    [[ -f "$config" ]] && { echo "$config"; return 0; } ||:
  done
  return 1
}

# ------------------------------------------------------------------------------
# load_hosts_conf() - Parse hosts.conf into global arrays
# Args: [path] (default: auto-detect)
# Populates: ALIAS_TO_FQDN, ALIAS_OPTIONS, ALIAS_LIST, FQDN_PRIMARY_ALIAS
# Dies on: missing file, empty file
# ------------------------------------------------------------------------------
load_hosts_conf() {
  local -- hosts_file="${1:-}"
  local -- line fqdn aliases options alias
  local -- options_re='[(]([^)]+)[)][[:space:]]*$'

  # Auto-detect hosts.conf if not provided
  if [[ -z "$hosts_file" ]]; then
    hosts_file=$(find_hosts_conf) || die 1 'hosts.conf not found in /etc/oknav/ or script directory'
  fi

  # Clear previous data
  ALIAS_TO_FQDN=()
  ALIAS_OPTIONS=()
  ALIAS_LIST=()
  FQDN_PRIMARY_ALIAS=()

  [[ -f "$hosts_file" ]] || die 1 "hosts.conf not found ${hosts_file@Q}"

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

# ------------------------------------------------------------------------------
# resolve_alias() - Resolve alias to FQDN with constraint checking
# Args: alias
# Stdout: FQDN
# Returns: 0 success, 1 not found, 2 local-only constraint violated
# ------------------------------------------------------------------------------
resolve_alias() {
  local -- alias=$1
  local -- fqdn options required_host
  local -- local_only_re='local-only:([^,)]+)'

  fqdn="${ALIAS_TO_FQDN[$alias]:-}"
  [[ -n "$fqdn" ]] || return 1

  options="${ALIAS_OPTIONS[$alias]:-}"

  # Check local-only constraint
  if [[ "$options" =~ $local_only_re ]]; then
    required_host="${BASH_REMATCH[1]}"
    if [[ "$HOSTNAME" != "$required_host" ]]; then
      error "$alias: restricted to host ${required_host@Q} (current: ${HOSTNAME@Q})"
      return 2
    fi
  fi

  echo "$fqdn"
}

# ------------------------------------------------------------------------------
# is_excluded() - Check for (exclude) option
# Returns: 0 if excluded, 1 if not
# ------------------------------------------------------------------------------
is_excluded() {
  local -- alias=$1
  [[ "${ALIAS_OPTIONS[$alias]:-}" == *exclude* ]]
}

# ------------------------------------------------------------------------------
# is_oknav() - Check for (oknav) option on primary alias
# Returns: 0 if oknav-enabled AND primary alias, 1 otherwise
# Note: Secondary aliases for same FQDN return 1 even with (oknav)
# ------------------------------------------------------------------------------
is_oknav() {
  local -- alias=$1
  local -- options="${ALIAS_OPTIONS[$alias]:-}"
  local -- fqdn="${ALIAS_TO_FQDN[$alias]:-}"
  [[ "$options" == *oknav* ]] || return 1
  [[ "${FQDN_PRIMARY_ALIAS[$fqdn]:-}" == "$alias" ]]
}

# ------------------------------------------------------------------------------
# get_local_only_host() - Extract hostname from (local-only:HOST)
# Stdout: hostname or empty
# Returns: 0 always
# ------------------------------------------------------------------------------
get_local_only_host() {
  local -- alias=$1
  local -- options="${ALIAS_OPTIONS[$alias]:-}"
  local -- local_only_re='local-only:([^,)]+)'
  if [[ "$options" =~ $local_only_re ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

#fin
