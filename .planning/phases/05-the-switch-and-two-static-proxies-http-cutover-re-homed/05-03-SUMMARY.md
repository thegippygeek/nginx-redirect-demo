---
phase: 05-the-switch-and-two-static-proxies-http-cutover-re-homed
plan: 03
subsystem: infra
tags: [nginx, cutover, flip, smoke-tests, health-gate, evidence-log]

# Dependency graph
requires:
  - phase: 05-02
    provides: running 6-service topology (switch + proxy-old/new + server-old/new + status), switch-sourced evidence, reconciled section_backends/proxy/redirect
provides:
  - The flip re-homed to the switch — flip.sh edits switch/active-proxy.conf and reloads the switch; identical client command lands on NEW (SW-04)
  - Health gate probes the switch's real upstreams (proxy-old/proxy-new :8081/nginx-health), not the backends (RESEARCH Pitfall 2)
  - make reset restores switch/active-proxy.conf byte-identical so the demo reopens on OLD (D-36/D-12)
  - Reconciled section_cutover + flip helpers; EV2-03 asserts /api/status.config re-sources NEW/OLD from the switch
  - make test green across the HTTP surface (backends + proxy + redirect + cutover + walkthrough): 154 passed, 0 failed
  - section_ssh + section_hostkey deferred to Phase 6 with explicit markers, preserved intact
affects: [06 switch SSH:22 (SW-03) re-enables section_ssh/section_hostkey, 07 walkthrough rewrite]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "The flip is a switch map-edit + reload — same v1 CUT-01/CUT-02 mechanism, one tier up"
    - "Gate probes the intermediate proxies' health, not the backends: the switch parses upstream proxy-old/proxy-new on every reload"
    - "SSH-deferred machinery (section_ssh/section_hostkey + their exclusive helpers) fenced off intact for Phase 6"

key-files:
  created: []
  modified:
    - scripts/flip.sh
    - Makefile
    - scripts/smoke.sh
    - .planning/REQUIREMENTS.md

key-decisions:
  - "D-35 cutover gate test re-homed to stop proxy-new (the switch's upstream), not server-new: the re-homed gate probes the static proxies, so stopping a backend no longer trips it (Rule 1)."
  - "Stale UI-SPEC grid assertion updated to the 6-column EV2-01 CLIENT layout added in 05-02 — the cutover section was never run green after that change (Rule 1)."
  - "SW-02 marked Complete alongside SW-04: the reconciled cutover section runtime-proves the switch selects via the one-line map in switch/active-proxy.conf, the only file the presenter edits."
  - "SSH-deferred proxy references (selector_now/set_active/restore_ssh_state/finish_ssh_state + section_ssh/section_hostkey, all at lines >=1064) left untouched for Phase 6, honoring the scope fence."

patterns-established:
  - "Every remaining proxy/active-backend reference in smoke.sh now lives strictly in the SSH-deferred region (line >=1064) — Phase 6 owns those renames"

requirements-completed: [SW-02, SW-04]

# Metrics
duration: 25min
completed: 2026-07-22
status: complete
---

# Phase 05 Plan 03: Re-home the Flip to the Switch (HTTP Cutover) Summary

**The on-stage flip now runs from the switch: `sh scripts/flip.sh new` edits the one line in `switch/active-proxy.conf`, reloads the switch, and the identical `curl localhost:9092/whoami` lands on NEW server-new — gated on the switch's real upstreams (proxy-old/proxy-new), reset byte-identical to reopen on OLD, with `make test` green at 154/0 and the switch-SSH sections honestly deferred to Phase 6.**

## Performance
- **Duration:** ~25 min
- **Tasks:** 3 (all `type=auto`)
- **Files:** 4 modified

