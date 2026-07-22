---
phase: 06-the-ssh-stream-flip-and-pre-flip-validation
verified: 2026-07-22T00:00:00Z
status: passed
score: 10/10 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
---

# Phase 6: The SSH Stream Flip and Pre-Flip Validation — Verification Report

**Phase Goal:** Extend the switch's single one-line selector to govern the SSH:22 stream path as well as HTTP:9092 (one edit flips both protocols), then deliver pre-flip validation — the presenter can `curl`/`ssh app-new.demo.test` to prove the new stack live BEFORE any cutover (while `app.demo.test` still lands on OLD), with verify.sh re-pointed at the switch and able to target app-new directly.
**Verified:** 2026-07-22
**Status:** PHASE VERIFIED
**Re-verification:** No — initial verification
**Evidence basis:** Live rig (`make reset` clean baseline, `docker 29.5.3`) + source inspection. One clean green run treated as authoritative.

## Goal Achievement — 3 ROADMAP Success Criteria

### Criterion 1 — One edit flips BOTH protocols (SW-03, finalizes SW-01): PASS

| Check | Evidence | Status |
|---|---|---|
| Stream block present on switch | `switch/nginx.conf:192-290` — full `stream {}` re-homed from v1 | VERIFIED |
| `demo/active-proxy.conf` included in BOTH http + stream | `grep -c` (comments stripped) = **2** (http `:78`, stream `:249`) | VERIFIED |
| Stream upstreams target static proxies :22 | `upstream old { server proxy-old:22; }` / `proxy-new:22` (`:239-240`) | VERIFIED |
| `listen 22; proxy_pass $active_backend;` | `switch/nginx.conf:286-289` | VERIFIED |
| Live: on OLD → `curl 9092` = `OLD server-old`; `verify old` exit 0 (HTTP+SSH OLD) | live run | VERIFIED |
| Live: `flip.sh new` → `curl 9092` = `NEW server-new` AND `verify new` exit 0 (HTTP+SSH NEW) | live run — one edit flipped both | VERIFIED |
| Live: `flip.sh old` → back to `OLD server-old` | live run | VERIFIED |
| flip.sh / compose.yaml unchanged | not in phase-6 file set; flip mechanism reused | VERIFIED |

The single `active-proxy.conf` selector edit (via `flip.sh`) cut over HTTP:9092 and SSH:22 together, live, in both directions. SW-01's SSH half is finalized — the switch is the sole client endpoint on both protocols.

### Criterion 2 — Pre-flip validation over BOTH protocols while app.demo.test stays OLD (VAL-01, VAL-02): PASS

| Check | Evidence | Status |
|---|---|---|
| `curl app-new.demo.test/whoami` → `NEW server-new` (client container, :80) | `make verify-new-stack` live: `HTTP ... -> NEW server-new` | VERIFIED |
| `ssh app-new.demo.test` → server-new banner (client container, :22) | live: `SSH ... -> NEW server-new [remote hostname: server-new]` | VERIFIED |
| Concurrently `curl localhost:9092` → OLD while switch on OLD | `section_validate` VAL-01 asserts app-new=NEW AND switch=OLD atomically | VERIFIED |
| section_validate non-destructive (never flips) | `awk` region: 0 `flip.sh new|toggle`; asserts OLD as precondition, no restore trap | VERIFIED |
| Full section green | `make test` `--- validate ---` 5 PASS (VAL-01, VAL-02 banner+hostname+concurrent, EV2-04) | VERIFIED |

### Criterion 3 — verify.sh through-switch + app-new mode with exit vocabulary intact (EV2-04): PASS

| Check | Evidence (verify.sh invoked directly) | Status |
|---|---|---|
| `verify old` (on OLD) | exit **0** | VERIFIED |
| `verify new` (on OLD) | exit **1** (mismatch) | VERIFIED |
| no args / `--target bogus` | exit **2** (usage) | VERIFIED |
| protocol disagreement (HTTP=OLD switch, SSH=NEW app-new via `VERIFY_SSH_HOST` seam) | exit **3**, `PROTOCOLS DISAGREE` | VERIFIED |
| `--target app-new` pre-flip | exit **0**, NEW on both HTTP + SSH lines while switch on OLD | VERIFIED |
| positional `<old|new>` mode preserved | unchanged; 0/1/2/3 vocabulary all reachable | VERIFIED |
| WR-01 fix (diagnostic path) | `verify.sh:225` prints `switch/active-proxy.conf` — confirmed **live** in exit-3 output and in source | VERIFIED |

> Note: `make verify EXPECT=old` on a NEW rig returned shell exit 2 — that is GNU make's own recipe-failure code wrapping the script. The script itself exits 1 (its `MISMATCH expected OLD` branch printed). Verified by invoking `sh scripts/verify.sh` directly, which yields the true 0/1/2/3 vocabulary above.

