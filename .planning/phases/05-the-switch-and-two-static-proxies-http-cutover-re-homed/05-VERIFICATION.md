---
phase: 05-the-switch-and-two-static-proxies-http-cutover-re-homed
verified: 2026-07-22T00:00:00Z
status: passed
score: 4/4 ROADMAP success criteria verified (live); 9/9 in-scope requirement IDs Complete, SW-01 honestly Pending
behavior_unverified: 0
overrides_applied: 0
mode: mvp
re_verification:
  previous_status: none
  note: "Initial verification. 05-REVIEW.md WR-01/WR-02 both marked FIXED — both fixes confirmed real in the codebase and by the live suite (155/0)."
---

# Phase 5: The Switch and Two Static Proxies — HTTP Cutover Re-Homed — Verification Report

**Phase Goal:** Replace v1's single flip-in-place proxy with a blue-green tier — a front `switch` nginx and two static single-upstream proxies (proxy-old→server-old, proxy-new→server-new, aliased app-old/app-new.demo.test). The client still hits app.demo.test:9092 exactly as in v1; HTTP lands on OLD through switch→proxy-old→server-old; one edit-and-reload of the switch's one-line map flips HTTP to NEW. Evidence re-sourced from the switch, which sees the client's real remote_addr while the backend's own X-Backend identity flows back up the chain.
**Verified:** 2026-07-22
**Status:** PHASE VERIFIED (passed)
**Re-verification:** No — initial verification. Docker available; verified against the LIVE running rig, not just SUMMARY claims.

## Goal Achievement — 4 ROADMAP Success Criteria (live evidence)

| # | Success Criterion | Status | Live Evidence |
|---|-------------------|--------|---------------|
| 1 | One command brings up switch + proxy-old + proxy-new + server-old + server-new + status; `curl :9092` lands on OLD through the switch, client hostname/port unchanged (MIG-01, SW-01 HTTP) | ✓ PASS | `docker compose up -d --build --wait` → exit 0; `docker compose ps` shows **6 healthy** (switch, proxy-old, proxy-new, server-old, server-new, status; client has no healthcheck by design). `client → app.demo.test:9092/whoami` → **`OLD server-old`** |
| 2 | Editing `default old`→`new` in `switch/active-proxy.conf` + reload flips HTTP to NEW, identical client command (SW-02, SW-04) | ✓ PASS | `sh scripts/flip.sh new` exit 0 → `curl localhost:9092/whoami` = **`NEW server-new`**, status `.config`=**NEW**; `sh scripts/flip.sh old` → **`OLD server-old`**; `make reset` exit 0 → **`OLD server-old`**, `switch/active-proxy.conf` restored 5 lines / 2 comments byte-identical |
| 3 | Status page reads the SWITCH's log: rows carry the client's real `remote_addr` (not a proxy IP); `backend=OLD/NEW` carried from the backend's own X-Backend, asserted by no proxy tier (EV2-01, EV2-02) | ✓ PASS | `/api/status` `rows[0].remote` = **172.19.0.8** = the **client** container IP; proxy-old=172.19.0.5, proxy-new=172.19.0.6 (remote ≠ either). Exactly **one** `X-Backend` header survives a static-proxy hop (`grep -ci '^X-Backend:'` = 1), value `X-Backend: OLD`. **Zero** `add_header` (non-comment) across switch + proxy-old + proxy-new configs |
| 4 | Status shows the current selector + recent backends, re-sourced from the switch (EV2-03) | ✓ PASS | `/api/status` `.config`=OLD, `.state`=OK, 3 rows, `rows[0].backend`=OLD; reads `switch/active-proxy.conf` via `DEMO_CONF_PATH`, probes `switch:8081`; selector flips NEW after `flip.sh new`, back to OLD after reset |

**Score: 4/4 ROADMAP success criteria VERIFIED against the live rig.**

### Full Test Suite

| Suite | Command | Result | Status |
|-------|---------|--------|--------|
| Full smoke | `make test` | **155 passed, 0 failed**, exit 0 (backends + proxy + redirect + cutover + walkthrough) | ✓ PASS |

