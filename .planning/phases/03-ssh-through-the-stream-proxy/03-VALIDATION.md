---
phase: 3
slug: ssh-through-the-stream-proxy
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-21
---

# Phase 3 — Validation Strategy

> Derived from `03-RESEARCH.md` § Validation Architecture, which was written against experiments
> executed on the running stack.

---


`workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `scripts/smoke.sh` — POSIX `sh`, hand-rolled `assert <label> <condition>`, section-dispatched. No third-party runner. |
| Config file | none — the script *is* the config. Sections dispatched by `$1` (`backends`, `proxy`, `redirect`, `cutover`; Phase 3 adds `ssh`). |
| Quick run command | `sh scripts/smoke.sh ssh` |
| Full suite command | `make test` (== `sh scripts/smoke.sh` == all sections) |
| Current baseline | **120 assertions, 0 failures**, re-verified this session — *and re-verified green with the Phase 3 stream block live*. `sh scripts/smoke.sh proxy` = **17/17**. |

Conventions that must be honoured (established Phase 1, reaffirmed Phase 2): deliberately **not**
`set -e` so every assertion runs; any destructive assertion backs up what it touches and restores via
a `trap` on `EXIT INT TERM` (`guard_check()` is the reference implementation); every section leaves
the rig selecting **OLD**.

### Phase Requirements → Test Map

| Req ID | Behavior | Test type | Automated command | File exists? |
|--------|----------|-----------|-------------------|-------------|
| SSH-02 | `proxy/nginx.conf` contains a top-level `stream` block that `proxy_pass`es, and contains no redirect on the SSH path | unit | `sh scripts/smoke.sh ssh` — assert `grep -q '^stream {' proxy/nginx.conf` and `awk` the stream block contains `proxy_pass $active_backend` | ❌ Wave 0 |
| SSH-02 | The stream block includes **the same file** the http block includes (D-39, the phase's headline claim) | unit | assert `active-backend.conf` appears exactly **twice** in `proxy/nginx.conf` (once per context), and that `proxy/active-backend.conf` is still **5 lines** | ❌ Wave 0 |
| SSH-01 | nginx is listening on :22 inside the proxy container | integration | `docker compose exec -T proxy nc -z 127.0.0.1 22` — **`127.0.0.1`, not `localhost`** (§Q8) | ❌ Wave 0 |
| SSH-01 | An `ssh` from the `client` to `app.demo.test:22` reaches the **active** backend | integration | capture the §Q9 idiom; assert stdout contains `server-old` with selector `old` | ❌ Wave 0 |
| BACK-05 | Key auth works, non-interactively, to **both** backends directly | integration | `ssh -o BatchMode=yes … demo@server-old hostname` and `…@server-new` → `server-old` / `server-new` | ❌ Wave 0 |
| BACK-05 | The sshd settings actually took effect (guards Pitfall S-2) | integration | `docker compose exec -T server-old sshd -T \| grep -i '^authorizedkeysfile /keys'` — **`sshd -T`, not a config grep** | ❌ Wave 0 |
| BACK-04 | Each backend's banner names its own identity and hostname, anchored like BACK-03 | integration | direct `ssh …@server-old true 2>&1` captured → `grep -q 'OLD server-old'`; same for NEW | ❌ Wave 0 |
| BACK-04 | The banner is `Banner`, not motd — i.e. it survives a non-interactive invocation (D-43) | integration | the capture above uses `ssh host <command>`; passing **is** the proof | ❌ Wave 0 |
| SSH-03 | The banner survives the stream hop | integration | same capture via `app.demo.test` instead of the backend directly | ❌ Wave 0 |
| CUT-04 | The **identical** `ssh` command string returns OLD then NEW across a flip (CUT-02's SSH twin) | integration | store `CMD` in a variable; assert OLD; `sh scripts/flip.sh new`; assert **the same `$CMD`** → NEW; restore to `old` via `trap` | ❌ Wave 0 |
| CUT-04 | The host key presented at :22 changes with the selector (auth-free corroboration) | integration | `ssh-keyscan -t ed25519 app.demo.test` fingerprint == the active backend's `/etc/ssh/ssh_host_ed25519_key.pub` | ❌ Wave 0 |
| D-40 | An in-flight session survives a reload while a new one lands on the new backend | integration | background a `timeout 20 ssh … 'sleep 8; hostname'`; flip; assert the backgrounded one still reports the **old** backend and a fresh one reports the new. **Must be `timeout`-bounded (Pitfall S-6).** | ❌ Wave 0 |
| EVID-04 | `verify.sh <expected>` reports **both** protocols' observed backend on labelled lines | integration | `sh scripts/verify.sh old` → stdout names HTTP and SSH readings; exit 0 | ❌ Wave 0 |
| EVID-05 | `verify.sh` exits **non-zero** on a mismatch | integration | `! sh scripts/verify.sh new` while the selector is `old` | ❌ Wave 0 |
| EVID-05 | `verify.sh` exits non-zero when the **two protocols disagree** (D-45) — distinct message | integration | hard to induce naturally; assert the code path exists: `grep -q` for the disagreement branch **and** exercise it by pointing the SSH probe at a fixed backend | ❌ Wave 0 |
| EVID-05 | `verify.sh` cannot mask an ssh failure in a pipeline (Pitfall S-1) | unit | assert no line in `verify.sh` matches `ssh .*|` in an assertion position; and that `-q`/`LogLevel=` never appear (Pitfall S-3) | ❌ Wave 0 |
| EVID-05 | `verify.sh` terminates rather than hangs | integration | `timeout 30 sh scripts/verify.sh old` exits well under the bound | ❌ Wave 0 |
| D-38 | No host port 22 binding exists (existing assertion, must keep passing) | unit | already in `section_proxy` — **verified still passing with the stream block live** | ✅ exists |
| D-46 | The stream block never writes to the JSON evidence sink | unit | assert the stream block contains no `/var/log/demo` | ❌ Wave 0 |
| Regression | Phase 1's 17 and the full 120 survive | integration | `sh scripts/smoke.sh proxy` == 17/17; `make test` == 120+/0 | ✅ exists |

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh ssh` (the new section only — seconds)
- **Per wave merge:** `sh scripts/smoke.sh proxy && sh scripts/smoke.sh ssh` — the 17/17 guard is the
  canonical regression tripwire and is cheap
- **Phase gate:** full `make test` green (120 + the new `ssh` section), plus `sh scripts/verify.sh old`
  exit 0 and `! sh scripts/verify.sh new`, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `section_ssh()` in `scripts/smoke.sh` + dispatch entry + `all` inclusion — covers SSH-01/02/03,
      BACK-04/05, CUT-04, D-40, D-46
- [ ] `scripts/verify.sh` — covers EVID-04/05; it is both deliverable and test subject
- [ ] `make verify` target
- [ ] A `trap`-based restore in `section_ssh` returning the selector to **old** (the suite's invariant)
- [ ] No framework install needed — the harness exists and is the established idiom

---

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Wave 0 gaps closed (`section_ssh()`, `scripts/verify.sh`, `make verify`, trap-based selector restore)
- [ ] `sh scripts/smoke.sh proxy` still returns exactly 17/17
- [ ] Full suite green from a cold `make reset && make test`
- [ ] SSH assertions pin `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` so they do not
      break for the wrong reason once Phase 4 stages KEY-02
- [ ] No SSH assertion pipes ssh into another command (`ssh … | head` masks the exit code)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
