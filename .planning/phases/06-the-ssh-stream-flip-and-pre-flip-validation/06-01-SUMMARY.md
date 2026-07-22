---
phase: 06-the-ssh-stream-flip-and-pre-flip-validation
plan: 01
subsystem: infra
tags: [nginx, stream, ssh, docker-compose, l4-proxy, smoke-tests, posix-sh]

# Dependency graph
requires:
  - phase: 05
    provides: "switch service with http block, shared active-proxy.conf selector, /active-proxy oracle, static proxy-old/proxy-new with inert :22 streams"
provides:
  - "switch/nginx.conf stream block: switch listens on :22 and relays SSH through proxy-old/proxy-new to the active backend"
  - "One switch/active-proxy.conf edit + one reload flips BOTH HTTP:9092 and SSH:22 (SW-03); flip.sh unchanged"
  - "section_ssh + section_hostkey reconciled onto the switch topology and re-enabled in the make test runner"
affects: [phase-07-v1-preservation, migration, ssh, cutover]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One shared map file (active-proxy.conf) included in BOTH http and stream contexts drives both protocols from one selector (D-39)"
    - "Single-file bind mount requires container --force-recreate to re-bind a new inode after an edit"
    - "Recreating one container that shares a host-dir bind mount can desync sibling containers' mount view on Docker Desktop macOS — recreate them too"

key-files:
  created: []
  modified:
    - "switch/nginx.conf — added the SSH:22 stream block (verbatim v1 re-home, 3 string deltas)"
    - "scripts/smoke.sh — reconciled section_ssh + section_hostkey + shared helpers onto the switch; re-enabled both in the all runner"
    - ".planning/REQUIREMENTS.md — SW-03 Complete, SW-01 finalized"

key-decisions:
  - "Stream access_log is /dev/stdout only (D-46) — never the JSON evidence sink the http block writes"
  - "Reconciled SSH-02/D-46 asserts grep the LIVE switch/nginx.conf, not the archived proxy/nginx.conf (Phase 7 keeps proxy/ intact)"
  - "Kept the direct-to-backend BACK-04/BACK-05 group unchanged; only the proxied-hop group and shared helpers moved to the switch"

patterns-established:
  - "SW-03 one-edit-both-protocols flip: active-proxy.conf included twice (http + stream), one reload cuts over both"

requirements-completed: [SW-03, SW-01]

