---
phase: 03-ssh-through-the-stream-proxy
verified: 2026-07-21T12:20:00Z
status: passed
score: 4/4 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 3: SSH Through the Stream Proxy — Verification Report

**Phase Goal:** Presenter SSHes to port 22 on the same host and lands on whichever backend is active, proving the cutover is not just an HTTP trick — with a script that asserts it automatically.
**Verified:** 2026-07-21T12:20:00Z
**Status:** passed
**Re-verification:** No — initial verification

Every finding below was produced by running a command against the live stack. No claim is carried over from a SUMMARY.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `ssh` to port 22 with a key gets a shell on the active backend; banner names it OLD/NEW with hostname | ✓ VERIFIED | `docker compose exec -T client ssh -o BatchMode=yes demo@app.demo.test hostname` → banner `OLD server-old` (stderr) + `server-old` (stdout), rc=0. `netstat` in proxy shows `0.0.0.0:22 LISTEN`. Key auth: no prompt, `BatchMode=yes` succeeded |
| 2 | nginx config visibly uses a `stream` block proxying raw TCP, not an HTTP redirect | ✓ VERIFIED | `proxy/nginx.conf` line 224 opens top-level `stream {`; line 90/91 of that block are `listen 22;` / `proxy_pass $active_backend;`. No `return`/`rewrite`/`301` directive in the block (only prose in a comment). `nginx -V` confirms `--with-stream` |
| 3 | After the flip, the identical `ssh` command lands on `server-new` with banner NEW | ✓ VERIFIED | Same `$CMD` string captured in a shell variable: before flip → `OLD server-old` / `server-old`; `sh scripts/flip.sh new`; after flip → `NEW server-new` / `server-new`. Restored with `flip.sh old` |
| 4 | Verify script issues HTTP + SSH, reports each, exits non-zero on mismatch | ✓ VERIFIED | `sh scripts/verify.sh old` → two labelled lines, rc=0 in 0.33 s. `sh scripts/verify.sh new` (selector on old) → `MISMATCH`, rc=1. Usage errors → rc=2. Cross-protocol disagreement → rc=3 |

**Score: 4/4 truths verified (0 present, behavior-unverified)**

### Focus-List Verification (each run, not read)