Note: 05-03-SUMMARY reported 154/0; the 05-REVIEW WR-02 fix (commit `0bb56ca`) added the EV2-01 `remote` assertion, taking it to 155/0. Live re-run confirms **155/0** — matches expected. Not a discrepancy; a timeline artifact.

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `switch/nginx.conf` | flip surface + evidence writer, upstreams→proxy-old/new:80, +remote field, no stream, no add_header | ✓ VERIFIED | upstreams re-pointed (L72-73); `"remote":"$remote_addr"` (L49); `escape=json`; literal 9093 redirect (L138); 0 stream; 0 add_header |
| `switch/active-proxy.conf` | 5-line, 2-comment presenter flip file | ✓ VERIFIED | 5 lines / 2 `#` / `map $server_port $active_backend { default old; }` |
| `proxy-old/nginx.conf` | static → server-old:80 + inert SSH server-old:22 + :8081 health | ✓ VERIFIED | `server server-old:80` / `:22`; listen 8081 + nginx-health; 0 add_header |
| `proxy-new/nginx.conf` | mirror → server-new | ✓ VERIFIED | `server server-new:80` / `:22`; listen 8081 + nginx-health; 0 add_header |
| `compose.yaml` | 3-service split + health cascade + alias move + no static-proxy ports | ✓ VERIFIED | 6 healthy under one `up --wait`; app-old/app-new aliases resolve; static proxies publish nothing |
| `status/status.py` | render `remote`, probe switch:8081, read active-proxy.conf | ✓ VERIFIED | `/api/status` renders real client remote, state OK, config selector correct |
| `status/index.html` | CLIENT column + WR-01 UNAVAILABLE re-point to switch | ✓ VERIFIED | CLIENT column present; ERR_BODY + `Check: docker compose ps switch` re-pointed |
| `scripts/flip.sh` | switch-targeted, gate probes proxy-old/proxy-new | ✓ VERIFIED | `CONF=switch/active-proxy.conf`, `ORACLE=.../active-proxy`, 0 `exec -T proxy`, gate loops `proxy-old proxy-new`; flip old↔new proven live |
| `Makefile` reset | writes switch/active-proxy.conf byte-identical | ✓ VERIFIED | reset → OLD, byte-identical restore |
| `scripts/smoke.sh` | reconciled HTTP sections + EV2-01 assertion + SSH deferral | ✓ VERIFIED | EV2-01 assert (L732-733); markers present; ssh/hostkey preserved intact |

## Requirements Coverage (every in-scope ID accounted for)

| Requirement | Description | REQUIREMENTS.md | Verdict | Evidence |
|-------------|-------------|-----------------|---------|----------|
| SW-01 | Switch is client's only endpoint on HTTP 9092 **and SSH 22** | Pending | ✓ CORRECTLY PENDING | HTTP half live-proven; switch ships **no stream block** — SSH:22 is SW-03/Phase 6. Leaving Pending is the honest call (bundled req, only half deliverable this phase) |
| SW-02 | One-line map in active-proxy.conf is the only file edited | Complete | ✓ SATISFIED | flip.sh edits only that file; selector flip proven live |
| SW-04 | Cutover = edit one line + `nginx -s reload`, no client change | Complete | ✓ SATISFIED | `flip.sh new/old` → NEW/OLD, identical `curl localhost:9092/whoami` |
| PROX-01 | proxy-old statically forwards to server-old, never reconfigured | Complete | ✓ SATISFIED | `switch→proxy-old/whoami`=OLD; single fixed upstream; SSH stream inert-from-birth |
| PROX-02 | proxy-new statically forwards to server-new | Complete | ✓ SATISFIED | `switch→proxy-new/whoami`=NEW |
| PROX-03 | Distinct aliases app-old/app-new.demo.test | Complete | ✓ SATISFIED | both resolve on the demo network (172.19.0.5 / .6) |
| EV2-01 | Switch log captures client's real remote_addr | Complete | ✓ SATISFIED | `rows[0].remote`=172.19.0.8=client IP, ≠ either proxy; smoke assertion enforces it |
| EV2-02 | Backend's own X-Backend propagates untampered; no proxy asserts it | Complete | ✓ SATISFIED | exactly 1 X-Backend through hop = OLD; 0 add_header on all 3 tiers |
| EV2-03 | Status shows selector + recent backends, re-sourced from switch | Complete | ✓ SATISFIED | selector + rows render; flips NEW/OLD from switch |
| MIG-01 | Whole v2 topology up with one `docker compose up` | Complete | ✓ SATISFIED | 6 healthy, one command, `--wait` exit 0 |

