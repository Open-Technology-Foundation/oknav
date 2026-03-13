# OKnav

Lightweight SSH orchestration for multi-server environments.

## Features

- **Individual server access** via named symlinks (`srv1`, `dev`, `backup`)
- **Cluster-wide commands** with sequential or parallel execution
- **Configuration-driven** server management via `hosts.conf`
- **Host connectivity testing** with reachability checks
- **Ad-hoc launchers** without config file editing
- **Local-only restrictions** for host-specific access control
- **Relay failover** on SSH connection failure via ProxyCommand (nc)

## Quick Start

```bash
# 1. Install
curl -sSL https://raw.githubusercontent.com/OkusiAssociates/oknav/main/install.sh | sudo bash

# 2. Configure servers
sudo nano /etc/oknav/hosts.conf
# server1.example.com   srv1   (oknav)
# server2.example.com   srv2   (oknav)

# 3. Create symlinks
sudo oknav install

# 4. Use
srv1 uptime              # Individual server
oknav uptime             # All cluster servers
oknav -p df -h           # Parallel execution
```

## Installation

### Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/OkusiAssociates/oknav/main/install.sh | sudo bash
```

Installs to:

| Location | Contents |
|----------|----------|
| `/usr/local/share/oknav/` | Package files |
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
```

## Configuration

Server definitions live in `/etc/oknav/hosts.conf`:

```
# Format: FQDN  primary-alias [alias2...]  [(options)]

# Production cluster
server1.example.com   srv1 server1   (oknav)
server2.example.com   srv2 server2   (oknav)
server3.example.com   srv3 server3   (oknav)

# Development (restricted to workstation)
devbox.local          dev devbox     (oknav,local-only:workstation)

# Backup (excluded from normal cluster operations)
backup.local          bak backup     (oknav,exclude)

# Direct access only (not in cluster)
adhoc.example.com     adhoc
```

### Configuration Options

| Option | Description |
|--------|-------------|
| `oknav` | Include in cluster operations (primary alias only) |
| `exclude` | Exclude from cluster operations (still accessible directly) |
| `local-only:HOST` | Restrict access to specified hostname |

### Key Concepts

- **Primary alias**: First alias listed is used for cluster operations
- **Combined options**: Separate with commas: `(oknav,local-only:myhost)`
- **Ad-hoc entries**: Servers without `(oknav)` are accessible but not in cluster
- **Config priority**: `/etc/oknav/hosts.conf` > `$SCRIPT_DIR/hosts.conf`

## Usage

### Individual Server Access

Connect to servers via symlinks that resolve through `hosts.conf`:

```bash
srv1 [OPTIONS] [command]
```

| Option | Description |
|--------|-------------|
| `-r, --root` | Connect as root |
| `-u, --user USER` | Connect as specified user |
| `-c, --connect-timeout S` | SSH connect timeout (default: 10) |
| `-d, --dir` | Preserve current working directory |
| `-R, --relay HOST` | Override relay host for this invocation |
| `--no-relay` | Disable relay failover for this invocation |
| `-D, --debug` | Show connection parameters |
| `-V, --version` | Show version |
| `-h, --help` | Show help |

**Examples**:

```bash
srv1                         # Interactive shell
srv1 uptime                  # Execute command
srv1 -r                      # Root shell
srv1 -rd                     # Root shell, current directory
srv1 -u deploy git pull      # Run as specific user
srv1 "df -h | grep data"     # Complex commands (quote them)
srv1 --relay relay-host uptime   # Force relay through specific host
srv1 --no-relay uptime           # Disable relay failover
```

### Relay Failover

When an SSH connection fails (exit code 255), ok_master can automatically retry through a relay host using ProxyCommand (nc). This is opt-in and machine-specific.

**Resolution priority** (highest first):

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | `--no-relay` flag | Disable relay for this invocation |
| 2 | `--relay HOST` / `-R HOST` flag | Override relay for this invocation |
| 3 | `OKNAV_RELAY` env var | Override relay (set to `none` to disable) |
| 4 | `/etc/oknav/relay.conf` | Persistent machine-specific default |
| 5 | No relay configured | Direct connection only (original behavior) |

**relay.conf format**: A single line containing an SSH config Host name or `user@host:port`.

**Behavior**: When no relay is configured, ok_master uses `exec ssh` with zero overhead (original behavior). When a relay is configured, it tries a direct connection first and only relays on exit code 255. Other exit codes pass through unchanged. The relay info message is suppressed in quiet/cluster mode.

**Examples**:

```bash
srv1 --relay jump-host uptime    # Force relay through specific host
srv1 --no-relay uptime           # Disable relay for this invocation
OKNAV_RELAY=none srv1 uptime     # Disable relay via env
srv1 -D uptime                   # Debug output shows relay status
```