| Check | Result | Evidence |
|-------|--------|----------|
| **D-39 — same file, both contexts** | ✓ VERIFIED | `include /etc/nginx/demo/active-backend.conf` at nginx.conf:66 (inside `http`) and :256 (inside `stream`) — identical path, and `ls proxy/` shows exactly one `active-backend.conf`. No copy exists. Proven behaviourally: one word flipped → **both** protocols moved together, and back |
| **Phase 1 regression guard** | ✓ VERIFIED | `sh scripts/smoke.sh proxy` → `--- 17 passed, 0 failed ---` (exact) |
| **EVID-05 is not a lie (no pipe)** | ✓ VERIFIED | `grep -nE 'ssh .*\|' scripts/verify.sh` matches only line 119, a comment explaining the hazard. The capture is `SSH_OUT=$(...)` with `SSH_RC=$?` on the next line. **Tested against a real failure:** `VERIFY_SSH_HOST=192.0.2.1 sh scripts/verify.sh old` → `SSH ... UNREADABLE (exit 255)` and script rc=1. The failure is not masked |
| **D-45 cross-protocol disagreement** | ✓ VERIFIED | `VERIFY_SSH_HOST=server-new sh scripts/verify.sh old` with selector on `old` → `PROTOCOLS DISAGREE HTTP reported OLD, SSH reported NEW`, **rc=3** — its own code, distinct from the rc=1 mismatch path |
| **Banner mechanics** | ✓ VERIFIED | `sshd -T` on both backends → `banner /etc/ssh/banner` (not motd-sourced). Banner survives non-interactive `ssh host command`. Stream separation confirmed: with `2>/dev/null` the invocation prints only `server-old` — banner is on stderr, remote stdout is clean. `grep -nE '\-q\|LogLevel\|-tt' scripts/verify.sh` → no matches |
| **`sshd -T` is the source of truth** | ✓ VERIFIED | `docker compose exec -T server-old sshd -T` → `authorizedkeysfile /keys/authorized_keys`; same on `server-new`. The drop-in `/etc/ssh/sshd_config.d/10-demo.conf` beats Alpine's active line-45 directive via the line-15 `Include`, exactly as the Dockerfile comment claims. `passwordauthentication yes` confirms D-41's documented fallback survives |
| **D-38 — port 22 not published** | ✓ VERIFIED | `compose.yaml` publishes exactly `127.0.0.1:9090`, `9091`, `9092`, `9093`, `9094`. No `:22` mapping anywhere. `docker compose ps` shows no host port 22 |
| **D-40 — `worker_shutdown_timeout` unset** | ✓ VERIFIED | `grep -n '^\s*worker_shutdown_timeout' proxy/nginx.conf` → no active directive. Both textual occurrences are prose in the resolved deferred-question comment. Smoke asserts the measured behaviour at lines 1385-1387 |
| **Phase 4 unblocked AND unstaged** | ✓ VERIFIED | Host keys **differ**: `server-old` ed25519 `AAAAC3NzaC1lZDI1NTE5AAAAIIbMML…` vs `server-new` `…AAAAIKGjKs…`. Mechanism **live**: recorded `app.demo.test` into a temp known_hosts, flipped to new, reconnected → `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` reproduced verbatim; temp file removed, selector restored. **Unstaged**: client container has no `known_hosts` (only `config`, which sets `IdentityFile` and deliberately no `StrictHostKeyChecking`), and `grep -ci 'REMOTE HOST IDENTIFICATION' README.md` → **0** |
| **Stream logs → `/dev/stdout` only** | ✓ VERIFIED | Stream block declares one `access_log /dev/stdout demo_stream;` and contains zero occurrences of `/var/log/demo`. Live: 39 `ssh backend=` lines in `docker compose logs proxy`; `grep -c "ssh backend=" /var/log/demo/access.log` inside the status container → **0**. The JSON sink is uncontaminated, so `status.py`'s `except ValueError: continue` discards nothing |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `proxy/nginx.conf` | top-level `stream` block, shared include, stdout log | ✓ VERIFIED | 16 KB; stream block at line 224; loads and serves live |
| `proxy/active-backend.conf` | unchanged 5-line shared selector | ✓ VERIFIED | Exactly 5 lines, both presenter comments intact, drives both contexts |
| `scripts/verify.sh` | HTTP + SSH probe, 4-code vocabulary | ✓ VERIFIED | All four exit codes (0/1/2/3) reproduced live |
| `Makefile` `verify` target | `make verify [EXPECT=new]` | ✓ VERIFIED | `make verify` rc=0 against true state |
| `backend/templates/banner.template` | one line, byte-identical to `/whoami` | ✓ VERIFIED | Renders `OLD server-old` / `NEW server-new`; comment lines stripped by entrypoint `sed` |
| `backend/Dockerfile` sshd drop-in | `sshd_config.d/10-demo.conf` | ✓ VERIFIED | Effective values confirmed via `sshd -T`, not a config grep |
| `client/entrypoint.sh` | keypair into `demo-keys`, no host-key relaxation | ✓ VERIFIED | `/root/.ssh/config` contains only `Host * / IdentityFile /keys/id_ed25519` |
| `compose.yaml` | `demo-keys` volume, rw on client, `:ro` on backends, no port 22 | ✓ VERIFIED | Asymmetry present as documented |
| `scripts/smoke.sh` `section_ssh` | new section, trap-restored | ✓ VERIFIED | `sh scripts/smoke.sh ssh` → 66 passed, 0 failed; selector left on `old` |
| `README.md` | Phase 3 presenter narrative | ✓ VERIFIED | §"SSH on port 22 — the same one word", §`make verify` with the exit-code table, §"SSH" |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `proxy/nginx.conf` stream block | `proxy/active-backend.conf` | `include` — same path as the http block | ✓ WIRED (behaviourally: flip moved both protocols) |
| `scripts/verify.sh` | `client` container ssh | `docker compose exec -T client timeout 10 ssh …` | ✓ WIRED |
| `scripts/verify.sh` | proxy :9092 | `curl --max-time 5` | ✓ WIRED |
| `Makefile verify` | `scripts/verify.sh` | `sh scripts/verify.sh $(EXPECT)` | ✓ WIRED |
| `backend/entrypoint.sh` | `/etc/ssh/banner` | `envsubst` from the same `$VARS` allowlist as the HTTP surfaces | ✓ WIRED |
| `client/entrypoint.sh` | both backends' `authorizedkeysfile` | `demo-keys` volume, rw→ro | ✓ WIRED (key auth succeeds non-interactively to both) |
| stream `access_log` | `make logs` / `logs-demo` | `backend=` field name reused so the awk colouriser matches | ✓ WIRED (live lines observed) |

