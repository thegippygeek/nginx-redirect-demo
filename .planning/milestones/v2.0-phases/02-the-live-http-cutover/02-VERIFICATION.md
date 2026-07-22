---
phase: 02-the-live-http-cutover
verified: 2026-07-21T10:36:00Z
status: passed
score: 4/4 roadmap success criteria verified (12/12 must-haves including load-bearing decisions)
behavior_unverified: 0
overrides_applied: 0
re_verification: null
---

# Phase 2: The Live HTTP Cutover — Verification Report

**Phase Goal:** Presenter flips the nginx upstream from old to new on stage, reloads, and the audience sees the same URL now answered by `server-new` — with independent evidence confirming it.
**Verified:** 2026-07-21
**Status:** passed
**Re-verification:** No — initial verification
**Method:** Live execution against the running stack. Every criterion below was exercised with real commands; no claim rests on SUMMARY.md text.

## Goal Achievement

### Roadmap Success Criteria

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Presenter edits upstream + reloads; identical `curl` with no client-side change returns NEW | ✓ VERIFIED | `curl -sS http://localhost:9092/whoami` → `OLD server-old`; `make flip-new`; **same command** → `NEW server-new`. Response headers moved `X-Backend: OLD/X-Backend-Host: server-old` → `X-Backend: NEW/X-Backend-Host: server-new`. Printed diff showed exactly one changed line: `-    default old;` / `+    default new;` |
| 2 | Live access-log tail shows each request and which upstream served it, visibly switching at the flip | ✓ VERIFIED | Captured `docker compose logs -f proxy` across a real flip. Consecutive lines: `... backend=OLD rt=0.001` then `... upstream=172.19.0.4:80 backend=NEW`. The upstream IP changes with the backend word — the log is reporting observation, not assertion. `make logs-demo` colourisation confirmed live (ANSI `1;97;43` amber OLD block emitted on a real request) |
| 3 | Status page shows the currently active backend and lists recent requests with the answering backend | ✓ VERIFIED | `GET :9094/api/status` returns `config`, `traffic`, `traffic_host`, `sync`, `counts{OLD,NEW}`, `rows[]` (time/path/status/backend/bhost) and `boundary`. `GET :9094/` serves 27,815 bytes of `text/html` with a 1 s poll (`POLL_MS = 1000`, `setInterval(poll, POLL_MS)`) satisfying D-24. Page JS passes `node --check` |
| 4 | Presenter can flip back to `server-old` and re-run the whole cutover without tearing anything down | ✓ VERIFIED | Ran **three** complete take cycles (`flip-new` → `flip-old` → `flip-new` → `flip-old` → …) with zero `docker compose down`/`restart`. Container uptimes were continuous throughout. Each `flip-old` left the evidence at zero and the next take read clean |

**Score: 4/4.**

### Load-Bearing Decisions (explicitly targeted)

