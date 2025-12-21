# OKnav

SSH orchestration for multi-server environments. Connect to individual servers via symlinks or execute commands across your entire cluster.

**Version**: 2.3.0

## Overview

| Component | Purpose |
|-----------|---------|
| `ok_master` | Individual server SSH handler (invoked via symlinks) |
| `oknav` | Cluster orchestrator for multi-server commands |
| `common.inc.sh` | Shared configuration and hosts.conf parsing |

### How It Works

```
hosts.conf                      # Server definitions: FQDN → aliases
    │
    ├── ok_master ◄── srv1      # Symlink name determines target
    │       │         srv2      # srv1 → lookup hosts.conf → FQDN → SSH
    │       │         srv3
    │       ▼
    │   resolve_alias()         # Returns FQDN, checks constraints
    │
    └── oknav                   # Discovers (oknav) servers, executes on all
```

## Installation

### Quick Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/OkusiAssociates/oknav/main/install.sh | sudo bash
```

This installs OKnav to standard system locations:

| Location | Contents |
|----------|----------|
| `/usr/local/share/oknav/` | Package files (oknav, ok_master, common.inc.sh) |
| `/usr/local/bin/` | Executable symlinks |
| `/etc/oknav/hosts.conf` | Server configuration |
| `/usr/local/share/man/man1/oknav.1` | Manual page |
| `/etc/bash_completion.d/oknav` | Bash completion |

### From Source

```bash
git clone https://github.com/OkusiAssociates/oknav.git
cd oknav
sudo ./install.sh
```

### Uninstall

```bash
sudo /usr/local/share/oknav/install.sh --uninstall
# or from source:
sudo ./install.sh --uninstall
```

## Quick Start

### 1. Configure Servers

Edit `/etc/oknav/hosts.conf` to define your servers:

```
# Format: FQDN  primary-alias [alias2...]  [(options)]
server1.example.com   srv1 server1   (oknav)
server2.example.com   srv2 server2   (oknav)
server3.example.com   srv3 server3   (oknav)
```

### 2. Install Symlinks

```bash
sudo oknav install
```

This creates symlinks in `/usr/local/bin` for each alias in `hosts.conf`.

### 3. Use

```bash
# Individual server access
srv1 uptime              # SSH to server1
srv2 -r                  # Root shell on server2

# Cluster operations
oknav uptime             # Run on all (oknav) servers
oknav -p df -h           # Parallel execution
```

## Configuration: hosts.conf

Server mappings and cluster membership are defined in `hosts.conf`:

```
# Format: FQDN  primary-alias [alias2...]  [(options)]

# Production servers (included in cluster operations)
server1.example.com   srv1 server1   (oknav)
server2.example.com   srv2 server2   (oknav)
server3.example.com   srv3 server3   (oknav)

# Development server (only accessible from workstation)
devbox.local          dev devbox     (oknav,local-only:workstation)

# Backup server (excluded from normal operations)
backup.local          bak backup     (oknav,exclude)

# Ad-hoc server (direct access only, not in cluster)
adhoc.example.com     adhoc
```

### Options

| Option | Description |
|--------|-------------|
| `oknav` | Include in cluster operations (uses first/primary alias only) |
| `exclude` | Exclude from cluster operations (still accessible directly) |
| `local-only:HOSTNAME` | Restrict access to specified host machine |

### Key Concepts

- **First alias is canonical**: For servers with multiple aliases, only the first alias is used in cluster operations
- **Ad-hoc servers**: Entries without `(oknav)` can be accessed directly but won't appear in cluster operations
- **Combined options**: Use commas to combine options: `(oknav,local-only:myhost)`

## Individual Server Access

Each symlink provides SSH access with user switching and directory preservation.

```bash
srv1 [OPTIONS] [command]     # Execute command or start shell
```

| Option | Description |
|--------|-------------|
| `-r, --root` | Connect as root |
| `-u, --user USER` | Connect as specified user |
| `-d, --dir` | Preserve current directory |
| `-D, --debug` | Show connection parameters |

```bash
srv1                     # Interactive shell
srv1 uptime              # Execute command
srv1 -r                  # Root shell
srv1 -rd                 # Root shell in current directory
srv1 -u deploy git pull  # Run as specific user
srv1 "df -h | grep data" # Complex commands (use quotes)
```

## Cluster Operations

Execute commands across all servers marked with `(oknav)` in `hosts.conf`.

```bash
oknav [OPTIONS] <command>        # Execute on all servers
oknav install [OPTIONS]          # Manage symlinks from hosts.conf
oknav add <hostname> [alias...]  # Add ad-hoc launcher (sudo)
oknav remove <alias>...          # Remove launcher (sudo)
```

| Option | Description |
|--------|-------------|
| `-p, --parallel` | Execute simultaneously |
| `-t, --timeout SECS` | Connection timeout (default: 30) |
| `-x, --exclude-host HOST` | Exclude server (repeatable) |
| `-D, --debug` | Show discovery details |

```bash
oknav uptime             # Sequential (default)
oknav -p df -h           # Parallel execution
oknav -pt 10 uptime      # Parallel + 10s timeout
oknav -x srv1 uptime     # Exclude srv1
oknav -D hostname        # Debug: show discovered servers
```

### Install Subcommand

Create symlinks in `/usr/local/bin` for all `hosts.conf` aliases:

```bash
sudo oknav install              # Create/update symlinks
oknav install --dry-run         # Preview changes
sudo oknav install --remove-stale   # Remove stale symlinks
```

### Add/Remove Subcommands

Create ad-hoc launchers without editing `hosts.conf` (requires sudo):

```bash
oknav add <hostname> [alias...]   # Add launcher(s)
oknav remove <alias>...           # Remove launcher(s)
```

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes |
| `-h, --help` | Show subcommand help |

```bash
# Add launcher (hostname used as alias)
oknav add ai.okusi.id