### Behavioural Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| SSH through proxy reaches active backend | `docker compose exec -T client ssh … demo@app.demo.test hostname` | `OLD server-old` + `server-old`, rc=0 | ✓ PASS |
| Identical command follows the flip | `flip.sh new` then same `$CMD` | `NEW server-new` + `server-new` | ✓ PASS |
| verify.sh success path | `sh scripts/verify.sh old` | two labelled lines, `OK`, rc=0, 0.33 s | ✓ PASS |
| verify.sh mismatch | `sh scripts/verify.sh new` on OLD | `MISMATCH`, rc=1 | ✓ PASS |
| verify.sh usage | `sh scripts/verify.sh` / `… bogus` | rc=2 both | ✓ PASS |
| verify.sh disagreement | `VERIFY_SSH_HOST=server-new sh scripts/verify.sh old` | `PROTOCOLS DISAGREE`, rc=3 | ✓ PASS |
| verify.sh cannot mask an ssh failure | `VERIFY_SSH_HOST=192.0.2.1 sh scripts/verify.sh old` | `UNREADABLE (exit 255)`, rc=1 | ✓ PASS |
| `make verify` | `make verify` | rc=0 | ✓ PASS |
| Phase 1 guard | `sh scripts/smoke.sh proxy` | `17 passed, 0 failed` | ✓ PASS |
| Full suite | `sh scripts/smoke.sh` | `186 passed, 0 failed` | ✓ PASS |
| Phase 4 mechanism reachable | temp known_hosts + flip | `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | ✓ PASS |

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| BACK-04 — banner states identity + hostname | ✓ SATISFIED | `OLD server-old` / `NEW server-new`, rendered from `BACKEND_ID`, `sshd -T banner` confirms source |
| BACK-05 — login over SSH with a known credential or key | ✓ SATISFIED | Key auth non-interactive to both backends; `passwordauthentication yes` retains the `demo:demo` fallback |
| SSH-01 — client SSHes to port 22 and lands on the active backend | ✓ SATISFIED | Proxy listens `0.0.0.0:22`; live hop returns the active backend |
| SSH-02 — `stream` module proxies raw TCP, not a redirect | ✓ SATISFIED | `stream { server { listen 22; proxy_pass $active_backend; } }`, no redirect directive |
| SSH-03 — session shows the active backend's banner | ✓ SATISFIED | Banner survives the stream hop, pre-auth, on stderr |
| CUT-04 — post-flip sessions land on `server-new` | ✓ SATISFIED | Identical command string, OLD → NEW across the flip |
| EVID-04 — script reports both protocols | ✓ SATISFIED | Two labelled lines on every run, fixed order, in all outcomes including failures |
| EVID-05 — non-zero on mismatch | ✓ SATISFIED | rc=1 mismatch, rc=3 disagreement, rc=2 usage; exit status read on the line after the capture, never through a pipe |

No orphaned requirements: ROADMAP maps 8 requirements to Phase 3 and all 8 are claimed by the phase plans and verified above.

### Anti-Patterns Found

None. `grep -nE '\b(TBD|FIXME|XXX|HACK|PLACEHOLDER|TODO)\b'` across every file this phase touched (`proxy/nginx.conf`, `proxy/active-backend.conf`, `compose.yaml`, `Makefile`, `scripts/verify.sh`, `scripts/smoke.sh`, `scripts/flip.sh`, `backend/*`, `client/*`, `README.md`) returned zero matches. The one deferred question Phase 2 left in `nginx.conf` is resolved in place and labelled `RESOLVED IN PHASE 3`, with a measurement rather than an assertion.

### Informational

- `proxy/active-backend.conf` currently carries mode `0600`. nginx's master runs as root and the mount is `:ro`, so nothing is affected and all 186 assertions pass; noting only in case a future phase adds a non-root reader.

### Human Verification Required

None. Every ROADMAP criterion and every focus-list item was resolved by executing a command against the live stack, including the two that are behaviour-dependent (the flip landing on SSH, and the exit-code honesty of `verify.sh` under a genuine ssh failure).

### Gaps Summary

No gaps. The headline claim — one file, one word, both protocols — is not merely configured but demonstrated: a single selector word moved HTTP and SSH together in both directions, and the script that asserts it fails honestly when told the wrong answer, when the protocols disagree, and when SSH itself cannot connect.

**Final state:** selector restored to `old`, all five services healthy, no host state touched, no source file modified.

---

*Verified: 2026-07-21T12:20:00Z*
*Verifier: Claude (gsd-verifier)*