| Item | Status | Evidence |
|------|--------|----------|
| **Phase 1 regression guard** | ✓ VERIFIED | `sh scripts/smoke.sh proxy` → `--- 17 passed, 0 failed ---`, exactly as required. The second `access_log` sink did not disturb the Phase 1 stdout format; the two Phase 1 assertions that grep `log_format demo` still pass |
| **Full suite** | ✓ VERIFIED | `sh scripts/smoke.sh` → `--- 120 passed, 0 failed ---` across `backends`/`proxy`/`redirect`/`cutover`. (Note: higher than the 116 quoted in the brief — see Observations. Zero failures either way) |
| **D-27 dual reading genuinely separate** | ✓ VERIFIED | Edited `default new;` → `default old;` **without reloading**. `/api/status` returned `config OLD / traffic NEW / sync PENDING` while the `:8081` oracle independently confirmed the running config was still `new`. After `nginx -s reload` the reading correctly stayed `PENDING` (traffic had not yet moved), then converged to `config OLD / traffic OLD / sync IN_SYNC` on the first post-reload request. PENDING is observable, distinct, and traffic-driven — not merged |
| **D-28 UNAVAILABLE has three inputs** | ✓ VERIFIED | `docker compose stop proxy` → within the first poll (t+0s) `/api/status` returned `state UNAVAILABLE, failing_source "proxy", config null, traffic null, sync CANNOT_DETERMINE, counts {OLD:0,NEW:0}, rows [], boundary null`. Fully blanked, all-or-nothing, never a stale banner. Proxy restarted and healthy. Code confirms the gate is `if cfg_err or log_err or not proxy_ok` — three independent inputs (`read_config`, `read_log`, `probe_proxy` against `:8081/nginx-health`) |
| **D-35 health-gated flip** | ✓ VERIFIED | With `server-new` stopped: `make flip-new` printed `REFUSING TO FLIP: server-new is not answering /healthz.` and **exited 2** (non-zero). `shasum proxy/active-backend.conf` was **byte-identical** before and after (`9b5726…5019`). Confirmed the gate runs *before* any write. Also verified the both-directions claim: `make flip-old` was refused identically while `server-new` was down |
| **D-36 evidence clearing** | ✓ VERIFIED | `make flip-old` → `/api/status` immediately reported `state NO_TRAFFIC, sync AWAITING_FIRST_REQUEST, counts {OLD:0,NEW:0}, rows 0, boundary null, since_flip_s null`. Counters, history, boundary and since-flip clock all reset. Containers untouched |
| **Deferred D1 closed** | ✓ VERIFIED | `flip.sh` step 6 now branches: the reset direction truncates and issues **no** confirming request. Confirmed in three reset runs — no traffic reading ever moved NEW→OLD, so the convergence sequence is structurally unable to fire on a reset |
| **`boundary.row_index` = `min(3, post_flip_row_count)`** | ✓ VERIFIED (with note) | Observed live migration `1 → 2 → 3 → 3 (pinned)` as post-flip requests arrived, then correct release. `status.py` computes it from the window actually returned (`len(above)`), and `index.html:573-578` places the boundary object at exactly that index rather than recomputing. The formula holds exactly. See Observations for the unreachable `0` case |
| **XSS** | ✓ VERIFIED | `grep -c 'innerHTML' status/index.html` → **0**. A request to `/<script>alert(1)</script>` was logged verbatim (`nginx escape=json` handled it) and is returned as `'/<script>alert(1)</script>'` in the API. Every DOM insertion routes through `var txt = function(el, s){ el.textContent = s; }` — `el()`, `rowEl()`, `boundaryEl()`, `errorEl()`, `emptyEl()` all use it. No `insertAdjacentHTML`/`outerHTML`/`document.write` anywhere |
| **Phase 3 territory untouched** | ✓ VERIFIED | No active `stream` block in `proxy/nginx.conf` (only the commented Phase 3 sketch at the file tail). No port 22 in `compose.yaml`. `worker_shutdown_timeout` appears exactly once, inside a prose comment explaining why it is deliberately unset |
| **Zero external assets** | ✓ VERIFIED | No `src=`, `href=`, `@import`, font-host or CDN reference in `status/index.html`. The only two `http://` occurrences are the literal empty-state copy string `"Send a request to http://app.demo.test:9092/…"`. Backed by permanent assertions in `smoke.sh` (`UI-SPEC 2 zero src/href attributes of any kind`) |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `Makefile: flip/flip-old/flip-new` | `scripts/flip.sh` | `sh scripts/flip.sh <target>` | ✓ WIRED — all three exercised live |
| `scripts/flip.sh` | `proxy/active-backend.conf` | `sed` rewrite + `diff -u` + restore-on-failure | ✓ WIRED — diff printed, rollback proven byte-identical |
| `scripts/flip.sh` | proxy `:8081/active-backend` | reload oracle retry loop (25 × 0.2 s) | ✓ WIRED — oracle independently queried and agreed |
| `proxy/nginx.conf` | `demo-logs` volume | `access_log /var/log/demo/access.log evidence` (second sink) | ✓ WIRED — JSON lines observed, stdout `demo` sink unaffected |
| `demo-logs` volume | `status/status.py` | `demo-logs:/var/log/demo:ro` | ✓ WIRED — and provably read-only (smoke asserts the status container cannot truncate it) |
| `status/status.py` | `status/index.html` | `GET /api/status`, 1 s poll | ✓ WIRED — live JSON matches every field the page reads |
| `proxy/active-backend.conf` | `status/status.py` | `./proxy:/etc/nginx/demo:ro` directory mount | ✓ WIRED — D-27's config reading changed within one poll of a file edit |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data? | Status |
|----------|------|--------|-----------|--------|
| `status/index.html` table | `data.rows` | `/api/status` → nginx `evidence` log | Yes — rows changed with each real request I issued | ✓ FLOWING |
| `status/index.html` banner | `data.config` / `data.traffic` | config file / last served log row | Yes — moved independently under D-27 test | ✓ FLOWING |
| `status/index.html` stats rail | `data.counts`, `since_flip_s` | derived from log window | Yes — counts tracked my requests exactly (`{OLD:5, NEW:1→4}`) | ✓ FLOWING |
| `/api/status` `state` | three-input gate | config + log + `:8081` probe | Yes — flipped to UNAVAILABLE on real proxy stop | ✓ FLOWING |

No hollow props, no hardcoded empties, no static fallbacks.

### Requirements Coverage

