#!/bin/bash
# ==============================================================================
# OKnav Installation Script
# ==============================================================================
# Installs OKnav SSH orchestration system to standard FHS locations.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/OkusiAssociates/oknav/main/install.sh | sudo bash
#   sudo ./install.sh
#   sudo ./install.sh --uninstall
#
# Installs to:
#   /usr/local/share/oknav/     - Package files (oknav, ok_master, common.inc.sh)
#   /usr/local/bin/             - Symlinks to executables
#   /etc/oknav/                 - Configuration (hosts.conf)
#   /usr/local/share/man/man1/  - Manual page
#   /etc/bash_completion.d/     - Bash completion
# ==============================================================================
set -euo pipefail
shopt -s inherit_errexit

# Configuration
declare -r VERSION='2.2.1'
declare -r REPO_URL='https://raw.githubusercontent.com/OkusiAssociates/oknav/main'
declare -r INSTALL_DIR='/usr/local/share/oknav'
declare -r BIN_DIR='/usr/local/bin'
declare -r CONFIG_DIR='/etc/oknav'
declare -r MAN_DIR='/usr/local/share/man/man1'
declare -r COMPLETION_DIR='/etc/bash_completion.d'

# Script metadata
declare -r SCRIPT_NAME="${0##*/}"
declare -- TEMP_DIR
TEMP_DIR=$(mktemp -d)
readonly TEMP_DIR

