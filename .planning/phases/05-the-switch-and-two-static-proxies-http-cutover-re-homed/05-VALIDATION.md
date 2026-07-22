---
phase: 5
slug: the-switch-and-two-static-proxies-http-cutover-re-homed
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-22
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from 05-RESEARCH.md § Validation Architecture — all nginx behaviours empirically verified against the pinned `nginx:1.30.4-alpine`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | POSIX shell smoke suite (`scripts/smoke.sh`), `section_*` functions, driven by `make test` |
| **Config file** | none — plain `sh`; no test runner to install |
| **Quick run command** | `docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami` + the single requirement's targeted command |
| **Full suite command** | `make test` |
| **Estimated runtime** | ~30–60 seconds (compose already up) |

---

## Sampling Rate

- **After every task commit:** `curl -s localhost:9092/whoami` + the touched requirement's targeted command
- **After every plan wave:** the updated `section_proxy` (topology) and `section_cutover` (flip) smoke sections
- **Before `/gsd-verify-work`:** full `make test` green — all seven `section_*` reconciled to the switch topology
- **Max feedback latency:** ~60 seconds

---

## Per-Requirement Verification Map

Task IDs are assigned by the planner; this seeds the draft with the empirically-derived command per requirement (validate-phase refines to per-task rows).

| Req | Wave | Behavior | Threat Ref | Test Type | Automated Command | File Exists |
|-----|------|----------|------------|-----------|-------------------|-------------|
| MIG-01 | 1 | one command brings up all 6 services healthy | — | integration | `docker compose up -d --wait && docker compose ps --format '{{.Service}} {{.Status}}' \| grep -c healthy` | ❌ W0 (extend `section_proxy`) |
| SW-01 | 1 | client hits `app.demo.test:9092` unchanged → OLD via switch→proxy-old→server-old | — | integration | `docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami \| grep -qx 'OLD server-old'` | ❌ W0 |
| PROX-01 | 1 | `proxy-old` statically forwards to server-old | — | integration | `docker compose exec -T switch curl -fsS http://proxy-old/whoami \| grep -qx 'OLD server-old'` | ❌ W0 |
| PROX-02 | 1 | `proxy-new` statically forwards to server-new | — | integration | `docker compose exec -T switch curl -fsS http://proxy-new/whoami \| grep -qx 'NEW server-new'` | ❌ W0 |
| PROX-03 | 1 | distinct aliases resolve on the demo net | — | integration | `docker compose exec -T switch getent hosts app-old.demo.test app-new.demo.test` | ❌ W0 |
| EV2-02 | 1 | `backend=` is the backend's own `X-Backend` through 2 hops; no proxy asserts it | T-05 integrity | integration | `curl -sD- localhost:9092/whoami \| grep -i '^X-Backend: OLD'` **and** static-proxy emits exactly one `X-Backend` | ❌ W0 |
| SW-02/SW-04 | 2 | edit `switch/active-proxy.conf` + reload flips to NEW, same client command | — | integration | `make flip-new && curl -fsS localhost:9092/whoami \| grep -qx 'NEW server-new'` | ⚠️ adapt `flip.sh` + `section_cutover` |
| EV2-01 | 2 | evidence rows carry the client's real `remote_addr`, not a proxy IP | V5 | integration | `curl -s localhost:9094/api/status \| jq -e '.rows[0].remote'` and assert ≠ proxy container IP | ❌ W0 (new JSON field + render) |
| EV2-03 | 2 | status shows current selector + recent backends (re-sourced from switch) | — | integration | `curl -s localhost:9094/api/status \| jq -e '.config=="OLD" and (.rows\|length>0)'` | ⚠️ adapt `section_cutover` |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/smoke.sh` — reconcile the `proxy` references + topology refs to the `switch` / static-proxy shape; add proxy-old/proxy-new/alias and two-hop-header assertions
- [ ] `scripts/flip.sh` — `CONF` → `switch/active-proxy.conf`; `exec proxy` → `exec switch`; startup gate probes proxy-old/proxy-new
- [ ] `status/status.py` (+ status template) — render the new `remote` field; re-point `DEMO_PROXY_PROBE` / `DEMO_CONF_PATH` to the switch
- [ ] `Makefile` — `up`/`reset`/`clear-evidence`/`logs`/`logs-demo`/`reload` re-pointed to `switch`; reset canonical file → `switch/active-proxy.conf`
- [ ] New assertion: **EV2-02 integrity** — exactly one `X-Backend` passes through a static proxy (no proxy-injected identity)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Status page renders the client-IP column legibly at projector scale | EV2-01 | Visual/layout judgement, not assertable | Open `http://localhost:9094`, confirm the recent-requests table shows a client-IP column following v1's existing design tokens |

*All other phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All requirements have an `<automated>` verify or Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (smoke.sh, flip.sh, status.py, Makefile)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
