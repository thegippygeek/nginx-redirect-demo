---
phase: 06-the-ssh-stream-flip-and-pre-flip-validation
reviewed: 2026-07-22T03:56:25Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - switch/nginx.conf
  - scripts/verify.sh
  - scripts/smoke.sh
  - Makefile
findings:
  critical: 0
  warning: 1
  info: 1
  total: 2
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-07-22T03:56:25Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Reviewed the four source files changed in Phase 6: the added SSH:22 `stream {}` block on
`switch/nginx.conf`, the `--target app-new` mode in `scripts/verify.sh`, the reconciled +
re-enabled `section_ssh`/`section_hostkey` and new `section_validate` in `scripts/smoke.sh`,
and the `verify-new-stack` Makefile target.

The high-priority security controls all hold:

- **D-46 evidence-sink separation (block-on-high): PASS.** The switch stream block declares
  exactly one `access_log`, to `/dev/stdout demo_stream` (`switch/nginx.conf:230`), and names
  no `/var/log` path anywhere in the stream region. No SSH line can reach the JSON evidence
  sink the status parser reads.
- **Shared-selector correctness (SW-03): PASS.** `include /etc/nginx/demo/active-proxy.conf`
  appears in both the http block (`:78`) and the stream block (`:249`); the stream upstreams
  target `proxy-old:22`/`proxy-new:22` (`:239-240`), routing through the static-proxy tier
  rather than the backends. A `diff` of the two stream blocks confirms the switch's is a
  faithful re-home of v1's `proxy/nginx.conf` block — the only deltas are the three documented
  string changes plus comment reconciliations and an added D-40 note. No functional directive
  (`log_format demo_stream`, the stdout `access_log`, `map $active_backend $stream_label`,
  `listen 22`, `proxy_pass $active_backend`) was dropped.
- **No host :22 exposure (D-15): PASS.** `compose.yaml` publishes only `9092`/`9093` on
  loopback for the switch and nothing for the proxies; there is no `ports:` entry mapping any
  container :22, and the stream `listen 22;` is not host-mapped.
- **smoke.sh reconciliation integrity: PASS.** Every stale v1 `proxy`/`active-backend`/
  `/active-backend` reference in `section_ssh`, `section_hostkey`, and the shared
  `selector_now`/`restore_ssh_state`/`finish_ssh_state` helpers is re-pointed onto the switch
  (verified by grep — zero residual). Assertions remain meaningful, not weakened to force
  green; `section_validate` is genuinely non-destructive (asserts OLD as a precondition, never
  flips, installs no restore trap); both SSH sections are re-enabled in the `all` runner with
  the deferral markers removed.
- **Shell hygiene: PASS.** No `ssh` invocation sits on the left of a pipe; capture-then-read-`$?`
  idiom preserved; ssh/curl calls carry `timeout`/`--max-time`; the intentional `HTTP_EXEC`/
  `VERIFY_SSH_OPTS` word-splits expand only fixed literals (no injection surface); the positional
  `<old|new>` mode and 0/1/2/3 exit vocabulary survive the new `--target` parse.

One genuine defect remains: a stale v1 file path in `verify.sh`'s protocol-disagreement
diagnostic — output the presenter reads precisely when debugging the exit-3 failure on stage.

## Warnings

### WR-01: Stale v1 file path in verify.sh's protocol-disagreement diagnostic — ✅ FIXED

**Status:** FIXED — `scripts/verify.sh:225` now prints `switch/active-proxy.conf` (orchestrator applied the one-line fix during the code-review gate).
**File:** `scripts/verify.sh:225`
**Issue:** When the two protocols disagree (the exit-3 branch), the script prints:

```
One word in proxy/active-backend.conf drives both. If they differ, they are not reading the same word:
```

`proxy/active-backend.conf` is the archived v1 path. In the current topology the single word
that drives both protocols lives in `switch/active-proxy.conf`, and `proxy/active-backend.conf`
is inert v1 config that the running switch does not even read. This is exactly the class of
stale reference the Phase-6 reconciliation (RESEARCH Pitfall 4) was chartered to eliminate in
`smoke.sh` — the same string survived here in `verify.sh`. Because this line prints only on the
exit-3 "HTTP flipped, SSH didn't" case, it fires at the worst possible moment: a presenter
debugging a live protocol split is directed to a file that is both wrong and misleading. The
exit code and control flow are correct; only the diagnostic text misdirects. (The very next
line, `:226`, gives the correct advice about the stream/http shared include, which makes the
stale path on `:225` stand out more, not less.)
**Fix:**
```sh
	echo "  One word in switch/active-proxy.conf drives both. If they differ, they are not reading the same word:"
```

## Info

### IN-01: Two duplicated demo-only SSH option strings drift-risk

**File:** `scripts/smoke.sh:1155`, `scripts/smoke.sh:1250` (and `scripts/verify.sh:79`)
**Issue:** The demo-only host-key option set
(`-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`)
is restated verbatim in `section_validate` (`SSH_OPTS`, `:1155`), `section_ssh` (`SSH_OPTS`,
`:1250`), and `verify.sh` (`VERIFY_SSH_OPTS`, `:79`). The duplication is deliberate and
documented (each must run standalone because `assert` reaches its condition through a fresh
`sh -c` that inherits exported variables but not functions), so this is not a correctness
defect — but it is a maintenance hazard: a future edit to the option set (e.g. adding a real
`ConnectTimeout` bump) must be applied in three places or the modes silently diverge. The
`KEY-02 guard` at `smoke.sh:2326-2329` only pins the presence of `UserKnownHostsFile=/dev/null`
in `section_ssh` and `verify.sh`, not that all three strings stay identical. No action required
for this phase; noting for future consolidation if these strings grow.
**Fix:** Optional — if these are ever changed, update all three occurrences together, or add a
guard asserting the three option strings are byte-identical.

---

_Reviewed: 2026-07-22T03:56:25Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