# Add with custom aliases
oknav add ai.okusi.id ai ok-ai

# Remove launchers
oknav remove ai ok-ai
```

**Notes:**
- Hostname must be resolvable (DNS or `/etc/hosts`)
- Creates symlinks in `/usr/local/bin → ok_master`
- Ad-hoc hosts are **not** in cluster operations (use `hosts.conf` for that)
- Interactive prompt if symlink exists pointing elsewhere

## Output Format

### Individual Server Access

Direct output without prefixes:

```
$ srv1 uptime
 09:15:23 up 45 days,  3:22,  2 users,  load average: 0.15, 0.12, 0.10
```

### Cluster Operations

Prefixed output showing which server produced which output:

```
$ oknav uptime
+++srv1:
 09:15:23 up 45 days,  3:22,  2 users,  load average: 0.15, 0.12, 0.10

+++srv2:
 09:15:24 up 32 days, 14:55,  0 users,  load average: 0.08, 0.03, 0.01

+++srv3:
 09:15:24 up 91 days,  7:42,  1 user,  load average: 0.24, 0.18, 0.15
```

## Security Considerations

**Important**:

- Commands execute via sudo with SSH key authentication
- Parallel operations affect multiple servers simultaneously
- Local-only restrictions prevent access from unauthorized hosts

### Best Practices

1. **Test first**: Run commands on individual servers before cluster-wide execution
2. **Quote carefully**: Use quotes for commands with pipes, redirects, or special characters
3. **Review changes**: Use `-D` debug mode to verify server discovery
4. **Limit blast radius**: Use `-x` to exclude servers when testing
5. **Secure keys**: Protect SSH keys and rotate regularly

## Troubleshooting

### Common Issues

**"Command not found"**
- Ensure symlinks exist: `ls -la /usr/local/bin/srv*`
- Run `sudo oknav install` to create symlinks

**SSH connection failures**
- Verify SSH key authentication: `ssh user@server echo OK`
- Check hostname resolution
- Use `-D` for debug output

**Timeout errors**
- Default timeout is 30 seconds
- Use `-t SECS` for slow networks
- Check network connectivity to target server

**"No servers found"**
- Verify `hosts.conf` has entries with `(oknav)` option
- Check `(local-only:HOST)` restrictions match current hostname
- Use `oknav -D` to see server discovery

**local-only restrictions**
- Servers with `(local-only:HOST)` only work from that specific host
- Check current hostname: `hostname`

### Debug Commands

```bash
# Show discovered servers and settings
oknav -D hostname

# Verify individual server resolution
srv1 -D whoami

# Quick connectivity test with short timeout
oknav -t 5 echo OK
```

## Technical Details

| Item | Value |
|------|-------|
| Version | 2.3.0 |
| Shell | Bash 5.2+ |
| Dependencies | ssh, sudo, timeout, mktemp |
| Temp files | `$XDG_RUNTIME_DIR` or `/tmp` |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Local-only constraint violated (ok_master) |
| 22 | Invalid option (EINVAL) |
| 124 | Timeout reached |
| 125 | Timeout command error |
| 126 | Command not found |

### Installed File Structure

```
/usr/local/share/oknav/
├── oknav           # Cluster orchestrator
├── ok_master       # Individual server handler
├── common.inc.sh   # Shared configuration and functions
└── VERSION         # Version file

/etc/oknav/
└── hosts.conf      # Server configuration

/usr/local/bin/
├── oknav           # Symlink to oknav
├── ok_master       # Symlink to ok_master
└── srv1, srv2...   # Server alias symlinks
```

## License

GPL-3. See LICENSE file for details.