coverage:
  - id: D1
    description: "switch/nginx.conf stream block: switch listens on :22, upstreams target proxy-old:22/proxy-new:22, includes demo/active-proxy.conf, stream access_log stdout-only (D-46), no worker-shutdown grace (D-40), no host :22 publish (D-15)"
    requirement: "SW-03"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh ssh (SSH-01/02/03, D-39, D-46, EVID-01, CUT-04, D-40) — 66 passed, 0 failed"
        status: pass
      - kind: integration
        ref: "docker compose exec switch nginx -t; nc -z 127.0.0.1 22; include count == 2; stream access_log == 1 /dev/stdout, 0 var/log; worker_shutdown_timeout count == 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "One switch/active-proxy.conf edit + one reload flips both HTTP:9092 and SSH:22 to the same backend, same ssh command (SW-03; finalizes SW-01's SSH half)"
    requirement: "SW-03"
    verification:
      - kind: integration
        ref: "ssh app.demo.test -> OLD; flip.sh new -> NEW over same command + HTTP NEW; flip.sh old -> OLD (live)"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh ssh CUT-04 identical-stored-command OLD->NEW; D-40 in-flight OLD / fresh NEW"
        status: pass
    human_judgment: false
  - id: D3
    description: "section_ssh + section_hostkey reconciled onto the switch topology and re-enabled in the all runner; full regression green"
    requirement: "SW-03"
    verification:
      - kind: integration
        ref: "make test — 241 passed, 0 failed, exit 0 (all 7 sections incl. ssh 66/0 + hostkey 20/0)"
        status: pass
    human_judgment: false

# Metrics
duration: ~35min
completed: 2026-07-22
status: complete
---

# Phase 6 Plan 01: The SSH Stream Flip and Pre-Flip Validation Summary

**The switch now answers SSH on :22 via a re-homed nginx stream block that shares the one active-proxy.conf selector with the http block, so a single flip.sh reload cuts over HTTP:9092 and SSH:22 together — and the two deferred SSH test sections are reconciled onto the switch and green in `make test` (241/0).**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-07-22T02:56Z
- **Completed:** 2026-07-22T03:31Z
- **Tasks:** 2
- **Files modified:** 3 (switch/nginx.conf, scripts/smoke.sh, .planning/REQUIREMENTS.md)

## Accomplishments
- Re-homed v1's proven `stream {}` block onto `switch/nginx.conf` with exactly three string deltas (upstreams `proxy-old:22`/`proxy-new:22`, include `demo/active-proxy.conf`). The switch now listens on :22 and relays SSH two hops (switch → static proxy → backend).
- `demo/active-proxy.conf` is now included exactly twice in `switch/nginx.conf` (once http, once stream) — one selector, both protocols. Proven live: `ssh app.demo.test` → OLD; `flip.sh new` → NEW over the identical command AND HTTP → NEW; `flip.sh old` → OLD. flip.sh and compose.yaml unchanged.
- Stream `access_log` is `/dev/stdout` only (D-46 evidence-sink separation verified: exactly one stream access_log, targets stdout, names no `var/log` path). No `worker_shutdown_timeout` anywhere (D-40). No host `:22` publish (D-15).
- Reconciled `section_ssh`, `section_hostkey`, and the shared `selector_now`/`restore_ssh_state`/`finish_ssh_state` helpers from the v1 `proxy` topology onto the switch, and re-enabled both sections in the `all` runner. `make test` green: 241 passed, 0 failed (ssh 66/0, hostkey 20/0).

## Task Commits

1. **Task 1: Re-home the SSH:22 stream block onto the switch** - `c7245bd` (feat)
2. **Task 2: Reconcile and re-enable section_ssh + section_hostkey onto the switch** - `de8825a` (test)

**Plan metadata:** committed separately with this SUMMARY + REQUIREMENTS.md.

## Files Created/Modified
- `switch/nginx.conf` - Added the top-level `stream {}` block (verbatim v1 re-home; upstreams retargeted to the static proxies on :22; shared `active-proxy.conf` include; stdout-only stream log). Reconciled the now-false "NO stream block this phase" trailing comment.
- `scripts/smoke.sh` - Re-pointed shared helpers and the section_ssh proxied-hop group + section_hostkey oracle from `proxy`/`proxy/active-backend.conf`/`proxy/nginx.conf`/`/active-backend` onto `switch`/`switch/active-proxy.conf`/`switch/nginx.conf`/`/active-proxy`; re-enabled both sections in the `all` runner (removed Phase-6 deferral markers). Direct-to-backend BACK-04/05 group left untouched.
- `.planning/REQUIREMENTS.md` - SW-03 marked Complete; SW-01 finalized (SSH half now delivered); traceability rows updated.

## Decisions Made
- Asserted SSH-02/D-46 config-shape checks against the LIVE `switch/nginx.conf`, not the archived `proxy/nginx.conf` (per RESEARCH Open Question 2 resolution). `proxy/` preservation stays Phase 7 (MIG-03) — untouched.
- Reworded two comments that would otherwise trip acceptance greps or state a now-false fact: dropped the literal token `worker_shutdown_timeout` from a switch comment (kept the D-40 intent as "no worker-shutdown grace period"), and updated SSH-01's "the proxy listens on :22" narrative/label to "the switch" now that the flip surface owns :22.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Recreated the `status` container to clear a Docker Desktop bind-mount desync**
- **Found during:** Task 2 (running `make test`)
- **Issue:** Task 1's `docker compose up -d --force-recreate --wait switch` recreated only the switch. The `status` container shares the same `./switch` → `/etc/nginx/demo` host-directory bind mount and was left with a stale/empty view (`ls /etc/nginx/demo` → `total 0`), so the status service reported `UNAVAILABLE` ("active-proxy.conf — no such file or directory"). This turned 19 unrelated `section_cutover` status assertions (EVID-02/03, T-02-04, EV2-01/03, CUT-05) red while ssh (66/0) and hostkey (20/0) passed in isolation.
- **Fix:** `docker compose up -d --force-recreate --wait status` re-established the mount; status returned OK/OLD/IN_SYNC.
- **Files modified:** none (runtime rig state only)
- **Verification:** `make test` → 241 passed, 0 failed, exit 0.
- **Committed in:** n/a (no file change)

**2. [Rule 1 - Honesty/correctness] Comment reconciliations in the edited files**
- **Found during:** Tasks 1 and 2
- **Issue:** switch/nginx.conf's trailing comment declared "NO stream block this phase"; the D-40 comment I added used the literal `worker_shutdown_timeout` token (tripping the count==0 acceptance grep); section_ssh's SSH-01 label/comments called the :22 listener "the proxy".
- **Fix:** Reconciled each to match reality (stream block present; "no worker-shutdown grace"; "the switch listens on :22"). No assertion logic weakened.
- **Files modified:** switch/nginx.conf, scripts/smoke.sh
- **Verification:** `grep -c worker_shutdown_timeout switch/nginx.conf` == 0; `make test` green.
- **Committed in:** c7245bd, de8825a

---

**Total deviations:** 2 (1 blocking rig-state fix, 1 correctness/honesty comment reconciliation)
**Impact on plan:** No scope change. The status-container recreate is an environmental artifact of the plan's own required `--force-recreate switch` step on Docker Desktop macOS, not a config defect. Documenting so Phase 7 / future runs recreate sibling containers sharing the `./switch` mount.

## Issues Encountered
- Single-file bind mount stale inode (expected, plan-flagged): after editing `switch/nginx.conf`, `nginx -t` inside the container reported a truncated file until `--force-recreate` re-bound the new inode. Resolved exactly as the plan directs.
- Docker Desktop macOS mount desync on the `status` sibling container (see Deviation 1).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SW-03 mechanism complete: one selector edit flips both protocols; SW-01 finalized (switch is the sole client endpoint on HTTP 9092 and SSH 22).
- `make test` green with the full SSH surface re-enabled; D-15 (no host :22) and D-46 (evidence-sink separation) controls stay green.
- Phase 7 (MIG-03) v1 preservation is untouched: `proxy/nginx.conf` and `proxy/active-backend.conf` remain on disk.
- Note for future runs: when recreating the switch alone, also recreate any sibling container sharing the `./switch` bind mount (currently `status`) to avoid a stale mount view.

## Known Stubs
None - config + POSIX-sh test changes only; no placeholder or empty-value stubs introduced.

## Self-Check: PASSED

- switch/nginx.conf, scripts/smoke.sh, 06-01-SUMMARY.md — all present on disk
- Task commits c7245bd, de8825a — both present in git history

---
*Phase: 06-the-ssh-stream-flip-and-pre-flip-validation*
*Completed: 2026-07-22*
