---
phase: 6
slug: the-ssh-stream-flip-and-pre-flip-validation
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-22
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from 06-RESEARCH.md § Validation Architecture — SSH stream flip re-homes a v1-proven pattern onto the switch; the bulk is reconciling the deferred SSH/host-key harness.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | POSIX sh assertion harness (`scripts/smoke.sh`, `scripts/verify.sh`), no external deps |
| **Config file** | none — self-contained; `Makefile` targets `test`, `verify`, `ssh` |
| **Quick run command** | `sh scripts/smoke.sh ssh` (SSH section) / `make verify EXPECT=old` |
| **Full suite command** | `make test` (== `sh scripts/smoke.sh all`) |
| **Estimated runtime** | ~60–90 seconds (compose up, includes SSH handshakes) |

---

## Sampling Rate

- **After every task commit:** `sh scripts/smoke.sh ssh` (or the specific reconciled section) + `nginx -t` inside the switch
- **After every plan wave:** `make test`
- **Before `/gsd-verify-work`:** `make test` green AND `make verify EXPECT=new` exit 0
- **Max feedback latency:** ~90 seconds

---

## Per-Requirement Verification Map

| Req | Wave | Behavior | Test Type | Automated Command | Exists |
|-----|------|----------|-----------|-------------------|--------|
| SW-03 | 1 | switch stream block includes the shared map; one edit flips SSH | integration | `sh scripts/smoke.sh ssh` (SSH-02 / D-39 reconciled to `switch/nginx.conf`) | ❌ W0 |
| SW-03 | 1 | same `ssh app.demo.test` command lands OLD→NEW across a flip | integration | `sh scripts/flip.sh new && sh scripts/smoke.sh ssh` (CUT-04 / D-40) | ❌ W0 |
| VAL-01 | 2 | `app-new` HTTP → NEW while switch → OLD | integration | `docker compose exec -T client curl -fsS http://app-new.demo.test/whoami` == `NEW server-new` **and** `curl -fsS localhost:9092/whoami` == `OLD server-old` | ❌ W0 |
| VAL-02 | 2 | `app-new` SSH → server-new banner pre-flip | integration | `docker compose exec -T client ssh <opts> demo@app-new.demo.test true` grep `NEW server-new` | ❌ W0 |
| EV2-04 | 2 | verify.sh asserts both protocols through the switch; non-zero on mismatch | integration | `make verify EXPECT=old` exit 0; after flip `make verify EXPECT=new` exit 0; forced split exit 3 | ⚠️ SSH half activates with the stream block |
| EV2-04 | 2 | verify.sh `--target app-new` asserts NEW pre-flip | integration | `sh scripts/verify.sh --target app-new` (new mode, both probes from client container, expectation fixed NEW) | ❌ W0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Add the SSH:22 `stream` block to `switch/nginx.conf` (upstreams `proxy-old:22`/`proxy-new:22`, shared `include demo/active-proxy.conf`, `listen 22; proxy_pass $active_backend`, access_log `/dev/stdout` only — **never** the JSON evidence sink, D-46) — the production edit the tests assert against
- [ ] Reconcile `section_ssh` proxied-hop group + `selector_now()` / `restore_ssh_state` / `finish_ssh_state` helpers onto the switch (Pitfall 4 stale-ref table: `proxy`→`switch`, `active-backend.conf`→`active-proxy.conf`, `/active-backend`→`/active-proxy`)
- [ ] Reconcile `section_hostkey` oracle probe + any `proxy` / `app.demo.test:22` references onto the switch
- [ ] Add VAL-01 / VAL-02 assertions (app-new pre-flip, **client-container** context, port 80 HTTP + 22 SSH)
- [ ] Add `verify.sh --target app-new` mode
- [ ] Re-enable `section_ssh` + `section_hostkey` in the `all` runner (remove the `# Phase 6 (SW-03)` deferral markers)

---

## Manual-Only Verifications

*All phase behaviors have automated verification (SSH handshakes, banners, and exit codes are all assertable in the harness).*

---

## Validation Sign-Off

- [ ] All requirements have an `<automated>` verify or Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers the stream block + harness reconciliation + verify.sh mode
- [ ] No watch-mode flags
- [ ] `make test` green including re-enabled section_ssh + section_hostkey; D-15 (no host :22) still passing
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