| Req | Description | Status | Evidence |
|-----|-------------|--------|----------|
| CUT-01 | Switch active backend by editing upstream + reloading | ✓ SATISFIED | SC1 |
| CUT-02 | No client-side change — same hostname, ports, commands | ✓ SATISFIED | Byte-identical `curl` before/after |
| CUT-03 | Post-flip requests land on `server-new`, provable from body | ✓ SATISFIED | `NEW server-new` body + `X-Backend-Host` |
| CUT-05 | Flip back to re-run without full teardown | ✓ SATISFIED | SC4, three cycles, continuous uptime |
| EVID-01 | Tail nginx access logs live, see which upstream served each request | ✓ SATISFIED | SC2; `make logs` and `make logs-demo` both exercised |
| EVID-02 | Status page shows which backend is currently active | ✓ SATISFIED | SC3, plus D-27's two-reading form |
| EVID-03 | Status page shows recent requests and which backend answered | ✓ SATISFIED | SC3 rows[] with per-row backend and the flip boundary |

No orphaned requirements: REQUIREMENTS.md maps exactly these seven to Phase 2, and all seven are claimed by the phase plans.

### Behavioural Spot-Checks

| Behaviour | Command | Result | Status |
|-----------|---------|--------|--------|
| Proxy serves active backend | `curl -sS :9092/whoami` | `OLD server-old` / `NEW server-new` | ✓ PASS |
| Flip pipeline end-to-end | `make flip-new` | gate → diff → `nginx -t` → reload → oracle → confirm | ✓ PASS |
| Health gate refuses + preserves file | `docker compose stop server-new; make flip-new` | exit 2, sha unchanged | ✓ PASS |
| UNAVAILABLE predicate | `docker compose stop proxy; curl :9094/api/status` | fully blanked at t+0s | ✓ PASS |
| Evidence reset | `make flip-old; curl :9094/api/status` | `NO_TRAFFIC`, counts zeroed | ✓ PASS |
| Phase 1 regression | `sh scripts/smoke.sh proxy` | `17 passed, 0 failed` | ✓ PASS |
| Full regression | `sh scripts/smoke.sh` | `120 passed, 0 failed` | ✓ PASS |
| Page JS validity | `node --check` on extracted script | clean | ✓ PASS |
| Status page served | `curl -o /dev/null -w '%{http_code}' :9094/` | `200 text/html 27815` | ✓ PASS |

### Anti-Patterns Found

None. `grep -nE 'TBD|FIXME|XXX'` and `grep -nEi 'TODO|HACK|placeholder|not yet implemented|coming soon'` across `proxy/nginx.conf`, `proxy/active-backend.conf`, `status/status.py`, `status/index.html`, `scripts/flip.sh`, `scripts/smoke.sh`, `Makefile`, `compose.yaml`, `README.md` returned zero hits. No debt markers, no stubs, no empty implementations.

### Observations (non-blocking, no action required)

1. **`boundary.row_index = 0` is documented but structurally unreachable.** `02-UI-SPEC.md:483-486` states the boundary sits at index 0 "at the instant of the flip". The implementation detects a boundary by scanning for a backend transition between adjacent log rows, so a boundary cannot exist until at least one post-flip row does — the first observable value is 1. The stated formula `min(3, post_flip_row_count)` is satisfied exactly; only the value 0 is unobservable, and `smoke.sh:690` correctly asserts 1 with one post-flip row. This affects nothing the audience sees: the boundary appears with the first post-flip request and migrates 1 → 2 → 3 as specified. It is a spec-prose nuance, not a defect.

2. **Full suite reports 120 assertions, not the 116 quoted in the phase brief.** Zero failures either way; the delta is a count discrepancy in the narration, not a regression.

3. Verification touched only `proxy/active-backend.conf` (via `flip.sh` and one deliberate D-27 edit) and the evidence log. `git status` confirms no source file is modified; the selector is restored to `default old;`, the running config oracle reports `old`, `:9092` serves `OLD server-old`, the evidence log is cleared, and all five containers are up and healthy.

### Human Verification Required

None outstanding. The visual/legibility items (projector contrast, type scale, row legibility at distance) were human-verified and approved at the 02-04 checkpoint. The projector-overscan consideration remains deliberately unresolved per UI-SPEC and cannot be settled without venue hardware — accepted, not a gap.

### Gaps Summary

No gaps. Every roadmap success criterion was exercised live against the running stack and passed. The four decisions singled out as highest-risk — the Phase 1 log regression, D-27's PENDING state, D-28's three-input blanking, and D-35's write-after-gate ordering — were each tested by inducing the failure they exist to handle, and each behaved exactly as designed. The one item deferred out of 02-03 (D1, `flip.sh` truncation ordering) has been structurally closed in the shipped script.

---

*Verified: 2026-07-21*
*Verifier: Claude (gsd-verifier)*