## Accomplishments
- **scripts/flip.sh (Task 1):** `CONF=switch/active-proxy.conf`, `ORACLE=http://localhost:8081/active-proxy`. Every container exec re-pointed to the `switch` (nginx -t, nginx -s reload, the :8081 oracle probe, and the evidence truncation into the switch's rw mount). The health gate now loops over `proxy-old proxy-new`, probing each proxy's `:8081/nginx-health` from inside the switch container (RESEARCH Pitfall 2 — the switch parses `upstream proxy-old/proxy-new` on every reload, so those must resolve, not the backends). The six-step structure, `diff -u` money shot, exit-code checks and reset-vs-forward split are untouched. No residual reference to the removed front-tier `proxy` container remains, not even in a comment.
- **Makefile `reset` (Task 1):** the canonical-file printf writes `switch/active-proxy.conf` (both the path and the header-comment filename), keeping the `map $$server_port $$active_backend { default old; }` body byte-identical (D-36/D-12; doubled `$$` for Make 3.81). Verified byte-identical to the canonical after `make reset`, reopening on OLD.
- **scripts/smoke.sh section_cutover + helpers (Task 2):** ~40 references mechanically re-homed to the switch across `settle_flip`, `restore_flip_state`, `manual_flip`, `finish_flip_state` and the section body — exec targets, `logs`, `stop`/`up`, `ps -q switch server-old server-new`, the oracle (`active-backend`→`active-proxy`), the flip include path, the restore trap (now brings up `switch proxy-old proxy-new`), and the status container's config-mount path (`/etc/nginx/demo/active-proxy.conf`). Added an explicit **EV2-03** block: after `flip.sh new` the switch-sourced `/api/status.config` reads NEW with the recent-requests table populated, and `flip.sh old` re-sources it to OLD.
- **scripts/smoke.sh `all` runner (Task 3):** `section_ssh` and `section_hostkey` commented out with `# Phase 6 (SW-03): re-enable when the switch carries the SSH:22 stream` — the switch ships no stream block this phase, so `app.demo.test:22` has no listener. The section FUNCTIONS are preserved intact and still run via `sh scripts/smoke.sh ssh|hostkey`. `section_walkthrough` kept in `all` (empirically green, 25/0, a pure Phase-4 doc-lint reader).

## Verification Results
- **SW-04:** `sh scripts/flip.sh new` → `NEW server-new`; `sh scripts/flip.sh old` → `OLD server-old`, both via the identical client command (`curl -fsS localhost:9092/whoami`).
- **Gate (Pitfall 2):** `grep -q 'proxy-old proxy-new' scripts/flip.sh` and `grep -c 'exec -T proxy' scripts/flip.sh` = 0.
- **make reset:** completes, whoami → `OLD server-old`, `switch/active-proxy.conf` is 5 lines / 2 comment lines and byte-identical to the canonical.
- **section_cutover:** `sh scripts/smoke.sh cutover` → 80 passed, 0 failed; `exec -T proxy` count inside the section and its flip helpers = 0; `settle_flip` carries no `active-backend`; EV2-03 config flips NEW→OLD; the section leaves the rig on OLD.
- **make test:** 154 passed, 0 failed, exit 0 — backends + proxy + redirect + cutover + walkthrough.
- **Scope fence:** `section_ssh()` and `section_hostkey()` each present exactly once (preserved); every remaining `exec -T proxy`/`proxy/active-backend` reference sits at line ≥1064, inside the SSH-deferred machinery.

## Requirements
Marked **Complete** (runtime-proven by this plan): `SW-02` (the switch selects via the one-line map in `switch/active-proxy.conf`, the only file edited), `SW-04` (cutover = edit one line + reload the switch, no client-side change).

**SW-01 / SW-03 left Pending (honest):** both require the switch's SSH:22 stream, which is deferred to Phase 6 — the switch ships no stream block this phase. `EV2-03` was already Complete from 05-02 and its flip-side assertion is now additionally proven here.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] D-35 cutover gate test re-homed from a backend to a proxy**
- **Found during:** Task 2 (first cutover run)
- **Issue:** The v1 test stopped `server-new` (a backend) and expected the flip to refuse. The re-homed gate (Task 1) probes the static proxies' `:8081/nginx-health`, which stays up when a backend stops — so the flip proceeded, the config was modified, and the refusal never named the tier. Two assertions failed ("names the backend that is not answering", "byte-identical after the refusal").
- **Fix:** Stop `proxy-new` (the switch's upstream) instead; the refusal now names `proxy-new` and leaves the config byte-identical, exercising the actual re-homed gate. Updated the comment (Pitfall 2), assertion labels, and the bring-back line.
- **Files modified:** scripts/smoke.sh
- **Commit:** `960c007`

**2. [Rule 1 - Bug] Stale UI-SPEC grid assertion updated to the 6-column layout**
- **Found during:** Task 2 (first cutover run)
- **Issue:** The cutover UI-SPEC assertion expected `grid-template-columns: .75rem 12.5rem 38.75rem 7.5rem 14rem;` (5 columns), but 05-02 added the EV2-01 CLIENT column making it 6. Because section_cutover was never run green after 05-02, this stale assertion had gone undetected.
- **Fix:** Updated the expected string to the actual `.75rem 12.5rem 26.25rem 7.5rem 12.5rem 14rem;`.
- **Files modified:** scripts/smoke.sh
- **Commit:** `960c007`

**Total deviations:** 2 (both Rule 1, both in smoke.sh, both stale-assertion reconciliations exposed by re-running the previously-unrun cutover section; no scope creep).

## Scope-Fence Note (honest interpretation)
The Task 3 acceptance grep expects remaining proxy references "ONLY inside the deferred section_ssh/section_hostkey ranges." All remaining `exec -T proxy` / `proxy/active-backend` references live at line ≥1064 — i.e., in the SSH-deferred region: `section_ssh`, `section_hostkey`, and their **exclusive** private helpers (`selector_now`, `set_active`, `keyscan_fp`, `hostkey_fp`, `restore_ssh_state`, `finish_ssh_state`), none of which are called by any HTTP section in the `all` runner. These are left intact for Phase 6 (SW-03) to reconcile alongside the sections they serve.

## Known Stubs
None. Every reconciled reference points at a live container/file, and every assertion runs against the running rig.

## Threat Flags
None. No new network surface, auth path, or schema introduced. T-05-01/02/03 mitigations hold: the green suite includes 05-02's EV2-02 two-hop integrity assertion, `guard_check` still proves a typo'd selector returns a legible 503, and the reset printf keeps the literal map body.

## Self-Check
- **Modified files:** FOUND: scripts/flip.sh, Makefile, scripts/smoke.sh, .planning/REQUIREMENTS.md
- **Commits:** FOUND: 637d4d4, 960c007, 2e7e8f7

## Self-Check: PASSED

---
*Phase: 05-the-switch-and-two-static-proxies-http-cutover-re-homed*
*Completed: 2026-07-22*
