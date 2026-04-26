# oknav — Main-Code Improvement Notes

Punch list of non-bug improvements identified during the test-coverage
extension on 2026-04-26. Nothing here is a regression or known fault — all
items are quality-of-life or testability wins. Triage at your own pace.

Severity: **HIGH** = pain point or blocks future work, **MED** = noticeable but
niche, **LOW** = polish.

---

## MED — Hardcoded `/usr/bin/ssh` in `ok_master`

**Where:** `ok_master:209`, `ok_master:214`, `ok_master:219`

**Issue:** Three `exec /usr/bin/ssh ...` calls bypass `$PATH`. Tests cannot
mock SSH for ok_master via the standard PATH-based mock pattern used
elsewhere — `tests/relay.bats` is reduced to asserting debug output rather
than the actual exec/failover behaviour.

**Suggested fix:** Use `command -v ssh` once at script load to resolve the
binary, then invoke via that variable. Preserves portability and makes the
relay-failover path mockable end-to-end.

---

## MED — Hardcoded `/etc/oknav/relay.conf` path in `ok_master`

**Where:** `ok_master:146`

**Issue:** `get_relay()` hardcodes the conf path. No env override (compare
`OKNAV_HOSTS_CONF` for hosts.conf). Tests that want to assert "no relay
configured" must skip when a real `/etc/oknav/relay.conf` exists on the
runner — see the `skip` in `tests/relay.bats:test 1`.

**Suggested fix:** Add `OKNAV_RELAY_CONF` env override (mirrors the existing
`OKNAV_HOSTS_CONF` pattern in `common.inc.sh:162`).

---

## MED — Duplicate `ok_master` path resolution

**Where:** `oknav:174-175`, `oknav:297-298`, `oknav:390-391`, `oknav:460-461`

**Issue:** The same two-line `/usr/local/share/oknav/ok_master` → `$SCRIPT_DIR`
fallback is repeated in `install_symlinks`, `add_host`, `remove_host`, and
`list_hosts`. DRY violation; one location to forget if the install layout
changes.

**Suggested fix:** Extract to `find_ok_master()` in `common.inc.sh`.

---

## MED — Parallel-mode missing-marker handling

**Where:** `oknav:805-815`

**Issue:** When the per-server marker file is missing in parallel mode, only
a `warn` is emitted ("Output file for X not found"). No retry, no fallback
display of the actual server output even if `temp_file` itself happens to
exist. The condition is also asymmetric — outer `[[ -f $temp_file_path ]]`
gates everything, so a missing marker silently swallows the server's output.

