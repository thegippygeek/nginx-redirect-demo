---
phase: 1
slug: demo-up-http-lands-on-old
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-21
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `01-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — POSIX shell assertions. No language runtime is required or present; adding a test framework would contradict ENV-03 ("no prior setup"). `bats-core` considered and rejected — six assertions that `curl -fsS` plus `test` already express clearly are not worth a `brew`/`apk` install on the presenter's machine. |
| **Config file** | none — Wave 0 creates `scripts/smoke.sh` |
| **Quick run command** | `sh scripts/smoke.sh` |
| **Full suite command** | `make test` (wraps `scripts/smoke.sh`) |
| **Estimated runtime** | ~5 seconds against a warm stack; ~30–60 seconds from cold start |

**Forward compatibility:** Phase 3's verify script (EVID-04/05) has the same shape — a shell script asserting observed backend against expected, exiting non-zero on mismatch. Establishing plain shell here means EVID-04 extends `scripts/smoke.sh` rather than introducing a second idiom.

---

## Sampling Rate

- **After every task commit:** `sh scripts/smoke.sh` (whole suite, seconds, against an already-up stack)
- **After every plan wave:** `make reset && make test` — the cold-start path
- **Before `/gsd-verify-work`:** `make reset && make test` green, plus the manual browser check for HTTP-04
- **Max feedback latency:** ~60 seconds (cold), ~5 seconds (warm)

**The cold-start distinction is load-bearing.** The `depends_on: service_healthy` race and `[emerg] host not found in upstream` only manifest from a cold `down -v`. A warm-stack-only suite would miss the single most likely demo-day failure.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | 01 | 1 | ENV-01 | — | N/A | integration | `docker compose up -d --wait` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | ENV-02 | — | N/A | integration | `docker compose down -v && test -z "$(docker compose ps -aq)"` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | ENV-03 | — | No credentials, no registry auth, no secrets in repo | manual-only | inspection — see Manual-Only Verifications | n/a | ⬜ pending |
| TBD | 01 | 1 | ENV-04 | — | N/A | smoke | `docker compose exec -T proxy nginx -V 2>&1 \| grep -q -- --with-stream` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | BACK-01 | — | sshd present but not published to host | smoke | `curl -fsS localhost:9090/healthz && docker compose exec -T server-old sh -c 'nc -z localhost 22'` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | BACK-02 | — | sshd present but not published to host | smoke | `curl -fsS localhost:9091/healthz && docker compose exec -T server-new sh -c 'nc -z localhost 22'` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | BACK-03 | — | N/A | smoke | `curl -fsS localhost:9090/whoami \| grep -q '^OLD server-old$'` (and NEW/server-new on 9091) | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | HTTP-01 | — | N/A | smoke | `curl -fsS http://localhost:9092/whoami \| grep -q OLD` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | HTTP-02 | — | N/A | smoke | `test "$(curl -sSL -o /dev/null -w '%{num_redirects}' http://localhost:9092/)" = 0` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | HTTP-03 | — | N/A | smoke | `curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' http://localhost:9093/ \| grep -q '^301 '` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | HTTP-04 | — | N/A | smoke + manual | `test "$(curl -sSL -o /dev/null -w '%{url_effective}' http://localhost:9093/whoami)" != "http://localhost:9093/whoami"`; browser check per D-07 | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | D-11 (feeds EVID-01) | — | N/A | smoke | `curl -sSI http://localhost:9092/ \| grep -qi '^X-Backend: OLD'` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | Phase 2 precondition | — | N/A | smoke | `docker compose logs proxy \| grep -q 'backend=OLD'` | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | Phase 4 precondition (KEY-01) | — | Host keys generated at runtime, never baked into the image | smoke | compare `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` across both backends; assert **not** equal | ❌ W0 | ⬜ pending |

*Task IDs are filled in by the planner. Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**The last three rows are not Phase 1 requirements — they are Phase 1 responsibilities.** Each is a precondition a later phase silently depends on, and each was found to be a real failure mode during research. Asserting them here is what stops them regressing unnoticed:

- **Log format** (`backend=OLD`) — Phase 2's EVID-01 depends entirely on the log format chosen in Phase 1.
- **`X-Backend` header** — D-11; the machine-greppable half of the identity signal.
- **Distinct host keys** — `ssh-keygen -A` at *build* time would produce identical keys on both backends (one image, D-16), making Phase 4's KEY-01 impossible to stage. Runtime generation in the entrypoint satisfies KEY-01 for free.

---

## Wave 0 Requirements

- [ ] `scripts/smoke.sh` — covers ENV-01, ENV-02, ENV-04, BACK-01..03, HTTP-01..04, plus the three cross-phase preconditions
- [ ] `Makefile` targets `test` and `status` — the runner surface (D-19)
- [ ] Framework install: **none required** — POSIX shell plus `curl`, both already present [VERIFIED by research]

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No cloud account, credentials, or cost | ENV-03 | Absence of a dependency is not meaningfully automatable | Inspect repo: no registry auth, no cloud SDK, no secrets, no `.env` with credentials. Confirm `docker compose up` succeeds on a machine with no cloud CLI configured. |
| URL bar stays put on proxy, changes on redirect | HTTP-04 / D-07 | The decisive proof is visual — a browser URL bar. `curl` covers the mechanism; only a browser covers the demo claim. | Open `http://app.demo.test:9092/` — URL bar unchanged. Open `http://app.demo.test:9093/` — URL bar visibly changes to the backend's address. |
| Host `/etc/hosts` entry present | D-03 | Host-machine state, outside the container boundary | `grep app.demo.test /etc/hosts` on the presenter's machine returns a line mapping to `127.0.0.1`. Documented as a one-time setup step. |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all ❌ W0 references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s (cold), < 5s (warm)
- [ ] Cold-start path (`make reset && make test`) exercised at least once per wave
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