# Color support
if [[ -t 1 && -t 2 ]]; then
  declare -r RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' CYAN=$'\033[0;36m' NC=$'\033[0m' BOLD=$'\033[1m'
else
  declare -r RED='' GREEN='' YELLOW='' CYAN='' NC='' BOLD=''
fi

# Cleanup on exit
cleanup() {
  [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Message functions
error() { >&2 echo "${RED}✗${NC} $*"; }
warn() { >&2 echo "${YELLOW}▲${NC} $*"; }
info() { >&2 echo "${CYAN}◉${NC} $*"; }
success() { >&2 echo "${GREEN}✓${NC} $*"; }

# Check if running as root
is_root() { [[ $EUID -eq 0 ]]; }

# Require root privileges
require_root() {
  if ! is_root; then
    if sudo -ln &>/dev/null; then
      info "Elevating to root privileges..."
      exec sudo -E "$0" "$@"
    else
      error "This script requires root privileges."
      error "Run with: sudo $0 $*"
      exit 1
    fi
  fi
}

# Detect download tool
get_downloader() {
  if command -v curl >/dev/null 2>&1; then
    echo "curl -sSL"
  elif command -v wget >/dev/null 2>&1; then
    echo "wget -qO-"
  else
    error "Neither curl nor wget found. Please install one."
    exit 1
  fi
}

# Detect if running from local repo or curl-pipe
is_local_install() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$script_dir/oknav" && -f "$script_dir/ok_master" && -f "$script_dir/common.inc.sh" ]]
}

# Get source file (download or local)
get_source_file() {
  local filename="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if is_local_install; then
    # Local install - use files from repo
    if [[ -f "$script_dir/$filename" ]]; then
      cat "$script_dir/$filename"
    else
      error "Local file not found: $filename"
      return 1
    fi
  else
    # Remote install - download from GitHub
    local downloader
    downloader=$(get_downloader)
    $downloader "$REPO_URL/$filename" || {
      error "Failed to download: $filename"
      return 1
    }
  fi
}

# Display usage
usage() {
  cat <<EOT
${BOLD}OKnav Installer v$VERSION${NC}

Usage:
  $SCRIPT_NAME [OPTIONS]

Options:
  --uninstall    Remove OKnav installation
  --help, -h     Show this help message

Installation Methods:
  # From GitHub (recommended):
  curl -sSL $REPO_URL/install.sh | sudo bash

  # From cloned repository:
  sudo ./install.sh

  # Uninstall:
  sudo ./install.sh --uninstall

Installed Locations:
  $INSTALL_DIR/     Package files
  $BIN_DIR/         Executable symlinks
  $CONFIG_DIR/      Configuration
  $MAN_DIR/         Manual page
  $COMPLETION_DIR/  Bash completion

EOT
}

# Install OKnav
install_oknav() {
  echo "${BOLD}OKnav Installer v$VERSION${NC}"
  echo

  require_root "$@"

  info "Installing OKnav..."

  # Create directories with explicit permissions
  info "Creating directories..."
  install -d -m 755 "$INSTALL_DIR"       # Package directory (world-readable)
  install -d -m 750 "$CONFIG_DIR"        # Config directory (group-only, hides server names)
  mkdir -p "$MAN_DIR" "$COMPLETION_DIR"  # Usually pre-exist

  # Install executable scripts (755)
  info "Installing package files to $INSTALL_DIR..."
  for file in oknav ok_master; do
    get_source_file "$file" > "$TEMP_DIR/$file" || exit 1
    install -m 755 "$TEMP_DIR/$file" "$INSTALL_DIR/$file"
    success "Installed $file"
  done

  # Install library file (644 - sourced, not executed)
  get_source_file "common.inc.sh" > "$TEMP_DIR/common.inc.sh" || exit 1
  install -m 644 "$TEMP_DIR/common.inc.sh" "$INSTALL_DIR/common.inc.sh"
  success "Installed common.inc.sh"

  # Create VERSION file
  echo "$VERSION" > "$INSTALL_DIR/VERSION"

  # Create symlinks in /usr/local/bin
  info "Creating symlinks in $BIN_DIR..."
  for cmd in oknav ok_master; do
    ln -sf "$INSTALL_DIR/$cmd" "$BIN_DIR/$cmd"
    success "Linked $cmd"
  done

  # Install config if not exists
  # Priority: 1) existing /etc/oknav/hosts.conf (preserve)
  #           2) hosts.conf from source directory (local install)
  #           3) hosts.conf.example template
  if [[ ! -f "$CONFIG_DIR/hosts.conf" ]]; then
    if get_source_file "hosts.conf" > "$TEMP_DIR/hosts.conf" 2>/dev/null; then
      # Local install with hosts.conf in source directory
      info "Installing hosts.conf from source directory..."
      install -m 640 "$TEMP_DIR/hosts.conf" "$CONFIG_DIR/hosts.conf"
      success "Installed $CONFIG_DIR/hosts.conf from source"
    elif get_source_file "hosts.conf.example" > "$TEMP_DIR/hosts.conf" 2>/dev/null; then
      # Fall back to example template
      info "Installing config template..."
      install -m 640 "$TEMP_DIR/hosts.conf" "$CONFIG_DIR/hosts.conf"
      success "Created $CONFIG_DIR/hosts.conf (edit this file to add your servers)"
    else
      warn "No hosts.conf or hosts.conf.example found, skipping config"
    fi
  else
    info "Config already exists: $CONFIG_DIR/hosts.conf (preserved)"
    chmod 640 "$CONFIG_DIR/hosts.conf"  # Enforce permissions on existing file
  fi

  # Install manpage
  info "Installing manual page..."
  if get_source_file "oknav.1" > "$TEMP_DIR/oknav.1" 2>/dev/null; then
    install -m 644 "$TEMP_DIR/oknav.1" "$MAN_DIR/oknav.1"
    # Update man database
    if command -v mandb >/dev/null 2>&1; then
      mandb -q 2>/dev/null || true
    fi
    success "Installed manual page (try: man oknav)"
  else
    warn "oknav.1 not found, skipping manual page"
  fi

  # Install bash completion
  info "Installing bash completion..."
  if get_source_file "oknav.bash_completion" > "$TEMP_DIR/oknav" 2>/dev/null; then
    install -m 644 "$TEMP_DIR/oknav" "$COMPLETION_DIR/oknav"
    success "Installed bash completion"
  else
    warn "oknav.bash_completion not found, skipping completion"
  fi

  # Create alias symlinks using oknav install
  echo
  info "Creating server alias symlinks..."
  if [[ -f "$CONFIG_DIR/hosts.conf" ]]; then
    "$BIN_DIR/oknav" install 2>/dev/null || {
      warn "Could not create alias symlinks (edit $CONFIG_DIR/hosts.conf first)"
    }
  else
    warn "No hosts.conf found - run 'sudo oknav install' after configuring servers"
  fi

  echo
  success "${BOLD}Installation complete!${NC}"
  echo
  echo "Next steps:"
  echo "  1. Edit $CONFIG_DIR/hosts.conf to add your servers"
  echo "  2. Run 'sudo oknav install' to create alias symlinks"
  echo "  3. Test with: oknav -D hostname"
  echo
  echo "Documentation:"
  echo "  man oknav          # Read the manual"
  echo "  oknav --help       # Cluster operations help"
  echo "  srv1 --help        # Individual server help"
  echo
}

# Uninstall OKnav
uninstall_oknav() {
  echo "${BOLD}OKnav Uninstaller${NC}"
  echo

  require_root "$@"

  local -i removed=0

  info "Removing OKnav..."

  # Remove alias symlinks (those pointing to our ok_master)
  info "Removing alias symlinks from $BIN_DIR..."
  for link in "$BIN_DIR"/*; do
    [[ -L "$link" ]] || continue
    local target
    target=$(readlink "$link")
    if [[ "$target" == "$INSTALL_DIR/ok_master" ]]; then
      rm -f "$link"
      success "Removed ${link##*/}"
      ((++removed))
    fi
  done

  # Remove main symlinks
  for cmd in oknav ok_master; do
    if [[ -L "$BIN_DIR/$cmd" ]]; then
      rm -f "$BIN_DIR/$cmd"
      success "Removed $cmd symlink"
      ((++removed))
    fi
  done

  # Remove package directory
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    success "Removed $INSTALL_DIR"
    ((++removed))
  fi

  # Remove manpage
  if [[ -f "$MAN_DIR/oknav.1" ]]; then
    rm -f "$MAN_DIR/oknav.1"
    success "Removed manual page"
    ((++removed))
    # Update man database
    command -v mandb >/dev/null 2>&1 && mandb -q 2>/dev/null || true
  fi

  # Remove bash completion
  if [[ -f "$COMPLETION_DIR/oknav" ]]; then
    rm -f "$COMPLETION_DIR/oknav"
    success "Removed bash completion"
    ((++removed))
  fi

  # Prompt for config removal
  if [[ -d "$CONFIG_DIR" ]]; then
    echo
    warn "Configuration directory exists: $CONFIG_DIR"
    if [[ -t 0 ]]; then
      read -r -p "Remove configuration? [y/N] " reply
      if [[ "${reply,,}" == "y" ]]; then
        rm -rf "$CONFIG_DIR"
        success "Removed $CONFIG_DIR"
        ((++removed))
      else
        info "Preserved $CONFIG_DIR"
      fi
    else
      info "Non-interactive mode - preserving $CONFIG_DIR"
    fi
  fi

  echo
  if ((removed > 0)); then
    success "Uninstallation complete ($removed items removed)"
  else
    info "Nothing to uninstall"
  fi
}

# Main
main() {
  case "${1:-}" in
    --uninstall)
      uninstall_oknav "$@"
      ;;
    --help|-h)
      usage
      ;;
    *)
      install_oknav "$@"
      ;;
  esac
}

main "$@"

#fin