**Suggested fix:** Either retry once (the marker may be racing with the
subshell's final write) or emit the orphaned `temp_file` content if it can
be located by glob (`$TEMP_DIR/$SCRIPT_NAME_$server_*`).

---

## LOW — Redundant `${TEMP_DIR:-/tmp}` fallbacks

**Where:** `oknav:79`, `oknav:80`

**Issue:** `TEMP_DIR` is set as `readonly` in `common.inc.sh:64,66` — by the
time `cleanup()` runs, `TEMP_DIR` is guaranteed non-empty. The `:-/tmp`
default in the cleanup trap is dead defensive code.

**Suggested fix:** Drop the `:-/tmp`. Same applies to `${SCRIPT_NAME:-}`
guard on those two lines — `SCRIPT_NAME` is set unconditionally at line 43.

---

## LOW — `shift_verbose` set in `oknav` but not `ok_master`

**Where:** `oknav:38` has `shopt -s inherit_errexit shift_verbose extglob nullglob`;
`ok_master:33` has `shopt -s inherit_errexit extglob nullglob` (no
`shift_verbose`).

**Issue:** Asymmetry between two scripts that share `common.inc.sh`. Both
should opt in to verbose shift errors for consistency, especially since the
option-parsing loop in `ok_master` uses `shift` heavily.

**Suggested fix:** Add `shift_verbose` to `ok_master`'s `shopt` line.

---

## LOW — `OKNAV_TARGET_DIR` not validated

**Where:** `oknav:455`

**Issue:** `local -- target_dir=${OKNAV_TARGET_DIR:-/usr/local/bin}` accepts
any value including non-existent or non-directory paths. Silent empty result
if dir is missing — `find` swallows the error via `2>/dev/null` at line 516.

**Suggested fix:** `[[ -d $target_dir ]] || warn "OKNAV_TARGET_DIR ${target_dir@Q}: not a directory"; return 1`
near the top of `list_hosts`.

---

## LOW — Regex patterns redeclared per-call

**Where:** `common.inc.sh:182` (`options_re`), `common.inc.sh:240` and `:292`
(`local_only_re`).

**Issue:** Same `local_only_re` defined twice in two functions. Same
`options_re` declared inside `load_hosts_conf` per call. Minor — but
hoisting them to module-level `readonly` constants documents intent and
saves the per-call assignment.

**Suggested fix:** Define near the top of `common.inc.sh`:
```bash
readonly OPTIONS_RE='[(]([^)]+)[)][[:space:]]*$'
readonly LOCAL_ONLY_RE='local-only:([^,)]+)'
```

---

## LOW — Man page (`oknav.1`) drift audit not done

**Where:** `oknav.1`

**Issue:** Not cross-checked against current `oknav --help` and `ok_master --help`
output during this pass. Drift between `--help` and the man page is a
common slow leak.

**Suggested fix:** Diff `--help` output against the OPTIONS section of
`oknav.1` and reconcile. Consider a `make check-manpage` target that
compares them.

---

## LOW — `add_host` does not warn on subcommand-name collision

**Where:** `oknav:292-376`

**Issue:** `install_symlinks` warns when an alias collides with a subcommand
name (`oknav:213-223`); `add_host` does not. A user can `oknav add
host.example.com list` and silently shadow the `list` subcommand once the
symlink is created. Tests `tests/oknav.bats:install warns when alias matches
subcommand 'add'/'remove'/'list'` pin install's behaviour.

**Suggested fix:** Reuse the `reserved_names=(install add remove list help)`
check in `add_host`. Either warn-and-proceed (parity with install) or
warn-and-require-`-f`.

---

## LOW — Last-write-wins on duplicate alias is silent

**Where:** `common.inc.sh:218-222`

**Issue:** A `hosts.conf` with two entries naming the same alias for
different FQDNs silently picks the second. Pinned by
`tests/hosts_conf.bats:load_hosts_conf last-write-wins on duplicate alias`.

**Suggested fix:** Warn (don't error) when overwriting an existing
`ALIAS_TO_FQDN[alias]`. Single line:
```bash
[[ -z ${ALIAS_TO_FQDN[$alias]:-} ]] || warn "duplicate alias ${alias@Q}: overriding ${ALIAS_TO_FQDN[$alias]} with $fqdn"
```

---

## LOW — FQDN-only line silently dropped

**Where:** `common.inc.sh:212-213`

**Issue:** `read -r fqdn aliases <<< "$line"` followed by no aliases means
nothing is registered. Silent, no warning. Pinned by
`tests/hosts_conf.bats:load_hosts_conf silently skips line with FQDN but no alias`.

**Suggested fix:** `warn "hosts.conf: line ${lineno}: no alias for FQDN ${fqdn@Q} — skipping"` (requires tracking line number; cheap).

---

## MED — Flaky test: `parallel mode uses background processes`

**Where:** `tests/oknav.bats:405-413`

**Issue:** Intermittent failure in full-suite runs; passes 100% of the time
in isolation (`bats --filter "parallel mode uses background processes"`).
Suspect timing-dependent assertion on `+++ok0:` / `+++ok1:` headers when
the parallel subshells haven't flushed marker files before output collection.
Predates this work — observed on baseline before any changes were made.

**Suggested fix:** Either add a small wait/retry in the test (assert
`+++ok0:` with a retry loop) or fix the underlying race in `oknav:805-815`
(see "Parallel-mode missing-marker handling" above — the two are likely the
same root cause).

---

## Summary

13 items total. Suggested order: MED items first (testability wins on the
hardcoded SSH path and relay.conf pay back immediately), then LOW polish.
None are urgent.
#fin
