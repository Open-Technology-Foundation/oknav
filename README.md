# OKnav

A lightweight SSH orchestration system for managing commands across multiple servers. Provides both individual server access via symlink-based routing and coordinated cluster operations with parallel execution.

**Version**: 2.2.1

## Overview

OKnav consists of two components:

| Component | Purpose |
|-----------|---------|
| `ok_master` | Individual server SSH handler (invoked via symlinks) |
| `oknav` | Cluster orchestrator for multi-server commands |

### Architecture

```
hosts.conf          # Server configuration (FQDNs, aliases, options)
     |
     v
ok_master  <------- srv1, srv2, srv3 (symlinks)
     |                   |
     v                   v
resolve_alias()    SSH to target server
     |
     v
oknav              # Cluster operations on (oknav) servers
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

Each symlink (srv1, srv2, etc.) provides enhanced SSH access to its corresponding server.

### Usage

```bash
ALIAS [OPTIONS] [command]    # Execute command
ALIAS [OPTIONS]              # Interactive shell
```

### Options

| Option | Description |
|--------|-------------|
| `-r, --root` | Connect as root user |
| `-u, --user USER` | Connect as specified user |
| `-d, --dir` | Preserve current working directory |
| `-D, --debug` | Show connection parameters |
| `-V, --version` | Show version |
| `-h, --help` | Show help |

### Examples

```bash
# Basic access
srv1                     # Interactive shell
srv1 uptime              # Execute command
srv1 -r                  # Root shell

# User switching
srv1 -u admin whoami     # Connect as admin
srv2 -u deploy git pull  # Deploy as specific user

# Directory preservation
srv1 -d                  # Shell in current directory
srv1 -d ls -la           # List files in current dir on remote

# Combined options
srv1 -rd                 # Root shell in current directory
srv1 -Du admin pwd       # Debug with user switch

# Complex commands (use quotes)
srv1 "df -h | grep data"
srv1 'ps aux | grep nginx'
```

## Cluster Operations

The `oknav` orchestrator runs commands across all servers marked with `(oknav)` in `hosts.conf`.

### Usage

```bash
oknav [OPTIONS] <command>     # Execute on all servers
oknav install [OPTIONS]       # Manage symlinks
```

### Options

| Option | Description |
|--------|-------------|
| `-p, --parallel` | Execute in parallel across all servers |
| `-t, --timeout SECS` | Connection timeout (default: 30) |
| `-x, --exclude-host HOST` | Exclude server from this run (repeatable) |
| `-D, --debug` | Show discovery and execution details |
| `-V, --version` | Show version |
| `-h, --help` | Show help |

### Examples

```bash
# Sequential execution (default)
oknav uptime             # Check uptime on all servers
oknav df -h              # Check disk space
oknav systemctl status ssh  # Check service status

# Parallel execution
oknav -p uptime          # All servers simultaneously
oknav -p free -m         # Memory status in parallel

# With timeout
oknav -t 60 apt update   # 60-second timeout
oknav -pt 10 uptime      # Parallel with 10-second timeout

# Exclusions
oknav -x srv1 uptime     # Exclude srv1 from this run
oknav -x srv1 -x srv2 df # Exclude multiple servers

# Debug mode
oknav -D hostname        # Shows discovered servers
oknav -Dp echo test      # Debug with parallel execution

# Complex commands
oknav "mysql -e 'SHOW DATABASES;'"
oknav -p "ps aux | grep apache"
```

### Install Subcommand

Manage symlinks in `/usr/local/bin`:

```bash
oknav install [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes without making them |
| `--remove-stale` | Remove symlinks not in hosts.conf |
| `--clean-local` | Remove local symlinks from script directory |
| `-h, --help` | Show install help |

```bash
# Create/update symlinks
sudo oknav install

# Preview what would happen
oknav install --dry-run

# Full cleanup and reinstall
sudo oknav install --remove-stale --clean-local
```

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
| Version | 2.2.1 |
| Shell | Bash 5.2+ |
| Dependencies | ssh, sudo, timeout, mktemp |
| Temp files | `$XDG_RUNTIME_DIR` or `/tmp` |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 22 | Invalid option |
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