### Cluster Operations

Execute commands across all servers marked with `(oknav)`:

```bash
oknav [OPTIONS] <command>
oknav [OPTIONS] -- <command>    # Force command mode
```

| Option | Description |
|--------|-------------|
| `-p, --parallel` | Execute simultaneously |
| `-d, --dir` | Preserve current working directory |
| `-c, --connect-timeout S` | SSH connect timeout (default: 10) |
| `-t, --timeout SECS` | Execution timeout (default: 120) |
| `-x, --exclude-host HOST` | Exclude server (repeatable) |
| `-D, --debug` | Show server discovery details |
| `--` | Force command mode (bypass subcommand detection) |
| `-V, --version` | Show version |
| `-h, --help` | Show help |

**Examples**:

```bash
oknav uptime                 # Sequential execution
oknav -p df -h               # Parallel execution
oknav -d ls                  # Run in current directory
oknav -pd pwd                # Parallel, preserve directory
oknav -pt 10 uptime          # Parallel + 10s timeout
oknav -x srv1 -x srv2 uptime # Exclude multiple servers
oknav -D hostname            # Debug: show discovered servers
oknav -- list /tmp           # Run 'list /tmp' (not subcommand)
```

### Subcommands

| Subcommand | Purpose |
|------------|---------|
| `install` | Manage symlinks from hosts.conf |
| `add` | Create ad-hoc launcher |
| `remove` | Remove launcher |
| `list` | List installed host symlinks |
| `help` | Show usage help |

#### install

Create symlinks in `/usr/local/bin` for all `hosts.conf` aliases:

```bash
sudo oknav install                  # Create/update symlinks
oknav install --dry-run             # Preview changes
sudo oknav install --remove-stale   # Remove ok*-prefixed symlinks not in hosts.conf
sudo oknav install --clean-local    # Remove ok*-prefixed dev symlinks from script dir
```

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes |
| `--remove-stale` | Remove ok*-prefixed symlinks not in hosts.conf |
| `--clean-local` | Remove ok*-prefixed symlinks from script directory |
| `-h, --help` | Show help |

**Note**: Aliases that conflict with subcommand names (`install`, `add`, `remove`, `list`, `help`) trigger a warning during `oknav install`. Use `oknav -- <alias> <cmd>` to execute commands on such servers.

#### add / remove

Create ad-hoc launchers without editing `hosts.conf`:

```bash
# Add launcher (hostname used as alias)
sudo oknav add ai.okusi.id

# Add with custom aliases
sudo oknav add ai.okusi.id ai ok-ai

# Remove launchers
sudo oknav remove ai ok-ai
```

| Option | Description |
|--------|-------------|
| `-n, --dry-run` | Preview changes |
| `-h, --help` | Show help |

**Notes**:
- Hostname must be resolvable (DNS or `/etc/hosts`)
- Ad-hoc hosts are NOT included in cluster operations
- Use `hosts.conf` for cluster membership

#### list

Show all host symlinks in `/usr/local/bin` pointing to `ok_master`:

```bash
oknav list                   # List all hosts
oknav list -R                # Test SSH connectivity
oknav list -R -p             # Parallel connectivity testing
```

| Option | Description |
|--------|-------------|
| `-R, --reachable` | Test SSH connectivity (3s connect, 10s total per host) |
| `-p, --parallel` | Test hosts in parallel (use with -R) |
| `-h, --help` | Show help |

**Output format**:

```
srv1         hosts.conf
srv2         hosts.conf
ai           ad-hoc
```

**With `-R` (reachability testing)**:

```
srv1         hosts.conf  ✓
srv2         hosts.conf  ✓
ai           ad-hoc      ✗
```

## Output Format

### Individual Server

Direct output without prefixes:

```
$ srv1 uptime
 09:15:23 up 45 days,  3:22,  2 users,  load average: 0.15, 0.12, 0.10
```

### Cluster Operations

Prefixed output showing server origin:

```
$ oknav uptime
+++srv1:
 09:15:23 up 45 days,  3:22,  2 users,  load average: 0.15, 0.12, 0.10

+++srv2:
 09:15:24 up 32 days, 14:55,  0 users,  load average: 0.08, 0.03, 0.01
```

In parallel mode (`-p`), output is collected and displayed in server order after all complete.

## Development

### Linting

```bash
shellcheck -x oknav ok_master common.inc.sh install.sh
```

### Testing

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/oknav.bats