## Observable Truths (10 plan must_haves)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | `ssh app.demo.test:22` lands on active backend via switch→proxy→server; stream includes same active-proxy.conf as http | VERIFIED | include count=2; live ssh OLD/NEW through switch |
| 2 | One active-proxy.conf edit + one reload flips both HTTP:9092 and SSH:22; flip.sh unchanged (finalizes SW-01 SSH half) | VERIFIED | live flip new→both NEW, old→both OLD |
| 3 | Stream upstreams target proxy-old:22/proxy-new:22; `listen 22; proxy_pass $active_backend;` | VERIFIED | `switch/nginx.conf:239-240,286-289` |
| 4 | section_ssh + section_hostkey reconciled onto switch and re-enabled in `all`; make test green | VERIFIED | 0 residual v1 refs; both in runner; 247/0 |
| 5 | In-flight SSH reports OLD after reload while fresh reports NEW; no worker_shutdown_timeout (D-40) | VERIFIED | 2 D-40 beats PASS in log; grep count=0 |
| 6 | Pre-flip `curl app-new` → NEW while `curl localhost:9092` → OLD (VAL-01) | VERIFIED | section_validate + verify-new-stack live |
| 7 | Pre-flip `ssh app-new` → server-new while `ssh app.demo.test` → OLD (VAL-02) | VERIFIED | banner+hostname corroboration beats PASS |
| 8 | `verify.sh --target app-new` asserts NEW over both protocols from client container, exit 0 pre-flip (EV2-04) | VERIFIED | live exit 0 |
| 9 | verify.sh through-switch asserts both protocols, non-zero on mismatch, exit 3 on protocol disagreement; vocabulary unchanged | VERIFIED | live 0/1/2/3 |
| 10 | make test green incl. section_validate and re-enabled section_ssh/section_hostkey | VERIFIED | 247 passed, 0 failed, exit 0 |

**Score:** 10/10 truths verified (0 present-behavior-unverified). D-40 behavior-dependent invariant confirmed by passing test beats, not presence alone.

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| SW-03 | 06-01 | Same selector governs HTTP:9092 and SSH:22 — one edit flips both | SATISFIED | Criterion 1 live |
| SW-01 (finalized) | 06-01 | Switch is client's only endpoint on HTTP 9092 AND SSH 22 | SATISFIED | Now fully Complete — SSH:22 listener live; REQUIREMENTS.md row reconciled |
| VAL-01 | 06-02 | Reach app-new over HTTP → server-new pre-flip while app.demo.test → OLD | SATISFIED | Criterion 2 live |
| VAL-02 | 06-02 | `ssh app-new.demo.test` → server-new banner pre-flip | SATISFIED | Criterion 2 live |
| EV2-04 | 06-02 | verify asserts both protocols through switch, can target app-new directly | SATISFIED | Criterion 3 live |

No orphaned requirements: REQUIREMENTS.md maps exactly SW-03/VAL-01/VAL-02/EV2-04 (+ SW-01 reconciliation) to Phase 6, all claimed by plans and all marked Complete.

## Security / Scope-Fence Controls

| Control | Check | Status |
|---|---|---|
| **D-46** stream access_log = /dev/stdout ONLY (block-on-high) | stream region: exactly **1** access_log, targets `/dev/stdout`, **0** `var/log` paths | PASS |
| **D-15** no host :22 publish | `compose.yaml` publishes only loopback 9090/9091/9092/9093/9094; no `:22` mapping; live `docker compose ps` shows proxies expose only 80/tcp internally, switch only 9092-9093 | PASS |
| **D-40** no worker_shutdown_timeout | `grep -c` = 0; in-flight-OLD/fresh-NEW beats PASS | PASS |
| No stream `$backend_is_valid` analogue | deliberate omission documented `switch/nginx.conf:274-281`; bad selector → status=500 | PASS (intentional) |
| section_ssh/section_hostkey not gutted | 66 ssh + 20 hostkey PASS beats; 9 SSH-02 asserts grep live `switch/nginx.conf`; 0 residual v1 refs | PASS |
| section_validate non-destructive | 0 `flip.sh new|toggle`; no restore trap; reads only | PASS |
| No ssh on left of a pipe | verify.sh count=0; capture-then-read-`$?` idiom preserved | PASS |
| v1 preservation (Phase 7 scope) | `proxy/nginx.conf` + `proxy/active-backend.conf` present on disk, last touched commit 3b7dc6c (Phase 3) — untouched by Phase 6 | PASS |
| Direct-to-backend BACK-04/05 group unchanged | 5 `demo@server-old|demo@server-new` refs intact (≥2) | PASS |

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Full suite | `make test` (post `make reset`) | 247 passed, 0 failed, exit 0 | PASS |
| One-edit-both-protocols flip | flip.sh new/old + verify | HTTP+SSH flip together, both directions | PASS |
| Pre-flip proof | `make verify-new-stack` | exit 0, NEW on HTTP+SSH while switch OLD | PASS |
| verify.sh exit vocabulary | direct invocations | 0/1/2/3 all reachable | PASS |

## Code Review (WR-01) Confirmation

06-REVIEW.md flagged WR-01 (stale `proxy/active-backend.conf` in verify.sh's exit-3 diagnostic) as FIXED. Confirmed real: `scripts/verify.sh:225` reads `switch/active-proxy.conf`, and the corrected string printed in the **live** exit-3 run. 0 Critical findings; IN-01 (triplicated SSH option strings) is a documented, non-blocking maintenance note.

## Anti-Patterns Found

None. No TBD/FIXME/XXX debt markers in changed files. No stubs — config + POSIX-sh only. Deviations documented in both SUMMARYs were runtime rig-state artifacts (Docker Desktop macOS bind-mount desync / shared-rig drift), resolved by container recreate / `make reset`; no code defect, no scope change.

## Gaps Summary

None. All 3 ROADMAP success criteria pass with live evidence, all 5 requirement IDs (incl. SW-01 now fully Complete) satisfied, all prohibitions upheld, all high-severity controls (D-46 block-on-high, D-15) green. `make test` 247/0 on a clean-reset rig.

---

_Verified: 2026-07-22_
_Verifier: Claude (gsd-verifier)_