No orphaned requirements. SW-03 is a Phase 6 ID (not in Phase 5's list) — correctly out of scope.

## Scope-Fence Honesty Check (were fences broken silently?)

| Fence | Expected | Verdict | Evidence |
|-------|----------|---------|----------|
| Switch has NO stream block (SSH:22 → Phase 6) | 0 stream on switch | ✓ HONEST | `grep -c '^stream' switch/nginx.conf` = 0 |
| section_ssh preserved intact, gated out of `all` | function kept, not gutted | ✓ HONEST | **570 lines, 67 asserts** intact; commented in `all` with `# Phase 6 (SW-03)` marker; still dispatchable via `ssh)` |
| section_hostkey preserved intact, gated out of `all` | function kept, not gutted | ✓ HONEST | **260 lines, 21 asserts** intact; `# Phase 6 (SW-03)` marker; dispatchable via `hostkey)` |
| Deferred v1 `proxy` refs contained to SSH region | only ≥ line 1064 | ✓ HONEST | first residual `exec -T proxy`/`proxy/active-backend` hit at L1080 — inside section_ssh/hostkey machinery; HTTP sections clean |
| SW-01 left Pending, not falsely marked Complete | Pending w/ honest reason | ✓ HONEST | Pending; HTTP delivered, SSH:22 half explicitly deferred |

The fences held **honestly** — nothing was gutted to fake a green. The `all` runner still exercises backends + proxy + redirect + cutover + walkthrough (155 assertions), and the SSH sections would fail loudly (no `proxy` service) if run standalone — no false-green risk.

## Code-Review Fix Confirmation (05-REVIEW.md)

| Finding | Claim | Verdict |
|---------|-------|---------|
| WR-01: UNAVAILABLE panel named dead `proxy` service | FIXED (e64442b) | ✓ CONFIRMED — index.html ERR_BODY + `Check: docker compose ps switch · logs switch`; config copy names active-proxy |
| WR-02: EV2-01 had no integration assertion | FIXED (0bb56ca) | ✓ CONFIRMED — smoke.sh L732-733 asserts `rows[0].remote` present ∧ ≠ proxy-old IP ∧ ≠ proxy-new IP; runs green live |

## Anti-Patterns

None found. No stubs, no TODO/FIXME/XXX debt markers in the changed files. `add_header` matches are full-line comments only. Every rendered status field flows from real runtime data (switch evidence log + active-proxy.conf).

## Human Verification (non-blocking nicety only)

One optional, explicitly non-blocking item carried from 05-02 (not a goal-achievement gate):

### CLIENT column projector legibility
**Test:** Open http://localhost:9094 and confirm the new client-IP column reads legibly at projector scale.
**Expected:** Muted, one-size-down monospace column following v1 table tokens; OLD→NEW money shot stays primary.
**Why human:** Pure visual aesthetics. The column's presence and data flow (real client IP) are already verified programmatically; only projector-scale legibility is human-only. Plan marked it non-blocking. Does NOT affect any of the 4 success criteria or any requirement contract.

## Gaps Summary

**No gaps.** All 4 ROADMAP success criteria pass against the live rig. All 9 in-scope requirement IDs are Complete and runtime-proven; SW-01 is honestly Pending because its bundled SSH:22 half is deferred to Phase 6/SW-03 (the switch ships no stream block by design). The security-critical evidence-integrity axis is clean: the client's real remote_addr is logged (not a proxy hop), exactly one backend-owned X-Backend survives the two-hop chain, and no tier forges identity. Scope fences held honestly — the deferred SSH sections are preserved fully intact with explicit Phase-6 markers, not gutted. `make test` is green at 155/0.

**Verdict: PHASE VERIFIED.**

---

_Verified: 2026-07-22_
_Verifier: Claude (gsd-verifier) — verified against the live running rig, not SUMMARY claims_
