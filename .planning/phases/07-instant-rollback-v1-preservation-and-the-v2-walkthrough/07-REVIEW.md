---
phase: 07-instant-rollback-v1-preservation-and-the-v2-walkthrough
reviewed: 2026-07-22T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - scripts/smoke.sh
  - WALKTHROUGH.md
  - Makefile
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Reviewed the three Phase 7 deliverables adversarially, with the primary lens on
false-passing assertions in the new test sections (these are TEST files — a test
that always passes is worse than none).

**The test assertions are sound.** I traced every new assertion in
`section_rollback`, `section_preserve`, and the updated `section_walkthrough`
against its failure mode and could not find a false-green:

- **VAL-04 checksum triple-equality** (`smoke.sh:2419-2420`) captures three
  *independent* `shasum -a 256` values at three real points (before cutover,
  after flip-to-new, after rollback-to-old), guards the first non-empty with
  `test -n`, and asserts `before==mid && mid==after`. A changed static config at
  any sample point makes it red. Not trivially satisfiable.
- **VAL-03 no-teardown** (`smoke.sh:2423-2429`) captures `StartedAt` and
  `pgrep -f 'nginx: worker'` PIDs at two distinct points, both `test -n`-guarded.
  A container recreate drops the stale ID from `docker inspect` output (line
  count changes → mismatch); a plain restart changes `StartedAt`; a reload
  respawns the workers (PIDs change). All three regressions are caught.
- **section_preserve** (`smoke.sh:2345-2364`) is non-destructive as required —
  only `git rev-parse`/`git show`/`git cat-file`. No `git checkout`/`switch`/
  `stash`/`reset`, no `compose.v1.yaml` added. Verified the `v1.0` tag exists and
  carries `proxy:` service, `proxy/nginx.conf`, `proxy/active-backend.conf`, and
  an `up:` target, so the assertions bind to real objects.
- **shasum portability**: `shasum -a 256` used in both `smoke.sh` (2398/2406/2413)
  and the `Makefile` `proxies-untouched` target (line 220). No `sha256sum`
  anywhere in the new code.
- **section_walkthrough lint** genuinely binds to the rewritten doc and was NOT
  weakened. I re-derived `WT_NARRATIVE` by hand against the 11 headings — it
  produces exactly the asserted `validate-new show-old redirect-contrast prime
  flip gotcha wrong-fix right-fix rollback proxies-untouched reset`. Non-vacuity
  guards, RES block order, prerequisite closure, and the "never executes what it
  extracts" guard (line 2037) are all intact. Every fenced `make` command maps to
  a real `.PHONY` target; every backtick path (`README.md`,
  `switch/active-proxy.conf`, `scripts/fix-hostkeys.sh`, `scripts/rearm.sh`)
  resolves.
- **Shell hygiene in section_rollback**: restore trap installed at entry and
  cleared at exit (leaves rig on OLD), no `ssh` on the left of a pipe (capture
  idiom used), correct `pgrep -f 'nginx: worker'`.

The defects are all in the **presenter-facing Expect blocks of `WALKTHROUGH.md`**
— content the executable lint structurally cannot check (only fenced ```bash
command blocks, paths, and structure are linted; ``` output blocks are not). MIG-02
was a v2 rewrite whose whole purpose was to purge stale v1 narrative, and one
Expect block survived the rewrite unchanged.

## Warnings

### WR-01: Beat 11 Expect block shows stale v1 container names that v2 never prints — ✅ FIXED

**Status:** FIXED — beat 11's Expect block now shows the real 7-service v2 `make status` table (client/proxy-new/proxy-old/server-new/server-old/status/switch + hosts line); walkthrough lint re-run green (26/0). Applied during the code-review gate.
**File:** `WALKTHROUGH.md:380-385`
**Issue:** Beat 11 ("Reset for the next take") runs `make reset`, which ends with
`make status`. Its Expect block shows:

```
demo-old     Up (healthy)
demo-new     Up (healthy)
demo-proxy   Up (healthy)
hosts: OK  app.demo.test -> 127.0.0.1
```

This is stale v1 single-proxy output. In v2 the demo has seven services
(`server-old`, `server-new`, `switch`, `proxy-old`, `proxy-new`, `status`,
`client`), and `make status` renders `{{.Service}}` — so it prints the *service
names*, never `demo-old`/`demo-new`/`demo-proxy` (confirmed: `compose.yaml` sets
no `container_name`, and even the v1.0 tag's `status` target used `{{.Service}}`,
so these three names were never real `make status` output). The presenter would
see three-plus extra rows with entirely different names than the script promises,
on the closing beat. The walkthrough lint cannot catch this because Expect blocks
are plain ``` fences, excluded from `$WT_TMP/cmds` extraction (`smoke.sh:1833`).

**Fix:** Replace the beat 11 Expect body with the actual v2 `make status` table,
e.g.:

```
SERVICE      STATUS              PORTS
server-old   Up (healthy)        ...
server-new   Up (healthy)        ...
switch       Up (healthy)        127.0.0.1:9092-9094->...
proxy-old    Up (healthy)        80/tcp
proxy-new    Up (healthy)        80/tcp
status       Up (healthy)        127.0.0.1:9094->...
client       Up                  ...
hosts: OK  app.demo.test -> 127.0.0.1
```

(`client` has no healthcheck — `compose.yaml:235` — so it shows `Up`, not
`Up (healthy)`.)

## Info

### IN-01: Beat 9 flip-old diff Expect omits the context lines diff -u actually emits

**File:** `WALKTHROUGH.md:328-333`
**Issue:** `flip.sh` renders the flip with `diff -u -L "$CONF (before)" -L
"$CONF (after)"` (`scripts/flip.sh:105`), i.e. a unified diff with three lines of
context. Beat 5 (flip-new) shows this correctly with all context lines
(`WALKTHROUGH.md:182-188`). Beat 9 (flip-old) shows a hunk header advertising
five lines (`@@ -1,5 +1,5 @@`) but then prints only the changed pair, dropping the
three comment/map context lines and the trailing `}`. The changed lines shown are
correct; the block is just internally inconsistent with the real output and with
beat 5. Low impact (presenter sees extra lines, not confusing), but it is the same
class of un-linted Expect drift as WR-01.
**Fix:** Show the full diff context, matching beat 5's rendering.

### IN-02: VAL-04 non-empty guard does not guarantee both config files are present

**File:** `scripts/smoke.sh:2419-2420`
**Issue:** `_sha_before=$(shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf
| awk '{print $1}')` writes a `No such file` error to stderr (unsuppressed) and
emits a hash only for the surviving file if one config were deleted. All three
captures would then be the single remaining hash, so `test -n` passes and the
triple-equality passes — the assertion would silently prove only *one* proxy
config unchanged while its label claims both. This is defense-in-depth only: a
missing static config would fail the rig's own healthchecks and the `MIG-01 six
services healthy` assertion long before this line, so the false-green is not
reachable in practice.
**Fix (optional):** Assert each file exists first, or count the hash lines, e.g.
`test "$(printf '%s\n' "$_sha_before" | grep -c .)" = "2"` before the equality.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
