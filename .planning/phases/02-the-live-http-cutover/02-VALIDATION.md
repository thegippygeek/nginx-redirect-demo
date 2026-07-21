---
phase: 2
slug: the-live-http-cutover
# status lifecycle: draft (seeded by plan-phase) -> validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-21
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `02-RESEARCH.md` § Validation Architecture, which was written against a
> working prototype rather than from theory.

---


`workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `scripts/smoke.sh` — POSIX `sh`, hand-rolled `assert <label> <condition>`, section-dispatched. No third-party runner |
| Config file | none — the script *is* the config. Sections dispatched by `$1` (`backends`, `proxy`, `redirect`; Phase 2 adds `cutover`) |
| Quick run command | `sh scripts/smoke.sh cutover` |
| Full suite command | `make test` (== `sh scripts/smoke.sh` == all sections) |
| Current baseline | 42 assertions across three sections; `sh scripts/smoke.sh proxy` re-verified green at **17 passed, 0 failed** this session |

Phase 2 extends this rather than introducing a second idiom (per CONTEXT.md's Reusable Assets note). Two existing conventions must be honoured: the script is deliberately **not** `set -e` so every assertion runs, and any destructive assertion backs up the file it touches and restores it via a `trap` on `EXIT INT TERM` — the pattern `guard_check()` already establishes.

### Phase Requirements → Test Map

| Req ID | Behavior | Test type | Automated command | File exists? |
|--------|----------|-----------|-------------------|-------------|
| CUT-01 | Flipping rewrites exactly one word in `active-backend.conf` and reloads cleanly | integration | `sh scripts/smoke.sh cutover` — assert the file differs from baseline in exactly one line, that `nginx -t` passes, and that the reload exits 0 | ❌ Wave 0 |
| CUT-01 | The file stays five lines including both presenter comments after a flip | integration | assert `wc -l == 5` and that both `^#` lines survive `make flip-new` | ❌ Wave 0 |
| CUT-02 | The identical command string returns OLD then NEW with no client change | integration | capture `CMD='curl -fsS http://localhost:9092/whoami'`; assert `$CMD` → `^OLD server-old$`, flip, assert **the same `$CMD` string** → `^NEW server-new$` | ❌ Wave 0 |
| CUT-02 | Via the real hostname from the client container, likewise unchanged | integration | same, through `docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami` | ❌ Wave 0 |
| CUT-03 | After flip + settle, traffic lands on NEW | integration | flip, poll `:8081/active-backend` until `new`, `sleep 0.2`, assert `/whoami` → `^NEW server-new$` | ❌ Wave 0 |
| CUT-03 | The flip is decisive — 20 consecutive post-settle requests are all NEW | integration | loop 20 `/whoami`, assert zero `OLD` (guards against the interleave leaking past the settle) | ❌ Wave 0 |
| CUT-05 | Flip back and re-flip works with **no container restart** | integration | record `docker inspect -f '{{.State.StartedAt}}'` for proxy and both backends before; run flip-old → flip-new → flip-old; assert all three timestamps unchanged | ❌ Wave 0 |
| CUT-05 | Evidence reset empties the log and the status readings | integration | `make flip-old`; assert the evidence file is 0 bytes and `/api/status` reports `NO_TRAFFIC` with both counters `0` | ❌ Wave 0 |
| D-35 | Flip refuses when a backend is down, and does not modify the config file | integration | `docker compose stop server-new`; assert `make flip-new` exits non-zero, prints the reason, and `active-backend.conf` is byte-identical afterwards; restart and re-assert green | ❌ Wave 0 |
| EVID-01 | **Phase 1 regression guard** — stdout still carries `backend=` | integration | re-run `sh scripts/smoke.sh proxy`; assert still 17/17. The single most important assertion in the phase | ✅ exists |
| EVID-01 | The evidence log carries `backend=NEW` after a flip | integration | assert the evidence file's last 9092 line has `"backend":"NEW"` | ❌ Wave 0 |
| EVID-01 | Both sinks receive the same request | integration | issue one uniquely-pathed request; assert it appears exactly once in `docker compose logs proxy` **and** once in the evidence file | ❌ Wave 0 |
| EVID-01 | `make logs-demo` colourises without swallowing lines | smoke | `docker compose logs --tail 5 -t proxy \| awk '<same script>' \| grep -c .` equals the input line count | ❌ Wave 0 |
| EVID-02 | Status reports config and traffic as two separate readings | integration | `curl -fsS http://localhost:9094/api/status`; assert both `config` and `traffic` keys are present and independently valued | ❌ Wave 0 |
| EVID-02 | PENDING is observable between edit and reload (D-27) | integration | edit the file **without** reloading; assert `sync == "PENDING"` with `config != traffic`; reload; assert `IN_SYNC` | ❌ Wave 0 |
| EVID-02 | UNAVAILABLE when the proxy is stopped (UI-SPEC test 4, Pitfall 6) | integration | `docker compose stop proxy`; within 5 s assert `state == "UNAVAILABLE"` and that **no** `traffic` value is reported; restart | ❌ Wave 0 |
| EVID-02 | UNAVAILABLE when the config is unreadable (UI-SPEC test 13) | integration | `chmod 000` the include (trap-restore!); assert full UNAVAILABLE, not a half-lit page | ❌ Wave 0 |
| EVID-03 | Recent requests list the answering backend | integration | issue a uniquely-pathed request; assert it appears in `rows[0]` with the correct `backend` | ❌ Wave 0 |
| EVID-03 | A boundary is reported after a flip, with a direction | integration | flip; assert `boundary.from == "OLD"` and `boundary.to == "NEW"` | ❌ Wave 0 |
| EVID-03 | Healthcheck traffic never enters the evidence (Pitfall 7) | integration | wait through 3 healthcheck intervals with no user traffic; assert the evidence line count is unchanged | ❌ Wave 0 |
| EVID-03 | 9093 redirect requests are excluded | integration | hit `:9093`; assert the counters and `rows` are unchanged | ❌ Wave 0 |
| — | Status port is loopback-only (T-01-06) | smoke | `docker compose port status 9094 \| grep -q '^127.0.0.1:9094$'` | ❌ Wave 0 |
| — | Status volume mount is read-only | smoke | assert `docker compose exec -T status sh -c ': > /var/log/demo/access.log'` **fails** | ❌ Wave 0 |
| — | The page makes zero external requests (UI-SPEC test 2) | manual-only | Visual inspection with the network panel. Automatable in part: assert `grep -c -E 'https?://(?!localhost)' status/index.html` is 0 | partial |
| — | Greyscale / distance / projector legibility (UI-SPEC tests 1, 3, 5, 9) | manual-only | Requires human visual judgement at the specified viewing distance. Belongs in `/gsd-verify-work` UAT, not smoke | manual |

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh cutover` — the phase's own section, plus `sh scripts/smoke.sh proxy` whenever `proxy/nginx.conf` is touched (the dual-`access_log` regression guard).
- **Per wave merge:** `make test` — all four sections green.
- **Phase gate:** `make test` fully green, then `make reset && make test` from cold to prove the evidence volume's lifecycle, before `/gsd-verify-work`.

### Wave 0 Gaps

- [ ] `scripts/smoke.sh` — add `section_cutover()` and register it in the `case` dispatcher; extend the usage string.
- [ ] `scripts/smoke.sh` — add a `settle_flip()` helper (poll `:8081/active-backend`, then `sleep 0.2`) so no assertion re-derives the timing logic.
- [ ] `scripts/smoke.sh` — add a `restore_flip_state()` trap helper mirroring `guard_check()`'s discipline: the cutover section is destructive by nature (it flips config and stops containers) and must leave the rig on OLD with everything running, even on `INT`.
- [ ] `scripts/flip.sh` — the shared flip implementation the three Make targets delegate to; assertions drive it directly.
- [ ] Framework install: **none** — POSIX `sh`, already present.

---

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Greyscale distinguishability of OLD vs NEW | UI-SPEC test 1 | `#b45309` and `#15803d` are isoluminant (0.1591 vs 0.1593, ratio 1.00:1) — they are the same colour in greyscale. Only a human can confirm the word/position/rule channels carry the signal without colour. | Screenshot the page in each state, desaturate, confirm OLD and NEW remain unambiguous. |
| Legibility at projection distance | UI-SPEC tests 3, 5, 9 | Requires the physical viewing distance and a projector's contrast loss. | Display at 1920x1080, step back ~10m, confirm the ACTIVE banner, the sync marker, and the table boundary all read. |
| The flip reads as an event, not a flicker | D-27 | The value of the dual reading is whether a room perceives the gap closing. Not mechanically checkable. | Run the cutover with an observer; confirm they can narrate what happened without prompting. |
| Zero external network requests | UI-SPEC test 2 | Partially automatable (grep for absolute URLs); full proof needs a browser network panel. | Open devtools network panel, hard reload, confirm no third-party origins. |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all Wave 0 gaps listed above
- [ ] No watch-mode flags
- [ ] `sh scripts/smoke.sh proxy` still returns 17/17 — the dual-`access_log` regression guard
- [ ] Cold-start path (`make reset && make test`) exercised at least once per wave
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