# Filter by test name
bats tests/oknav.bats --filter "parallel"
```

### Syntax Validation

```bash
bash -n oknav && bash -n ok_master && bash -n common.inc.sh
```

## Reference

### Options Summary

| Tool | Option | Description |
|------|--------|-------------|
| `ok_master` | `-r` | Root user |
| `ok_master` | `-u USER` | Specific user |
| `ok_master` | `-c SECS` | SSH connect timeout (default: 10) |
| `ok_master` | `-d` | Preserve directory |
| `ok_master` | `-R HOST` | Override relay host |
| `ok_master` | `--no-relay` | Disable relay failover |
| `ok_master` | `-D` | Debug mode |
| `ok_master` | `-V` | Show version |
| `ok_master` | `-h` | Show help |
| `oknav` | `-p` | Parallel execution |
| `oknav` | `-d` | Preserve directory |
| `oknav` | `-c SECS` | SSH connect timeout (default: 10) |
| `oknav` | `-t SECS` | Execution timeout (default: 120) |
| `oknav` | `-x HOST` | Exclude host (repeatable) |
| `oknav` | `-D` | Debug mode |
| `oknav` | `--` | Force command mode |
| `oknav` | `-V` | Show version |
| `oknav` | `-h` | Show help |
| `install` | `-n` | Dry run |
| `install` | `--remove-stale` | Remove stale ok* symlinks |
| `install` | `--clean-local` | Remove local ok* symlinks |
| `add` | `-n` | Dry run |
| `remove` | `-n` | Dry run |
| `list` | `-R` | Test reachability |
| `list` | `-p` | Parallel testing |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Local-only constraint violated |
| 22 | Invalid option (EINVAL) |
| 42 | Direct ok_master execution (must use symlink) |
| 124 | Timeout reached |
| 125 | Timeout command error |
| 126 | Command not found |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OKNAV_CONNECT_TIMEOUT` | Override default SSH connect timeout (default: 10) |
| `OKNAV_HOSTS_CONF` | Override hosts.conf location |
| `OKNAV_RELAY` | Override relay host for ok_master (set to `none` to disable) |
| `OKNAV_TARGET_DIR` | Override target directory (for testing) |
| `XDG_RUNTIME_DIR` | Temp file location (falls back to `/tmp`) |

### File Structure

**Installed**:

```
/usr/local/share/oknav/
├── oknav              # Cluster orchestrator
├── ok_master          # Individual server handler
├── common.inc.sh      # Shared functions
└── install.sh         # Installer

/etc/oknav/
├── hosts.conf         # Server configuration
└── relay.conf         # Relay failover host (optional)

/usr/local/bin/
├── oknav              # → /usr/local/share/oknav/oknav
├── ok_master          # → /usr/local/share/oknav/ok_master
└── srv1, srv2...      # → /usr/local/share/oknav/ok_master
```

**Source**:

```
oknav/
├── oknav              # Cluster orchestrator
├── ok_master          # Individual server handler
├── common.inc.sh      # Shared functions
├── install.sh         # Installer
├── hosts.conf.example # Configuration template
├── oknav.1            # Man page
├── oknav.bash_completion
└── tests/             # BATS test suite
```

## Security

### Important

- Commands execute via sudo with SSH key authentication
- Parallel operations affect multiple servers simultaneously
- Local-only restrictions prevent access from unauthorized hosts

### Best Practices

1. **Test first**: Run commands on individual servers before cluster-wide
2. **Quote carefully**: Use quotes for commands with pipes or special characters
3. **Review changes**: Use `-D` debug mode to verify server discovery
4. **Limit blast radius**: Use `-x` to exclude servers when testing
5. **Secure keys**: Protect SSH keys and rotate regularly
6. **Restrict access**: Use `local-only:HOST` for sensitive servers

## Troubleshooting

### Common Issues

**"Command not found"**
- Ensure symlinks exist: `ls -la /usr/local/bin/srv*`
- Run `sudo oknav install` to create symlinks

**SSH connection failures**
- Verify SSH key authentication: `ssh user@server echo OK`
- Check hostname resolution: `getent hosts server1.example.com`
- Use `-D` for debug output (shows relay status)
- Try `--no-relay` to test direct connection if relay is configured

**Timeout errors**
- Connect timeout (`-c`): controls SSH handshake (default: 10s)
- Execution timeout (`-t`): controls total time (default: 120s)
- Use `-c SECS` for unreachable hosts to fail fast
- Use `-t SECS` for long-running commands

**"No servers found"**
- Verify `hosts.conf` has entries with `(oknav)` option
- Check `(local-only:HOST)` restrictions match current hostname
- Use `oknav -D` to see server discovery

**Local-only restrictions**
- Servers with `(local-only:HOST)` only work from that specific host
- Check current hostname: `hostname`

### Debug Commands

```bash
# Show discovered servers and settings
oknav -D hostname

# Verify individual server resolution
srv1 -D whoami

# Test connectivity with short timeout
oknav -t 5 echo OK

# List hosts with reachability check
oknav list -R
```

## License

GPL-3. See LICENSE file for details.
